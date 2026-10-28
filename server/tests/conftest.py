"""Shared fixtures. Integration services are opt-in through environment variables:

TEST_POSTGRES_URL  disposable PostgreSQL (schema is DROPPED), e.g. postgresql+psycopg://kundli:local-dev-only@127.0.0.1:55432/kundli
TEST_S3_ENDPOINT   disposable S3-compatible endpoint, e.g. http://127.0.0.1:59000 (with TEST_S3_ACCESS_KEY / TEST_S3_SECRET_KEY)
Never point these at shared or production services.
"""
import os
# Hermetic: a developer's .env must not change test behaviour (environment variables override it).
os.environ.update(DATABASE_URL='sqlite://',APP_ENV='test',ASTROLOGY_MODE='disabled',ASTROLOGY_URL='',S3_BUCKET='',S3_ENDPOINT_URL='')
from pathlib import Path
from types import SimpleNamespace
import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from app import db, main, worker

PG_URL=os.environ.get('TEST_POSTGRES_URL')
S3_ENDPOINT=os.environ.get('TEST_S3_ENDPOINT')
needs_pg=pytest.mark.skipif(not PG_URL,reason='set TEST_POSTGRES_URL to a disposable database')
needs_s3=pytest.mark.skipif(not S3_ENDPOINT,reason='set TEST_S3_ENDPOINT to a disposable S3-compatible service')
SERVER=Path(__file__).parents[1]

def alembic_config(connection):
    cfg=Config(str(SERVER/'alembic.ini')); cfg.set_main_option('script_location',str(SERVER/'migrations'))
    cfg.attributes['connection']=connection
    return cfg

@pytest.fixture()
def database(monkeypatch):
    """PostgreSQL migrated by Alembic when configured, otherwise in-memory SQLite."""
    if PG_URL:
        engine=create_engine(PG_URL,pool_size=5)
        with engine.begin() as c: c.execute(text('DROP SCHEMA public CASCADE; CREATE SCHEMA public'))
        with engine.begin() as c: command.upgrade(alembic_config(c),'head')
    else:
        engine=create_engine('sqlite://',connect_args={'check_same_thread':False},poolclass=StaticPool)
        db.Base.metadata.create_all(engine)
    factory=sessionmaker(engine,expire_on_commit=False)
    def session():
        with factory() as s: yield s
    main.app.dependency_overrides[db.session]=session
    monkeypatch.setattr(worker,'Session',factory)
    main.limits.clear()
    yield SimpleNamespace(engine=engine,factory=factory,postgres=bool(PG_URL))
    main.app.dependency_overrides.clear()
    engine.dispose()

@pytest.fixture()
def client(database):
    with TestClient(main.app) as c: yield c

def token(c): return {'Authorization':'Bearer '+c.post('/v1/guest-sessions').json()['token']}

def person(c,h,name='Person',**overrides):
    payload=dict(display_name=name,birth_date='1997-09-14',birth_time_local='09:30:00',birth_timezone='Asia/Kolkata',birth_place_name='Delhi',latitude=28.6139,longitude=77.209,time_accuracy='exact')
    r=c.post('/v1/people',headers=h,json={**payload,**overrides}); assert r.status_code==201,r.text
    return r.json()

def drain():
    while worker.run_once(): pass
