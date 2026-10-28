from alembic import context
from app.db import Base,engine
# Online migrations only. DATABASE_URL comes from the app settings unless a caller
# (e.g. the integration tests) passes a connection in config.attributes.
def run(connection):
    context.configure(connection=connection,target_metadata=Base.metadata,compare_type=True)
    with context.begin_transaction(): context.run_migrations()
if (connection:=context.config.attributes.get('connection')) is not None: run(connection)
else:
    with engine.connect() as connection: run(connection)
