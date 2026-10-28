from datetime import datetime, timezone
from uuid import uuid4
from sqlalchemy import create_engine, String, JSON, DateTime, Integer, ForeignKey, Text, Index, UniqueConstraint
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker
from .config import settings

def now(): return datetime.now(timezone.utc)
def uid(): return str(uuid4())
class Base(DeclarativeBase): pass
class User(Base):
    __tablename__ = 'app_users'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    locale: Mapped[str] = mapped_column(default='en')
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
class Person(Base):
    __tablename__ = 'people'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    owner_id: Mapped[str] = mapped_column(ForeignKey('app_users.id'), index=True)
    data: Mapped[dict] = mapped_column(JSON)
    revision: Mapped[int] = mapped_column(default=1)
class Match(Base):
    __tablename__ = 'matches'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    owner_id: Mapped[str] = mapped_column(ForeignKey('app_users.id'), index=True)
    cache_key: Mapped[str] = mapped_column(String(64), unique=True)
    snapshot: Mapped[dict] = mapped_column(JSON)
    status: Mapped[str] = mapped_column(default='pending')
    facts: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    failure_code: Mapped[str | None] = mapped_column(nullable=True)
class Comparison(Base):
    __tablename__ = 'comparisons'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    owner_id: Mapped[str] = mapped_column(ForeignKey('app_users.id'), index=True)
    person1_id: Mapped[str]
    match_ids: Mapped[list] = mapped_column(JSON)
class Report(Base):
    __tablename__ = 'reports'
    __table_args__ = (UniqueConstraint('match_id','locale'),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    owner_id: Mapped[str] = mapped_column(ForeignKey('app_users.id'), index=True)
    match_id: Mapped[str] = mapped_column(ForeignKey('matches.id'))
    locale: Mapped[str]
    status: Mapped[str] = mapped_column(default='pending')
    object_key: Mapped[str | None] = mapped_column(nullable=True)
    checksum: Mapped[str | None] = mapped_column(nullable=True)
    failure_code: Mapped[str | None] = mapped_column(nullable=True)
class Job(Base):
    __tablename__ = 'jobs'
    __table_args__ = (Index('ix_jobs_claim','status','available_at'),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    kind: Mapped[str]
    target_id: Mapped[str]
    payload: Mapped[dict] = mapped_column(JSON, default=dict)
    status: Mapped[str] = mapped_column(default='pending')
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    available_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    lease_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    failure_code: Mapped[str | None] = mapped_column(Text, nullable=True)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
engine = create_engine(settings.database_url, **({'connect_args': {'check_same_thread': False}} if settings.database_url.startswith('sqlite') else {'pool_pre_ping': True, 'pool_size': 3, 'max_overflow': 2}))
Session = sessionmaker(engine, expire_on_commit=False)
def session():
    with Session() as db: yield db
