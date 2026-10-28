"""Single bounded worker; durable PostgreSQL queue, no Redis/Celery."""
import logging
import signal
import time
from datetime import timedelta
from sqlalchemy import select, delete, or_, and_
from .db import Session, Job, Match, Report, now
from .config import settings
from .services import calculate, store_report, s3, PermanentFailure

log=logging.getLogger('worker')
stopping=False

def run_once():
    with Session() as db:
        job=db.scalar(select(Job).where(or_(and_(Job.status=='pending',Job.available_at<=now()),and_(Job.status=='processing',Job.lease_until<now()))).order_by(Job.available_at).with_for_update(skip_locked=True).limit(1))
        if not job: return False
        model=Match if job.kind=='match' else Report
        obj=db.get(model,job.target_id) if job.kind!='delete_object' else None
        if job.status=='processing' and job.attempts>=settings.job_max_attempts:
            # Lease expired after the last attempt: the worker died mid-job (e.g. OOM). Stop retrying.
            job.status='failed'; job.failure_code='lease_expired'; job.finished_at=now()
            if obj: obj.status='failed'; obj.failure_code='lease_expired'
            db.commit(); return True
        job.status='processing'; job.attempts+=1; job.lease_until=now()+timedelta(minutes=settings.job_lease_minutes)
        job_id=job.id; kind=job.kind; target_id=job.target_id; payload=job.payload
        if obj: obj.status='processing'
        db.commit()
    result=None; error=None; permanent=False
    try:
        if kind=='match':
            if obj: result=calculate(obj.snapshot)
        elif kind=='report':
            with Session() as db:
                match=db.get(Match,obj.match_id) if obj else None
            if obj and match: result=store_report(obj,match)
        elif kind=='delete_object': s3().delete_object(Bucket=settings.s3_bucket,Key=payload['key'])
        else: raise PermanentFailure('unknown_job')
    except PermanentFailure as exc: error=str(exc); permanent=True
    except Exception:
        # Do not log upstream bodies, credentials, or birth data.
        error='temporary_processing_failure'
    with Session() as db:
        job=db.get(Job,job_id)
        obj=db.get(model,target_id) if kind!='delete_object' else None
        if not job or (kind!='delete_object' and not obj):
            if kind=='report' and result:
                db.add(Job(kind='delete_object',target_id=target_id,payload={'key':result[0]})); db.commit()
            return True
        if error:
            failed=permanent or job.attempts>=settings.job_max_attempts
            job.status='failed' if failed else 'pending'; job.failure_code=error
            job.available_at=now()+timedelta(seconds=10*2**job.attempts)
            if failed: job.finished_at=now()
            # Only identifiers and reason codes: never birth data, names, or upstream bodies.
            log.warning('job %s (%s) attempt %s failed: %s%s',job_id,kind,job.attempts,error,' (final)' if failed else '')
            if obj: obj.status='failed' if failed else 'pending'; obj.failure_code=error
        else:
            job.status='done'; job.finished_at=now()
            if obj:
                obj.status='ready'; obj.failure_code=None
                if kind=='match': obj.facts=result
                else: obj.object_key,obj.checksum=result
        db.commit()
    return True

def purge_finished():
    """Retention: drop finished job rows; failed rows are kept long enough for inspection."""
    with Session() as db:
        db.execute(delete(Job).where(Job.status.in_(('done','failed')),Job.finished_at<now()-timedelta(days=settings.job_retention_days)))
        db.commit()

def stop(*_):
    global stopping
    stopping=True

def main():
    logging.basicConfig(level=logging.INFO,format='%(asctime)s %(levelname)s %(name)s %(message)s')
    signal.signal(signal.SIGTERM,stop); signal.signal(signal.SIGINT,stop)
    last_purge=0.0
    while not stopping:
        if run_once(): continue
        if time.monotonic()-last_purge>3600: purge_finished(); last_purge=time.monotonic()
        time.sleep(settings.worker_poll_seconds)
if __name__=='__main__': main()
