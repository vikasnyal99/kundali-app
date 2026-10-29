"""Experimental local engine checks. These verify adapter wiring, not astrological correctness."""
import json
from datetime import datetime, timezone
from pathlib import Path
import pytest
pytest.importorskip('vedic_calc')
import swisseph as swe
from vedic_calc import calculate_chart, calculate_compatibility
from vedic_calc.chart.calculator import longitude_to_nakshatra_info, longitude_to_sign
from vedic_calc.core.constants import Planet, Sign, Nakshatra
from vedic_calc.core.types import PlanetPosition
from app import local_engine, services
from app.services import validate_facts, PermanentFailure, KOOTAS

DELHI=dict(latitude=28.6139,longitude=77.209)
def person(utc,accuracy='exact',**place): return {'birth_utc':utc,'time_accuracy':accuracy,**(place or DELHI)}
def snapshot(*people): return {'people':list(people),'settings':{}}
P1=person('1997-09-14T04:00:00+00:00')
P2=person('1998-02-20T23:30:00+00:00',latitude=19.076,longitude=72.8777)

def fake_moon(longitude):
    return PlanetPosition(planet=Planet.MOON,longitude=longitude,sign=longitude_to_sign(longitude),degree_in_sign=longitude%30,nakshatra_info=longitude_to_nakshatra_info(longitude))

def test_eight_rows_bounds_and_total():
    facts=local_engine.calculate_local(snapshot(P1,P2))
    rows=facts['score']['kootas']
    assert [r['key'] for r in rows]==list(KOOTAS)
    assert all(r['possible']==KOOTAS[r['key']] and 0<=r['earned']<=r['possible'] for r in rows)
    assert facts['score']['possible']==36==sum(r['possible'] for r in rows)
    assert facts['score']['earned']==sum(r['earned'] for r in rows)
    assert validate_facts(facts,local_engine.VERSION,local_engine.RULESET)['manglik']=={'status':'unavailable'}
    assert {'experimental_engine','independent_validation_pending'}<=set(facts['warnings'])
    assert facts['calculation']['role_order'].startswith('person1=groom-side')

def test_repeatable():
    a,b=(local_engine.calculate_local(snapshot(P1,P2)) for _ in range(2))
    for f in (a,b): f['calculation'].pop('calculated_at')
    assert a==b

def test_utc_instant_independent_of_offset_and_day_rollover():
    # 02:00 IST on 15 Sep is 20:30 UTC on 14 Sep: the stored instant must yield the same Moon either way.
    ist=local_engine.moon(person('1997-09-15T02:00:00+05:30'))
    utc=local_engine.moon(person('1997-09-14T20:30:00+00:00'))
    local=calculate_chart(year=1997,month=9,day=15,hour=2,minute=0,latitude=DELHI['latitude'],longitude=DELHI['longitude'],timezone_offset=5.5).planets[Planet.MOON]
    assert ist==utc and ist.longitude==local.longitude

def test_moon_matches_raw_swiss_ephemeris_lahiri():
    dt=datetime(1997,9,14,4,0,tzinfo=timezone.utc)
    swe.set_sid_mode(swe.SIDM_LAHIRI)
    raw=swe.calc_ut(swe.julday(dt.year,dt.month,dt.day,dt.hour+dt.minute/60),swe.MOON,swe.FLG_SIDEREAL)[0][0]
    assert local_engine.moon(P1).longitude==pytest.approx(raw,abs=1e-3)

def test_person_order_is_rule_direction(monkeypatch):
    # Gemini Moon (Shudra varna) as Person 1 vs Cancer Moon (Brahmin varna) as Person 2 and swapped.
    moons={'a':fake_moon(70.0),'b':fake_moon(100.0)}
    monkeypatch.setattr(local_engine,'moon',lambda p:moons[p['id']])
    varna=lambda first,second:local_engine.calculate_local(snapshot({'id':first,'birth_utc':'','time_accuracy':'exact'},{'id':second,'birth_utc':'','time_accuracy':'exact'}))['score']['kootas'][0]['earned']
    assert (varna('a','b'),varna('b','a'))==(0.0,1.0)

def test_same_nadi_scores_zero(monkeypatch):
    monkeypatch.setattr(local_engine,'moon',lambda p:fake_moon(45.0))
    facts=local_engine.calculate_local(snapshot({'birth_utc':'','time_accuracy':'exact'},{'birth_utc':'','time_accuracy':'exact'}))
    assert {r['key']:r['earned'] for r in facts['score']['kootas']}['nadi']==0

@pytest.mark.parametrize('longitude,accuracy,warned',[(13.2,'approximate',True),(29.9,'approximate',True),(6.0,'approximate',False),(13.2,'exact',False)])
def test_boundary_sensitivity_warning(monkeypatch,longitude,accuracy,warned):
    monkeypatch.setattr(local_engine,'moon',lambda p:fake_moon(longitude))
    facts=local_engine.calculate_local(snapshot({'birth_utc':'','time_accuracy':accuracy},{'birth_utc':'','time_accuracy':'exact'}))
    assert ('moon_near_boundary_time_sensitive' in facts['warnings'])==warned

def test_tampered_or_mislabelled_output_rejected():
    facts=local_engine.calculate_local(snapshot(P1,P2))
    with pytest.raises(PermanentFailure): validate_facts(facts)  # provider version/ruleset do not match local output
    bad=json.loads(json.dumps(facts)); bad['score']['kootas'][0]['earned']=2; bad['score']['earned']+=2
    with pytest.raises(PermanentFailure): validate_facts(bad,local_engine.VERSION,local_engine.RULESET)
    bad=json.loads(json.dumps(facts)); bad['score']['earned']=36
    with pytest.raises(PermanentFailure): validate_facts(bad,local_engine.VERSION,local_engine.RULESET)

def test_service_path_validates_and_requires_birth_time(monkeypatch):
    monkeypatch.setattr(services.settings,'astrology_mode','local_experimental')
    facts=services.calculate(snapshot(P1,{**P2,'time_accuracy':'approximate'}))
    assert 'approximate_birth_time' in facts['warnings'] and len(facts['score']['kootas'])==8
    day={'birth_timezone':'Asia/Kolkata','time_accuracy':'unknown'}
    # The Moon stays in one nakshatra and sign all of 1996-01-05 (Delhi) but changes on 1998-02-20.
    steady=services.calculate(snapshot(P1,{**P2,**day,'birth_date':'1996-01-05','birth_utc':'1996-01-05T06:30:00+00:00'}))
    assert 'birth_time_unknown_noon' in steady['warnings'] and 'unknown_time_moon_changes_that_day' not in steady['warnings']
    changing=services.calculate(snapshot(P1,{**P2,**day,'birth_date':'1998-02-20','birth_utc':'1998-02-20T06:30:00+00:00'}))
    assert {'birth_time_unknown_noon','unknown_time_moon_changes_that_day'}<=set(changing['warnings']) and len(changing['score']['kootas'])==8
    monkeypatch.setattr(services.settings,'astrology_mode','external'); monkeypatch.setattr(services.settings,'astrology_url','https://provider.test')
    with pytest.raises(PermanentFailure,match='birth_time_required'): services.calculate(snapshot(P1,{**P2,**day}))

def test_known_upstream_graha_maitri_deviations_are_pinned():
    """Characterises upstream behaviour that differs from the commonly published naisargika table.

    Commonly published: Mars treats Saturn as neutral and Venus treats the Moon as an enemy, and a
    friend+enemy pair scores 1. Upstream scores these 0, 3 and 3 respectively. If this test starts
    failing the pin changed; re-review instead of updating expectations blindly. See docs/ENGINE_RESEARCH.md.
    """
    gm=lambda s1,s2:calculate_compatibility(Nakshatra.ASHWINI,s1,Nakshatra.ASHWINI,s2).kuttas[4].obtained
    assert gm(Sign.SCORPIO,Sign.CAPRICORN)==0.0   # Mars/Saturn: published neutral+enemy = 0.5
    assert gm(Sign.TAURUS,Sign.CANCER)==3.0       # Venus/Moon: published enemy+neutral = 0.5
    assert gm(Sign.CANCER,Sign.GEMINI)==3.0       # Moon/Mercury: published friend+enemy = 1

def test_domain_reviewed_reference_cases():
    cases=json.loads((Path(__file__).parent/'fixtures'/'ashtakoota_reference.json').read_text())['cases']
    if not cases: pytest.skip('No domain-reviewed reference cases yet; required before any release approval')
    for case in cases:
        facts=local_engine.calculate_local(snapshot(*case['people']))
        assert {r['key']:r['earned'] for r in facts['score']['kootas']}==case['expected_kootas'], case['id']

# Commonly published Ashtakoota Graha Maitri table (rows/columns: Sun, Moon, Mars, Mercury, Jupiter, Venus, Saturn).
PUBLISHED_MAITRI=[[5,5,5,4,5,0,0],[5,5,4,1,4,0.5,0.5],[5,4,5,0.5,5,3,0.5],[4,1,0.5,5,0.5,5,4],[5,4,5,0.5,5,0.5,3],[0,0.5,3,5,0.5,5,5],[0,0.5,0.5,4,3,5,5]]
LORD_SIGN={'sun':4,'moon':3,'mars':0,'mercury':2,'jupiter':8,'venus':1,'saturn':9}

def test_graha_maitri_matches_published_table():
    lords=['sun','moon','mars','mercury','jupiter','venus','saturn']
    for i,a in enumerate(lords):
        for j,b in enumerate(lords):
            assert local_engine.graha_maitri(LORD_SIGN[a],LORD_SIGN[b])==PUBLISHED_MAITRI[i][j],(a,b)

@pytest.mark.parametrize('lon1,lon2,expected',[(225.0,285.0,0.5),(45.0,105.0,0.5),(105.0,75.0,1)])
def test_adapter_corrects_upstream_graha_maitri(monkeypatch,lon1,lon2,expected):
    # Scorpio/Capricorn (Mars/Saturn), Taurus/Cancer (Venus/Moon), Cancer/Gemini (Moon/Mercury)
    moons={'a':fake_moon(lon1),'b':fake_moon(lon2)}
    monkeypatch.setattr(local_engine,'moon',lambda p:moons[p['id']])
    facts=local_engine.calculate_local(snapshot({'id':'a','birth_utc':'','time_accuracy':'exact'},{'id':'b','birth_utc':'','time_accuracy':'exact'}))
    rows={r['key']:r['earned'] for r in facts['score']['kootas']}
    assert rows['graha_maitri']==expected and facts['score']['earned']==sum(rows.values())
    validate_facts(facts,local_engine.VERSION,local_engine.RULESET)
