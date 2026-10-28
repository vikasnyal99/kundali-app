import os
os.environ['DATABASE_URL']='sqlite://'
from sqlalchemy import create_engine
from sqlalchemy.pool import StaticPool
from sqlalchemy.orm import sessionmaker
import pytest
from fastapi.testclient import TestClient
from app import db, main, worker
from app.schemas import PersonInput
from app.services import validate_facts, PermanentFailure

@pytest.fixture()
def client(monkeypatch):
    engine=create_engine('sqlite://',connect_args={'check_same_thread':False},poolclass=StaticPool)
    db.Base.metadata.create_all(engine)
    factory=sessionmaker(engine,expire_on_commit=False)
    def session():
        with factory() as s: yield s
    main.app.dependency_overrides[db.session]=session
    monkeypatch.setattr(worker,'Session',factory)
    main.limits.clear()
    with TestClient(main.app) as c: yield c
    main.app.dependency_overrides.clear()
def token(c): return {'Authorization':'Bearer '+c.post('/v1/guest-sessions').json()['token']}
def person(c,h,name='Person',**overrides):
    payload=dict(display_name=name,birth_date='1997-09-14',birth_time_local='09:30:00',birth_timezone='Asia/Kolkata',birth_place_name='Delhi',latitude=28.6139,longitude=77.209,time_accuracy='exact')
    return c.post('/v1/people',headers=h,json={**payload,**overrides})
def test_ownership(client):
    a,b=token(client),token(client)
    p=person(client,a).json()
    assert client.get('/v1/people/'+p['id'],headers=b).status_code==404
    assert client.get('/v1/people',headers=b).json()==[]
    assert client.get('/v1/people').status_code==401

def test_validation_dst(client):
    h=token(client)
    assert person(client,h,birth_timezone='Bad/Zone').status_code==422
    assert person(client,h,birth_date='2024-03-10',birth_time_local='02:30:00',birth_timezone='America/New_York').status_code==422
    assert person(client,h,birth_date='2024-11-03',birth_time_local='01:30:00',birth_timezone='America/New_York').status_code==422
    p=person(client,h,birth_date='2024-11-03',birth_time_local='01:30:00',birth_timezone='America/New_York',fold=1).json()
    assert p['birth_utc']=='2024-11-03T06:30:00+00:00'

def test_comparison_cache_and_failure(client):
    h=token(client); ps=[person(client,h,str(i)).json()['id'] for i in range(4)]
    body={'person1_id':ps[0],'person2_ids':ps[1:]}
    c=client.post('/v1/comparisons',headers=h,json=body).json()
    c2=client.post('/v1/comparisons',headers=h,json={**body,'person2_ids':ps[1:3]}).json()
    assert c['person1_id']==c2['person1_id']==ps[0]
    assert c['results'][0]['id']==c2['results'][0]['id']
    assert len(client.get('/v1/matches',headers=h).json())==3
    while worker.run_once(): pass
    results=client.get('/v1/comparisons/'+c['id'],headers=h).json()['results']
    assert all(r['failure_code']=='calculation_unavailable' and r['facts'] is None for r in results)
    assert client.post('/v1/comparisons',headers=h,json={'person1_id':ps[0],'person2_ids':[ps[1],ps[1]]}).status_code==422
    assert client.post('/v1/matches/'+results[0]['id']+'/reports',headers=h,json={}).status_code==409

def test_delete_invalidation(client):
    h=token(client); p1=person(client,h).json(); p2=person(client,h,'Second').json()
    m=client.post('/v1/matches',headers=h,json={'person1_id':p1['id'],'person2_id':p2['id']}).json()
    assert client.delete('/v1/people/'+p1['id'],headers=h).status_code==204
    assert client.get('/v1/matches/'+m['id'],headers=h).status_code==404
    assert client.delete('/v1/me',headers=h).status_code==204
    assert client.get('/v1/people',headers=h).status_code==401

def test_reject_fake_or_inconsistent_facts():
    with pytest.raises(PermanentFailure): validate_facts({'score':{'earned':36,'possible':36,'kootas':[]}})
