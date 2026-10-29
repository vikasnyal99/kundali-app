"""Persistence, ownership, comparison and worker behaviour. Runs on SQLite by default and on
PostgreSQL (with Alembic migrations) when TEST_POSTGRES_URL is set; some checks need PostgreSQL."""
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from fastapi.testclient import TestClient
from sqlalchemy import select, text, update
from app import db, main, worker
from app.db import Job, Match, Report, Comparison, now
from app.services import PermanentFailure
from conftest import needs_pg, alembic_config, token, person, drain

# Test-only stand-in for the calculation engine: fixed points per candidate name, NOT astrology.
SCORES={'Bela':27.0,'Zara':27.0,'Asha':20.0,'Kiran':20.0}
def fake_facts(snapshot):
    name=snapshot['people'][1]['display_name']
    if name not in SCORES: raise PermanentFailure('calculation_unavailable')
    return {'score':{'earned':SCORES[name],'possible':36,'kootas':[]},'calculation':{'engine':'test-double'},'warnings':[],'manglik':{'status':'unavailable'}}

@pytest.fixture()
def calc(monkeypatch):
    monkeypatch.setattr(worker,'calculate',fake_facts)

def jobs(database,**where):
    with database.factory() as s: return list(s.scalars(select(Job).filter_by(**where)))

def ready_report(database,client,h,match_id,key='reports/test.pdf'):
    r=client.post(f'/v1/matches/{match_id}/reports',headers=h,json={'locale':'en'}).json()
    with database.factory() as s:
        s.execute(update(Report).where(Report.id==r['id']).values(status='ready',object_key=key)); s.execute(update(Job).where(Job.target_id==r['id']).values(status='done')); s.commit()
    return r['id']

@needs_pg
def test_migration_matches_models_and_round_trips(database):
    with database.engine.connect() as c:
        assert compare_metadata(MigrationContext.configure(c,opts={'compare_type':True}),db.Base.metadata)==[]
        assert c.scalar(text('select version_num from alembic_version'))=='001'
    with database.engine.begin() as c:
        command.upgrade(alembic_config(c),'head')  # re-running is a no-op
        command.downgrade(alembic_config(c),'base')
        assert c.scalar(text("select count(*) from information_schema.tables where table_schema='public' and table_name<>'alembic_version'"))==0
        command.upgrade(alembic_config(c),'head')
    with database.engine.connect() as c:
        assert {'app_users','people','matches','comparisons','reports','jobs'}<=set(c.scalars(text("select table_name from information_schema.tables where table_schema='public'")))

def test_ownership_isolation(database,client,calc):
    a,b=token(client),token(client)
    p1,p2,p3=(person(client,a,n)['id'] for n in ('Owner','Bela','Zara'))
    m=client.post('/v1/matches',headers=a,json={'person1_id':p1,'person2_id':p2}).json()
    cmp=client.post('/v1/comparisons',headers=a,json={'person1_id':p1,'person2_ids':[p2,p3]}).json()
    drain()
    rid=ready_report(database,client,a,m['id'])
    for method,path in [('GET',f'/v1/people/{p1}'),('DELETE',f'/v1/people/{p1}'),('GET',f"/v1/matches/{m['id']}"),('POST',f"/v1/matches/{m['id']}/retry"),('GET',f"/v1/comparisons/{cmp['id']}"),('GET',f'/v1/reports/{rid}'),('POST',f'/v1/reports/{rid}/download-url')]:
        assert client.request(method,path,headers=b).status_code==404,(method,path)
    assert client.patch(f'/v1/people/{p1}',headers=b,json={'display_name':'x','birth_date':'1990-01-01','birth_time_local':'10:00:00','birth_timezone':'UTC','birth_place_name':'x','latitude':0,'longitude':0}).status_code==404
    assert client.post(f"/v1/matches/{m['id']}/reports",headers=b,json={'locale':'en'}).status_code==404
    # B cannot reference A's people in its own requests either.
    mine=person(client,b,'Mine')['id']
    assert client.post('/v1/matches',headers=b,json={'person1_id':mine,'person2_id':p2}).status_code==404
    assert client.post('/v1/comparisons',headers=b,json={'person1_id':mine,'person2_ids':[p2,p3]}).status_code==404
    export=client.get('/v1/me/export',headers=b).json()
    assert [p['id'] for p in export['people']]==[mine] and export['matches']==export['reports']==[]
    assert client.delete('/v1/me',headers=b).status_code==204
    assert len(client.get('/v1/people',headers=a).json())==3 and client.get(f'/v1/reports/{rid}',headers=a).json()['status']=='ready'

def test_comparison_order_ties_cache_and_invalidation(database,client,calc):
    h=token(client)
    ids={n:person(client,h,n)['id'] for n in ('Fixed','Zara','Asha','Bela','Mira','Other')}
    body={'person1_id':ids['Fixed'],'person2_ids':[ids[n] for n in ('Zara','Asha','Bela','Mira')]}
    cmp=client.post('/v1/comparisons',headers=h,json=body).json(); drain()
    rows=client.get(f"/v1/comparisons/{cmp['id']}",headers=h).json()['results']
    # Score descending, ties by name, unscored last; Person 1 identical everywhere.
    assert [r['people'][1]['display_name'] for r in rows]==['Bela','Zara','Asha','Mira']
    assert [r['status'] for r in rows]==['ready','ready','ready','failed'] and rows[3]['facts'] is None
    assert {r['people'][0]['id'] for r in rows}=={ids['Fixed']}
    first={r['people'][1]['display_name']:r['id'] for r in rows}
    # Editing an unrelated person keeps the comparison and cached matches.
    other=client.get(f"/v1/people/{ids['Other']}",headers=h).json()
    edit=lambda name,**change:client.patch(f'/v1/people/{ids[name]}',headers=h,json={k:v for k,v in {**client.get(f'/v1/people/{ids[name]}',headers=h).json(),**change}.items() if k not in ('id','revision','birth_utc')})
    assert edit('Other',birth_place_name='Agra').status_code==200 and other['revision']==1
    assert client.get(f"/v1/comparisons/{cmp['id']}",headers=h).status_code==200
    # Editing a candidate invalidates only matches/comparisons using that candidate.
    assert edit('Asha',birth_time_local='10:00:00').json()['revision']==2
    assert client.get(f"/v1/comparisons/{cmp['id']}",headers=h).status_code==404
    assert client.get(f"/v1/matches/{first['Asha']}",headers=h).status_code==404
    again=client.post('/v1/comparisons',headers=h,json=body).json()
    again_ids={r['people'][1]['display_name']:r['id'] for r in again['results']}
    assert again_ids['Bela']==first['Bela'] and again_ids['Asha']!=first['Asha']
    assert next(r for r in again['results'] if r['id']==again_ids['Asha'])['people'][1]['revision']==2
    # Changing Person 1 invalidates every pairing with them.
    edit('Fixed',birth_place_name='Pune')
    assert client.get('/v1/matches',headers=h).json()==[]

@needs_pg
def test_concurrent_identical_comparisons_share_matches(database,calc):
    with TestClient(main.app) as c:
        h=token(c); ids=[person(c,h,n)['id'] for n in ('Fixed','Bela','Zara','Asha')]
        body={'person1_id':ids[0],'person2_ids':ids[1:]}
        def post(_):
            with TestClient(main.app) as own: return own.post('/v1/comparisons',headers=h,json=body)
        with ThreadPoolExecutor(4) as pool: responses=list(pool.map(post,range(4)))
        assert [r.status_code for r in responses]==[202]*4
        assert len({tuple(sorted(x['id'] for x in r.json()['results'])) for r in responses})==1
        assert len(c.get('/v1/matches',headers=h).json())==3

@needs_pg
def test_worker_skips_rows_locked_by_another_worker(database,client,calc):
    h=token(client); a,b=person(client,h,'Fixed')['id'],person(client,h,'Bela')['id']
    client.post('/v1/matches',headers=h,json={'person1_id':a,'person2_id':b})
    with database.engine.connect() as other:
        other.begin(); other.execute(text("select id from jobs where status='pending' for update"))
        assert worker.run_once() is False  # SKIP LOCKED: no second worker can take a leased row
        other.rollback()
    assert worker.run_once() is True

def test_expired_lease_is_recovered_then_capped(database,client,calc):
    h=token(client); a=person(client,h,'Fixed')['id']
    m1=client.post('/v1/matches',headers=h,json={'person1_id':a,'person2_id':person(client,h,'Bela')['id']}).json()
    m2=client.post('/v1/matches',headers=h,json={'person1_id':a,'person2_id':person(client,h,'Zara')['id']}).json()
    with database.factory() as s:
        s.execute(update(Job).where(Job.target_id==m1['id']).values(status='processing',attempts=1,lease_until=now()-timedelta(minutes=1)))
        s.execute(update(Job).where(Job.target_id==m2['id']).values(status='processing',attempts=3,lease_until=now()-timedelta(minutes=1)))
        s.commit()
    drain()
    assert client.get(f"/v1/matches/{m1['id']}",headers=h).json()['status']=='ready'
    capped=client.get(f"/v1/matches/{m2['id']}",headers=h).json()
    assert (capped['status'],capped['failure_code'])==('failed','lease_expired')
    assert client.post(f"/v1/matches/{m2['id']}/retry",headers=h).json()['status']=='pending'
    drain()
    assert client.get(f"/v1/matches/{m2['id']}",headers=h).json()['status']=='ready'

def test_transient_failures_back_off_then_fail(database,client,monkeypatch):
    def boom(_): raise RuntimeError('upstream timeout with sensitive body')
    monkeypatch.setattr(worker,'calculate',boom)
    h=token(client); m=client.post('/v1/matches',headers=h,json={'person1_id':person(client,h,'A')['id'],'person2_id':person(client,h,'B')['id']}).json()
    for attempt in (1,2,3):
        assert worker.run_once() is True
        job=jobs(database,target_id=m['id'])[0]
        assert job.attempts==attempt and job.failure_code=='temporary_processing_failure'
        if attempt<3:
            assert job.status=='pending' and worker.run_once() is False  # backoff: not yet available
            with database.factory() as s: s.execute(update(Job).values(available_at=now())); s.commit()
    assert job.status=='failed' and job.finished_at is not None
    assert client.get(f"/v1/matches/{m['id']}",headers=h).json()['status']=='failed'

def test_purge_keeps_recent_and_unfinished_jobs(database,monkeypatch):
    with database.factory() as s:
        s.add_all([Job(kind='match',target_id='old',status='done',finished_at=now()-timedelta(days=30)),Job(kind='match',target_id='recent',status='done',finished_at=now()),Job(kind='match',target_id='queued')]); s.commit()
    worker.purge_finished()
    assert {j.target_id for j in jobs(database)}=={'recent','queued'}

def test_person_deleted_while_match_is_calculating(database,client):
    h=token(client); a,b=person(client,h,'Fixed')['id'],person(client,h,'Bela')['id']
    m=client.post('/v1/matches',headers=h,json={'person1_id':a,'person2_id':b}).json()
    def delete_midway(snapshot):
        assert client.delete(f'/v1/people/{b}',headers=h).status_code==204
        return fake_facts(snapshot)
    worker.calculate=delete_midway
    try: assert worker.run_once() is True
    finally: worker.calculate=__import__('app.services',fromlist=['calculate']).calculate
    assert client.get(f"/v1/matches/{m['id']}",headers=h).status_code==404
    assert jobs(database)==[]

def test_person_deleted_while_report_uploads_schedules_object_cleanup(database,client,calc,monkeypatch):
    h=token(client); a,b=person(client,h,'Fixed')['id'],person(client,h,'Bela')['id']
    m=client.post('/v1/matches',headers=h,json={'person1_id':a,'person2_id':b}).json(); drain()
    deleted=[]
    def upload_then_race(report,match,summary=None):
        assert client.delete(f'/v1/people/{a}',headers=h).status_code==204
        return f'reports/{report.owner_id}/{match.id}/{report.id}.pdf','checksum'
    monkeypatch.setattr(worker,'store_report',upload_then_race)
    monkeypatch.setattr(worker,'s3',lambda:type('S3',(),{'delete_object':lambda self,**kw:deleted.append(kw['Key'])})())
    rid=client.post(f"/v1/matches/{m['id']}/reports",headers=h,json={'locale':'hi'}).json()['id']
    drain()
    assert deleted==[f"reports/{jobs_owner(database)}/{m['id']}/{rid}.pdf"]
    assert {j.kind for j in jobs(database)}=={'delete_object'} and all(j.status=='done' for j in jobs(database))

def jobs_owner(database):
    with database.factory() as s: return s.scalar(text('select id from app_users'))

def test_erasing_account_queues_s3_deletion(database,client,calc):
    h=token(client); a,b=person(client,h,'Fixed')['id'],person(client,h,'Bela')['id']
    m=client.post('/v1/matches',headers=h,json={'person1_id':a,'person2_id':b}).json(); drain()
    ready_report(database,client,h,m['id'],key='reports/u/m/r.pdf')
    assert client.delete('/v1/me',headers=h).status_code==204
    assert [(j.kind,j.payload) for j in jobs(database,status='pending')]==[('delete_object',{'key':'reports/u/m/r.pdf'})]
    with database.factory() as s:
        assert s.scalar(select(Match))is None and s.scalar(select(Comparison)) is None and s.scalar(select(Report)) is None

def test_duplicate_report_requests_share_one_report(database,client,calc):
    h=token(client); m=client.post('/v1/matches',headers=h,json={'person1_id':person(client,h,'Fixed')['id'],'person2_id':person(client,h,'Bela')['id']}).json(); drain()
    ids={client.post(f"/v1/matches/{m['id']}/reports",headers=h,json={'locale':'en'}).json()['id'] for _ in range(3)}
    assert len(ids)==1 and len(jobs(database,kind='report'))==1
