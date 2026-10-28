import pytest
from app.config import Settings

GOOD=dict(app_env='production',database_url='postgresql+psycopg://u:p@db/k',jwt_signing_key='x'*48,cors_origins='https://app.example.com')

@pytest.mark.parametrize('override',[{'jwt_signing_key':'development-only-change-before-deployment'},{'jwt_signing_key':'short'},{'database_url':'sqlite:///k.db'},
    {'cors_origins':'*'},{'cors_origins':'http://app.example.com'},{'astrology_mode':'local_experimental'}])
def test_production_refuses_unsafe_settings(override):
    with pytest.raises(RuntimeError): Settings(**{**GOOD,**override}).check()

def test_production_accepts_safe_settings():
    Settings(**GOOD).check()

def test_aws_presigned_urls_use_regional_virtual_host(monkeypatch):
    from app import services
    monkeypatch.setattr(services.settings,'s3_endpoint_url',None); monkeypatch.setattr(services.settings,'s3_region','ap-south-1')
    monkeypatch.setenv('AWS_ACCESS_KEY_ID','test'); monkeypatch.setenv('AWS_SECRET_ACCESS_KEY','test')
    url=services.s3().generate_presigned_url('get_object',Params={'Bucket':'kundali-milan','Key':'reports/a.pdf'},ExpiresIn=60)
    assert url.startswith('https://kundali-milan.s3.ap-south-1.amazonaws.com/reports/a.pdf?') and 'X-Amz-Algorithm=AWS4-HMAC-SHA256' in url
