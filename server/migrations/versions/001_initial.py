"""Initial durable app and job tables.

Explicit DDL (not metadata.create_all) so this revision stays fixed when models change;
add a new revision for every later schema change.
"""
from alembic import op
import sqlalchemy as sa
revision='001'
down_revision=None

def upgrade():
    tz=sa.DateTime(timezone=True)
    op.create_table('app_users',sa.Column('id',sa.String(36),primary_key=True),sa.Column('locale',sa.String(),nullable=False),sa.Column('created_at',tz,nullable=False))
    op.create_table('people',sa.Column('id',sa.String(36),primary_key=True),sa.Column('owner_id',sa.String(36),sa.ForeignKey('app_users.id'),nullable=False,index=True),sa.Column('data',sa.JSON(),nullable=False),sa.Column('revision',sa.Integer(),nullable=False))
    op.create_table('matches',sa.Column('id',sa.String(36),primary_key=True),sa.Column('owner_id',sa.String(36),sa.ForeignKey('app_users.id'),nullable=False,index=True),sa.Column('cache_key',sa.String(64),nullable=False,unique=True),sa.Column('snapshot',sa.JSON(),nullable=False),sa.Column('status',sa.String(),nullable=False),sa.Column('facts',sa.JSON(),nullable=True),sa.Column('failure_code',sa.String(),nullable=True))
    op.create_table('comparisons',sa.Column('id',sa.String(36),primary_key=True),sa.Column('owner_id',sa.String(36),sa.ForeignKey('app_users.id'),nullable=False,index=True),sa.Column('person1_id',sa.String(),nullable=False),sa.Column('match_ids',sa.JSON(),nullable=False))
    op.create_table('reports',sa.Column('id',sa.String(36),primary_key=True),sa.Column('owner_id',sa.String(36),sa.ForeignKey('app_users.id'),nullable=False,index=True),sa.Column('match_id',sa.String(36),sa.ForeignKey('matches.id'),nullable=False),sa.Column('locale',sa.String(),nullable=False),sa.Column('status',sa.String(),nullable=False),sa.Column('object_key',sa.String(),nullable=True),sa.Column('checksum',sa.String(),nullable=True),sa.Column('failure_code',sa.String(),nullable=True),sa.UniqueConstraint('match_id','locale'))
    op.create_table('jobs',sa.Column('id',sa.String(36),primary_key=True),sa.Column('kind',sa.String(),nullable=False),sa.Column('target_id',sa.String(),nullable=False),sa.Column('payload',sa.JSON(),nullable=False),sa.Column('status',sa.String(),nullable=False),sa.Column('attempts',sa.Integer(),nullable=False),sa.Column('available_at',tz,nullable=False),sa.Column('lease_until',tz,nullable=True),sa.Column('failure_code',sa.Text(),nullable=True),sa.Column('finished_at',tz,nullable=True))
    op.create_index('ix_jobs_claim','jobs',['status','available_at'])

def downgrade():
    for table in ('jobs','reports','comparisons','matches','people','app_users'): op.drop_table(table)
