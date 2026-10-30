"""Inline calculation, summaries (template and mocked OpenAI) and the full report with real chart details."""
import json
from types import SimpleNamespace
import httpx
import pytest
from sqlalchemy import select
from app import summary, services
from app.config import settings
from app.db import Job
from conftest import token, person

ROWS=[('varna',1,1),('vashya',2,2),('tara',3,1.5),('yoni',4,3),('graha_maitri',5,5),('gana',6,6),('bhakoot',7,7),('nadi',8,0)]
def facts(snapshot=None):
    kootas=[{'key':k,'earned':e,'possible':m} for k,m,e in ROWS]
    return {'score':{'earned':sum(r['earned'] for r in kootas),'possible':36,'kootas':kootas},'warnings':['experimental_engine'],
            'calculation':{'engine':'test-double','version':'v','ruleset':'r','ayanamsa':'lahiri'},'manglik':{'status':'unavailable'}}

def match(details=None):
    people=[{'display_name':'Deepak','birth_date':'1995-03-12','birth_time_local':'10:15:00','birth_timezone':'Asia/Kolkata','birth_place_name':'Delhi','latitude':28.6,'longitude':77.2,'time_accuracy':'exact','birth_utc':'1995-03-12T04:45:00+00:00'},
            {'display_name':'Kirti','birth_date':'1997-09-14','birth_time_local':'09:30:00','birth_timezone':'Asia/Kolkata','birth_place_name':'Mumbai','latitude':19.07,'longitude':72.87,'time_accuracy':'exact','birth_utc':'1997-09-14T04:00:00+00:00'}]
    return SimpleNamespace(id='m1',facts=facts(),snapshot={'people':people,'settings':{}},summaries=None)

@pytest.fixture()
def local(monkeypatch):
    monkeypatch.setattr(settings,'astrology_mode','local_experimental')
    monkeypatch.setattr(services,'calculate',facts)

def test_local_matches_are_ready_in_the_response_without_jobs(database,client,local):
    h=token(client); a,b,c=(person(client,h,n)['id'] for n in ('A','B','C'))
    m=client.post('/v1/matches',headers=h,json={'person1_id':a,'person2_id':b}).json()
    assert m['status']=='ready' and m['facts']['score']['earned']==25.5
    cmp=client.post('/v1/comparisons',headers=h,json={'person1_id':a,'person2_ids':[b,c]}).json()
    assert [r['status'] for r in cmp['results']]==['ready','ready']
    with database.factory() as s: assert list(s.scalars(select(Job)))==[]

def test_permanent_failure_is_reported_immediately(database,client,monkeypatch):
    monkeypatch.setattr(settings,'astrology_mode','local_experimental')
    def fail(snapshot): raise services.PermanentFailure('invalid_engine_response')
    monkeypatch.setattr(services,'calculate',fail)
    h=token(client); a=person(client,h,'A')['id']; b=person(client,h,'B')['id']
    m=client.post('/v1/matches',headers=h,json={'person1_id':a,'person2_id':b}).json()
    assert (m['status'],m['failure_code'])==('failed','invalid_engine_response')

def test_unknown_birth_time_is_saved_at_noon_without_a_time(client):
    h=token(client)
    p=person(client,h,'U',time_accuracy='unknown',birth_time_local=None)
    assert p['birth_time_local']=='12:00:00' and p['birth_utc']=='1997-09-14T06:30:00+00:00'
    r=client.post('/v1/people',headers=h,json={'display_name':'X','birth_date':'1997-09-14','birth_timezone':'Asia/Kolkata','birth_place_name':'Delhi','latitude':28.6,'longitude':77.2,'time_accuracy':'exact'})
    assert r.status_code==422

def test_report_for_unknown_time_draws_no_lagna_chart():
    pytest.importorskip('vedic_calc')
    m=match(); m.snapshot['people'][1].update(time_accuracy='unknown',birth_time_local='12:00:00',birth_utc='1997-09-14T06:30:00+00:00')
    html=services.report_html(m,'en',None)
    assert html.count('<svg')==1 and 'Birth time unknown' in html

def test_summary_endpoint_returns_template_and_caches(database,client,local):
    h=token(client); a,b=(person(client,h,n)['id'] for n in ('Deepak','Kirti'))
    m=client.post('/v1/matches',headers=h,json={'person1_id':a,'person2_id':b}).json()
    s=client.get(f"/v1/matches/{m['id']}/summary?locale=hi",headers=h).json()
    assert s['source']=='template' and s['score']==25.5 and s['band']=='good' and [d['key'] for d in s['doshas']]==['nadi']
    assert len(s['kootas'])==8 and 'Deepak' in s['overview'] and 'नाड़ी दोष' in s['overview']
    assert client.get(f"/v1/matches/{m['id']}/summary?locale=hi",headers=h).json()==s
    assert client.get(f"/v1/matches/{m['id']}/summary?locale=xx",headers=h).status_code==422

def fake_openai(monkeypatch,answer,calls):
    class Client:
        def __init__(self,**kw): pass
        def __enter__(self): return self
        def __exit__(self,*a): return False
        def post(self,url,json,headers):
            calls.append(json)
            return httpx.Response(200,json={'choices':[{'message':{'content':__import__('json').dumps(answer)}}]},request=httpx.Request('POST',url))
    monkeypatch.setattr(summary.httpx,'Client',Client)
    monkeypatch.setattr(settings,'openai_api_key','test-key')

def answer(**over):
    base={'headline':'Good match','overview':'{P1} and {P2} are a good match.','kootas':[{'key':k,'note':f'{k} note for {{P1}}'} for k,_,_ in ROWS],
          'strengths':['Gana fully matches'],'considerations':['Nadi Dosha is present'],'guidance':'Talk openly.'}
    return {**base,**over}

def test_ai_summary_fills_names_and_sends_no_birth_data(monkeypatch):
    calls=[]; fake_openai(monkeypatch,answer(),calls)
    s,cacheable=summary.build(match(),'en')
    assert cacheable and s['source']=='ai' and s['overview'].startswith('Deepak and Kirti')
    assert s['kootas'][0]['note']=='varna note for Deepak' and s['kootas'][7]['earned']==0
    sent=json.dumps(calls[0],ensure_ascii=False)
    assert 'Deepak' not in sent and '1995' not in sent and 'Delhi' not in sent and '28.6' not in sent

@pytest.mark.parametrize('bad',[answer(overview='{P1} and {P2} share 31 of 36 gunas.'),answer(guidance='कुल २५ गुण।'),answer(kootas=[{'key':'varna','note':'x'}]),answer(guidance='Ask {name}.')])
def test_ai_answer_with_invented_numbers_or_gaps_falls_back_uncached(monkeypatch,bad):
    fake_openai(monkeypatch,bad,[])
    s,cacheable=summary.build(match(),'en')
    assert s['source']=='template' and not cacheable and '25.5 of 36' in s['overview']

def test_full_report_has_charts_and_avakhada_with_real_engine():
    pytest.importorskip('vedic_calc'); pytest.importorskip('weasyprint')
    m=match(); s,_=summary.build(m,'hi')
    html=services.report_html(m,'hi',s)
    assert html.count('<svg')==2 and 'अवकहड़ा चक्र' in html and 'नाड़ी दोष' in html and 'Deepak' in html
    pdf=services.render_pdf(m,'en',summary.build(m,'en')[0])
    assert pdf.startswith(b'%PDF')

def test_person_avatar_is_optional_and_limited_to_the_app_set(client):
    h=token(client)
    assert person(client,h,'A')['avatar'] is None
    assert person(client,h,'B',avatar='female_1')['avatar']=='female_1'
    assert person(client,h,'B2',avatar='male_3')['avatar']=='male_3'
    r=client.post('/v1/people',headers=h,json={'display_name':'C','birth_date':'1997-09-14','birth_time_local':'09:30:00','birth_timezone':'Asia/Kolkata','birth_place_name':'Delhi','latitude':28.6,'longitude':77.2,'avatar':'someone_else'})
    assert r.status_code==422
