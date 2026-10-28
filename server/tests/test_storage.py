"""Private S3-compatible storage and the draft -> calculation -> stored report -> download path.
Needs TEST_S3_ENDPOINT (e.g. MinIO from infra/compose.dev.yml); never a shared or production bucket.
Set TEST_S3_EMULATOR=1 for moto_server, which cannot prove presigned-URL expiry."""
import hashlib
import os
import time
from uuid import uuid4
import httpx
import pytest
from botocore.exceptions import ClientError
from app import worker
from app.config import settings
from app.services import store_report, s3
from conftest import needs_s3, token, person, drain, S3_ENDPOINT
from test_reports import match

pytestmark=needs_s3

@pytest.fixture()
def bucket(monkeypatch):
    monkeypatch.setenv('AWS_ACCESS_KEY_ID',os.environ.get('TEST_S3_ACCESS_KEY','devminio'))
    monkeypatch.setenv('AWS_SECRET_ACCESS_KEY',os.environ.get('TEST_S3_SECRET_KEY','devminio-password-change'))
    name=f'kundli-test-{uuid4().hex[:12]}'
    monkeypatch.setattr(settings,'s3_endpoint_url',S3_ENDPOINT); monkeypatch.setattr(settings,'s3_bucket',name)
    monkeypatch.setattr(settings,'s3_region','us-east-1'); monkeypatch.setattr(settings,'report_presign_ttl_seconds',60)
    client=s3()  # same client factory (and signature version) as the app
    client.create_bucket(Bucket=name)  # new buckets are private: no bucket policy, no public ACL
    yield client
    for o in client.list_objects_v2(Bucket=name).get('Contents',[]): client.delete_object(Bucket=name,Key=o['Key'])
    client.delete_bucket(Bucket=name)

def report_stub(locale='en'):
    return type('R',(),{'id':'r1','owner_id':'owner-1','locale':locale})()

def test_upload_is_private_encrypted_and_checksummed(bucket):
    key,checksum=store_report(report_stub('hi'),match())
    assert key=='reports/owner-1/m1/r1.pdf'
    head=bucket.head_object(Bucket=settings.s3_bucket,Key=key)
    assert head['ContentType']=='application/pdf' and head['Metadata']['sha256']==checksum
    assert head.get('ServerSideEncryption')=='AES256'
    body=bucket.get_object(Bucket=settings.s3_bucket,Key=key)['Body'].read()
    assert hashlib.sha256(body).hexdigest()==checksum
    assert httpx.get(f'{S3_ENDPOINT}/{settings.s3_bucket}/{key}').status_code==403  # no anonymous access

def test_signed_url_works_then_expires(bucket):
    key,checksum=store_report(report_stub(),match())
    url=bucket.generate_presigned_url('get_object',Params={'Bucket':settings.s3_bucket,'Key':key},ExpiresIn=1)
    assert 'X-Amz-Algorithm=AWS4-HMAC-SHA256' in url and 'X-Amz-Expires=1&' in url
    fetched=httpx.get(url); assert fetched.status_code==200 and hashlib.sha256(fetched.content).hexdigest()==checksum
    if os.environ.get('TEST_S3_EMULATOR'): pytest.skip('emulator (moto) does not enforce presigned expiry; run against MinIO/S3')
    time.sleep(2)
    assert httpx.get(url).status_code==403

def test_draft_to_calculation_to_report_to_download(database,client,bucket,monkeypatch):
    """PRD acceptance path through the real API, worker, WeasyPrint and storage."""
    pytest.importorskip('vedic_calc'); monkeypatch.setattr(settings,'astrology_mode','local_experimental')
    a,b=token(client),token(client)
    p1=person(client,a,'Asha',birth_date='1990-03-15',birth_time_local='10:30:00')['id']
    p2=person(client,a,'Bharat',birth_date='1989-11-02',birth_time_local='06:45:00',time_accuracy='approximate')['id']
    m=client.post('/v1/matches',headers=a,json={'person1_id':p1,'person2_id':p2}).json(); drain()
    m=client.get(f"/v1/matches/{m['id']}",headers=a).json()
    assert m['status']=='ready' and len(m['facts']['score']['kootas'])==8
    assert {'experimental_engine','approximate_birth_time'}<=set(m['facts']['warnings'])
    r=client.post(f"/v1/matches/{m['id']}/reports",headers=a,json={'locale':'hi'}).json()
    assert client.post(f"/v1/reports/{r['id']}/download-url",headers=a).status_code==409  # not ready yet
    drain()
    assert client.get(f"/v1/reports/{r['id']}",headers=a).json()['status']=='ready'
    assert client.post(f"/v1/reports/{r['id']}/download-url",headers=b).status_code==404  # other guest
    signed=client.post(f"/v1/reports/{r['id']}/download-url",headers=a).json()
    assert settings.s3_bucket in signed['url'] and 'X-Amz-Signature' in signed['url'] and signed['expires_at']
    pdf=httpx.get(signed['url']); assert pdf.status_code==200 and pdf.content.startswith(b'%PDF')
    keys=[o['Key'] for o in bucket.list_objects_v2(Bucket=settings.s3_bucket)['Contents']]
    # Deleting the profile queues S3 cleanup; the worker removes the object.
    assert client.delete(f'/v1/people/{p1}',headers=a).status_code==204
    drain()
    for key in keys:
        with pytest.raises(ClientError): bucket.head_object(Bucket=settings.s3_bucket,Key=key)
    assert worker.run_once() is False
