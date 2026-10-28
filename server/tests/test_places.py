from app.places import search
from conftest import token

def test_search_ranks_exact_then_prefix_with_timezone():
    top=search('varanasi')[0]
    assert (top['name'],top['region'],top['country'],top['timezone'])==('Varanasi','Uttar Pradesh','IN','Asia/Kolkata')
    assert search('Dehra')[0]['name']=='Dehradun'
    assert search('new york')[0]['timezone']=='America/New_York'
    assert search('sao paulo')[0]['name']=='São Paulo'

def test_hindi_aliases_and_bounds():
    assert search('वाराणसी')[0]['name']=='Varanasi' and search('काशी')[0]['name']=='Varanasi'
    assert search('a') == [] and len(search('ka'))==8

def test_endpoint_requires_session_and_validates(client):
    assert client.get('/v1/places',params={'q':'pune'}).status_code==401
    h=token(client)
    assert client.get('/v1/places',params={'q':'p'},headers=h).status_code==422
    assert client.get('/v1/places',params={'q':'pune'},headers=h).json()[0]['latitude']==18.5196
