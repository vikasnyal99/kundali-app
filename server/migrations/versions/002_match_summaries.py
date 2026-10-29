"""Cached match summaries (explanation text per locale)."""
from alembic import op
import sqlalchemy as sa
revision='002'
down_revision='001'

def upgrade():
    op.add_column('matches',sa.Column('summaries',sa.JSON(),nullable=True))

def downgrade():
    op.drop_column('matches','summaries')
