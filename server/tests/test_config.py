import pytest
from app.config import Settings

GOOD=dict(app_env='production',database_url='postgresql+psycopg://u:p@db/k',jwt_signing_key='x'*48,cors_origins='https://app.example.com')

@pytest.mark.parametrize('override',[{'jwt_signing_key':'development-only-change-before-deployment'},{'jwt_signing_key':'short'},{'database_url':'sqlite:///k.db'},
    {'cors_origins':'*'},{'cors_origins':'http://app.example.com'},{'astrology_mode':'local_experimental'}])
def test_production_refuses_unsafe_settings(override):
    with pytest.raises(RuntimeError): Settings(**{**GOOD,**override}).check()

def test_production_accepts_safe_settings():
    Settings(**GOOD).check()
