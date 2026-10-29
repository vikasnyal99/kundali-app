"""The web app is served at '/' next to the API and revalidated on every load."""
import pytest
from app import main

@pytest.fixture()
def web(tmp_path):
    (tmp_path/'index.html').write_text('<!DOCTYPE html><title>KundliMilan</title>')
    (tmp_path/'main.dart.js').write_text('console.log(1)')
    main.mount_web(str(tmp_path))
    yield
    main.app.router.routes.pop()

def test_web_files_are_served_without_shadowing_the_api(client,web):
    page=client.get('/')
    assert page.status_code==200 and 'KundliMilan' in page.text and page.headers['cache-control']=='no-cache'
    js=client.get('/main.dart.js')
    assert js.status_code==200 and client.get('/main.dart.js',headers={'If-None-Match':js.headers['etag']}).status_code==304
    assert client.get('/health/live').json()=={'status':'ok'}
    assert client.post('/v1/guest-sessions').status_code==201
    assert 'cache-control' not in client.get('/health/live').headers

def test_static_files_do_not_use_the_api_rate_limit(client,web):
    for _ in range(200): assert client.get('/main.dart.js').status_code==200
    assert client.get('/health/live').status_code==200

def test_no_web_dir_serves_api_only(client):
    main.mount_web(''); main.mount_web('/nonexistent')
    assert client.get('/').status_code==404
