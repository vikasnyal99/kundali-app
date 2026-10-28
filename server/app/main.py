import hashlib
import json
from datetime import timedelta
from collections import defaultdict, deque
from time import monotonic
import jwt
from fastapi import FastAPI, Depends, HTTPException, Request, Query
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select, delete, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session as DBSession
from .config import settings
from .db import User, Person, Match, Comparison, Report, Job, session, now
from .schemas import PersonInput, MatchInput, ComparisonInput, LocaleInput
from .places import search as search_places

app = FastAPI(title='KundliMilan AI', version='0.1.0')
app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins.split(','), allow_methods=['GET','POST','PATCH','DELETE'], allow_headers=['Authorization','Content-Type'])
auth = HTTPBearer(auto_error=False)
limits = defaultdict(deque)
@app.middleware('http')
async def guard(request: Request, call_next):
    if int(request.headers.get('content-length','0') or 0) > 65536:
        return JSONResponse({'error':{'code':'request_too_large','message':'Request exceeds limit'}},status_code=413)
    key = (request.client.host if request.client else 'unknown', request.url.path == '/v1/guest-sessions')
    if len(limits) > 5000: limits.clear()  # bound memory under many distinct client addresses
    q = limits[key]; current = monotonic()
    while q and q[0] < current - 60: q.popleft()
    if len(q) >= (10 if key[1] else 180): return JSONResponse({'error':{'code':'rate_limit','message':'Please try again shortly'}},status_code=429)
    q.append(current)
    return await call_next(request)
@app.exception_handler(HTTPException)
async def http_error(request, exc):
    return JSONResponse({'error':{'code':str(exc.detail),'message':str(exc.detail)}}, status_code=exc.status_code)
@app.exception_handler(RequestValidationError)
async def validation_error(request, exc):
    return JSONResponse({'error':{'code':'invalid_input','message':'Check the entered details','details':[{'field':'.'.join(map(str,e['loc'])),'message':e['msg']} for e in exc.errors()]}},status_code=422)
def user(credentials: HTTPAuthorizationCredentials | None = Depends(auth), db: DBSession = Depends(session)):
    try:
        claims = jwt.decode(credentials.credentials,settings.jwt_signing_key,algorithms=['HS256'],options={'require':['exp','sub']})
        result = db.get(User,claims['sub'])
        if not result: raise ValueError()
        return result
    except (AttributeError,ValueError,jwt.PyJWTError): raise HTTPException(401,'session_expired')
def owned(db, cls, id, owner):
    obj = db.get(cls,id)
    if not obj or obj.owner_id != owner: raise HTTPException(404,'not_found')
    return obj
def person_json(p): return {'id':p.id,'revision':p.revision,**p.data}
def match_json(m): return {'id':m.id,'status':m.status,'failure_code':m.failure_code,'people':m.snapshot['people'],'calculation':m.snapshot['settings'],'facts':m.facts}
def enqueue(db,kind,id,payload=None): db.add(Job(kind=kind,target_id=id,payload=payload or {}))
def create_match(db,owner,p1,p2):
    if p1 == p2: raise HTTPException(422,'same_person')
    people = [owned(db,Person,p,owner) for p in (p1,p2)]
    from .local_engine import VERSION, RULESET
    local = settings.astrology_mode == 'local_experimental'
    config = {'engine_version':VERSION if local else settings.astrology_engine_version,'ayanamsa':'lahiri','ruleset':RULESET if local else 'provider-validated-v1','mode':settings.astrology_mode}
    snapshot = {'people':[person_json(p) for p in people],'settings':config}
    key = hashlib.sha256(json.dumps({'owner':owner,**snapshot},sort_keys=True).encode()).hexdigest()
    existing = db.scalar(select(Match).where(Match.cache_key == key))
    if existing: return existing
    m = Match(owner_id=owner,cache_key=key,snapshot=snapshot)
    db.add(m); db.flush(); enqueue(db,'match',m.id)
    return m
@app.get('/health/live')
def live(): return {'status':'ok'}
@app.get('/health/ready')
def ready(db: DBSession = Depends(session)):
    db.execute(text('SELECT 1')); return {'status':'ok','calculation_available':settings.astrology_mode == 'local_experimental' or bool(settings.astrology_url)}
def issue(u): return {'token':jwt.encode({'sub':u.id,'exp':now()+timedelta(days=90)},settings.jwt_signing_key,algorithm='HS256'),'expires_in':7776000}
@app.post('/v1/guest-sessions',status_code=201)
def guest(db: DBSession = Depends(session)):
    u = User(); db.add(u); db.commit(); return issue(u)
@app.post('/v1/guest-sessions/refresh')
def refresh(u=Depends(user)): return issue(u)
@app.get('/v1/me/settings')
def get_settings(u=Depends(user)): return {'locale':u.locale}
@app.patch('/v1/me/settings')
def set_settings(body:LocaleInput,u=Depends(user),db:DBSession=Depends(session)):
    u.locale=body.locale; db.commit(); return {'locale':u.locale}
@app.get('/v1/places')
def place_suggestions(q:str=Query(min_length=2,max_length=64),u=Depends(user)): return search_places(q)
@app.get('/v1/people')
def people(u=Depends(user),db:DBSession=Depends(session)):
    return [person_json(p) for p in db.scalars(select(Person).where(Person.owner_id==u.id).order_by(Person.id))]
@app.post('/v1/people',status_code=201)
def add_person(body:PersonInput,u=Depends(user),db:DBSession=Depends(session)):
    p=Person(owner_id=u.id,data=body.stored()); db.add(p); db.commit(); return person_json(p)
@app.get('/v1/people/{id}')
def get_person(id:str,u=Depends(user),db:DBSession=Depends(session)): return person_json(owned(db,Person,id,u.id))
def invalidate(db,owner,person_id):
    """Drop cached matches, reports and comparisons that used this person; schedule S3 cleanup."""
    removed=set()
    for m in list(db.scalars(select(Match).where(Match.owner_id==owner))):
        if not any(p['id']==person_id for p in m.snapshot['people']): continue
        for r in db.scalars(select(Report).where(Report.match_id==m.id)):
            if r.object_key: enqueue(db,'delete_object',r.id,{'key':r.object_key})
            db.execute(delete(Job).where(Job.target_id==r.id,Job.kind=='report')); db.delete(r)
        db.execute(delete(Job).where(Job.target_id==m.id)); db.delete(m); removed.add(m.id)
    for c in db.scalars(select(Comparison).where(Comparison.owner_id==owner)):
        if c.person1_id==person_id or removed.intersection(c.match_ids): db.delete(c)
    db.flush()
@app.patch('/v1/people/{id}')
def edit_person(id:str,body:PersonInput,u=Depends(user),db:DBSession=Depends(session)):
    p=owned(db,Person,id,u.id); invalidate(db,u.id,id); p.data=body.stored(); p.revision+=1; db.commit(); return person_json(p)
@app.delete('/v1/people/{id}',status_code=204)
def remove_person(id:str,u=Depends(user),db:DBSession=Depends(session)):
    p=owned(db,Person,id,u.id); invalidate(db,u.id,id); db.delete(p); db.commit()
@app.post('/v1/matches',status_code=202)
def add_match(body:MatchInput,u=Depends(user),db:DBSession=Depends(session)):
    try:
        m=create_match(db,u.id,body.person1_id,body.person2_id); db.commit(); return match_json(m)
    except IntegrityError:
        db.rollback(); m=create_match(db,u.id,body.person1_id,body.person2_id); db.commit(); return match_json(m)
@app.get('/v1/matches')
def matches(u=Depends(user),db:DBSession=Depends(session)):
    return [match_json(m) for m in db.scalars(select(Match).where(Match.owner_id==u.id))]
@app.get('/v1/matches/{id}')
def get_match(id:str,u=Depends(user),db:DBSession=Depends(session)): return match_json(owned(db,Match,id,u.id))
@app.post('/v1/matches/{id}/retry',status_code=202)
def retry_match(id:str,u=Depends(user),db:DBSession=Depends(session)):
    m=owned(db,Match,id,u.id)
    if m.status=='failed':
        m.status='pending'; m.failure_code=None; enqueue(db,'match',id); db.commit()
    return match_json(m)
@app.post('/v1/comparisons',status_code=202)
def compare(body:ComparisonInput,u=Depends(user),db:DBSession=Depends(session)):
    def build():
        ms=[create_match(db,u.id,body.person1_id,p) for p in body.person2_ids]
        c=Comparison(owner_id=u.id,person1_id=body.person1_id,match_ids=[m.id for m in ms]); db.add(c); db.commit()
        return {'id':c.id,'person1_id':c.person1_id,'results':[match_json(m) for m in ms]}
    try: return build()
    except IntegrityError: db.rollback(); return build()  # a concurrent request created a shared match first
@app.get('/v1/comparisons/{id}')
def comparison(id:str,u=Depends(user),db:DBSession=Depends(session)):
    c=owned(db,Comparison,id,u.id)
    ms=[owned(db,Match,i,u.id) for i in c.match_ids]
    # Ready results first by score; ties and unscored rows keep a deterministic name/id order.
    ms.sort(key=lambda m:(-(m.facts['score']['earned'] if m.status=='ready' else -1),m.snapshot['people'][1]['display_name'].casefold(),m.snapshot['people'][1]['id']))
    return {'id':c.id,'person1_id':c.person1_id,'results':[match_json(m) for m in ms]}
def report_json(r): return {'id':r.id,'match_id':r.match_id,'status':r.status,'locale':r.locale,'failure_code':r.failure_code}
@app.get('/v1/reports')
def reports(u=Depends(user),db:DBSession=Depends(session)):
    return [report_json(r) for r in db.scalars(select(Report).where(Report.owner_id==u.id))]
@app.post('/v1/matches/{id}/reports',status_code=202)
def make_report(id:str,body:LocaleInput,u=Depends(user),db:DBSession=Depends(session)):
    m=owned(db,Match,id,u.id)
    if m.status!='ready': raise HTTPException(409,'match_not_ready')
    r=db.scalar(select(Report).where(Report.match_id==id,Report.locale==body.locale))
    if not r:
        try:
            r=Report(owner_id=u.id,match_id=id,locale=body.locale); db.add(r); db.flush(); enqueue(db,'report',r.id)
        except IntegrityError:
            db.rollback(); r=db.scalar(select(Report).where(Report.match_id==id,Report.locale==body.locale))
    elif r.status=='failed': r.status='pending'; r.failure_code=None; enqueue(db,'report',r.id)
    db.commit(); return report_json(r)
@app.get('/v1/reports/{id}')
def report(id:str,u=Depends(user),db:DBSession=Depends(session)): return report_json(owned(db,Report,id,u.id))
@app.post('/v1/reports/{id}/download-url')
def download(id:str,u=Depends(user),db:DBSession=Depends(session)):
    r=owned(db,Report,id,u.id)
    if r.status!='ready': raise HTTPException(409,'report_not_ready')
    from .services import s3
    url=s3().generate_presigned_url('get_object',Params={'Bucket':settings.s3_bucket,'Key':r.object_key},ExpiresIn=settings.report_presign_ttl_seconds)
    return {'url':url,'expires_at':now()+timedelta(seconds=settings.report_presign_ttl_seconds)}
@app.get('/v1/me/export')
def export(u=Depends(user),db:DBSession=Depends(session)):
    return {'people':people(u,db),'matches':matches(u,db),'reports':reports(u,db),'locale':u.locale}
@app.delete('/v1/me',status_code=204)
def erase(u=Depends(user),db:DBSession=Depends(session)):
    for p in list(db.scalars(select(Person).where(Person.owner_id==u.id))): invalidate(db,u.id,p.id); db.delete(p)
    db.delete(u); db.commit()
