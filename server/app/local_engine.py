"""Optional experimental adapter. Install requirements-engine.txt explicitly.

Never presents upstream's relationship verdict as a factual prediction. Every
result still passes services.validate_facts before it is stored.
"""
from datetime import datetime, timezone

VERSION='vedic-calc-620d54560ee7+swe-2.10.3.2'
RULESET='vedic-calc-ashtakoota-620d54560ee7+naisargika-maitri-v1'
NAKSHATRA_SPAN=360/27
# The Moon moves at most ~0.64 deg/hour; an "approximate" time is treated as +/- 1 hour.
APPROXIMATE_WINDOW_DEGREES=0.65

# Graha Maitri from the naisargika (natural) relationships as commonly published (BPHS). Upstream
# deviates for three pairs (see test_known_upstream_graha_maitri_deviations_are_pinned), so this koota
# is computed here from the sign lords instead.
SIGN_LORDS=['mars','venus','mercury','moon','sun','mercury','venus','mars','jupiter','saturn','saturn','jupiter']
FRIENDS={'sun':{'moon','mars','jupiter'},'moon':{'sun','mercury'},'mars':{'sun','moon','jupiter'},'mercury':{'sun','venus'},
 'jupiter':{'sun','moon','mars'},'venus':{'mercury','saturn'},'saturn':{'mercury','venus'}}
ENEMIES={'sun':{'venus','saturn'},'moon':set(),'mars':{'mercury'},'mercury':{'moon'},'jupiter':{'mercury','venus'},
 'venus':{'sun','moon'},'saturn':{'sun','moon','mars'}}
MAITRI_POINTS={('friend','friend'):5,('friend','neutral'):4,('neutral','neutral'):3,('enemy','friend'):1,('enemy','neutral'):0.5,('enemy','enemy'):0}

def relation(a,b):
    return 'friend' if b in FRIENDS[a] else 'enemy' if b in ENEMIES[a] else 'neutral'

def graha_maitri(sign1,sign2):
    """Points (of 5) for two Moon signs given as 0-based indices from Aries."""
    a,b=SIGN_LORDS[sign1],SIGN_LORDS[sign2]
    if a==b: return 5
    return MAITRI_POINTS[tuple(sorted((relation(a,b),relation(b,a))))]

def boundary_distance(longitude):
    """Degrees from the Moon to the nearest nakshatra or sign boundary."""
    return min(min(longitude%NAKSHATRA_SPAN,NAKSHATRA_SPAN-longitude%NAKSHATRA_SPAN),min(longitude%30,30-longitude%30))

def moon(person):
    from vedic_calc import calculate_chart
    from vedic_calc.core.constants import Planet, Ayanamsa
    # birth_utc is produced by schemas.PersonInput.utc(); pass UTC components with a zero offset
    # so the library never re-applies a local offset or rolls the date over itself.
    dt=datetime.fromisoformat(person['birth_utc']).astimezone(timezone.utc)
    chart=calculate_chart(year=dt.year,month=dt.month,day=dt.day,hour=dt.hour,minute=dt.minute,second=dt.second,latitude=person['latitude'],longitude=person['longitude'],timezone_offset=0,ayanamsa=Ayanamsa.LAHIRI)
    return chart.planets[Planet.MOON]

def sign_index(m):
    return int(m.longitude//30)%12

def calculate_local(snapshot):
    from vedic_calc import calculate_compatibility
    people=snapshot['people']
    moons=[moon(p) for p in people]
    # Upstream argument order is groom-side first, bride-side second (affects Varna, Gana, Vashya).
    result=calculate_compatibility(moons[0].nakshatra_info.nakshatra,moons[0].sign,moons[1].nakshatra_info.nakshatra,moons[1].sign)
    kootas=[{'key':k.name.lower().replace(' ','_'),'earned':k.obtained,'possible':k.maximum} for k in result.kuttas]
    for k in kootas:
        if k['key']=='graha_maitri': k['earned']=graha_maitri(sign_index(moons[0]),sign_index(moons[1]))
    warnings=['experimental_engine','independent_validation_pending']
    if any(p['time_accuracy']=='approximate' and boundary_distance(m.longitude)<APPROXIMATE_WINDOW_DEGREES for p,m in zip(people,moons)):
        warnings.append('moon_near_boundary_time_sensitive')
    return {
        'score':{'earned':sum(k['earned'] for k in kootas),'possible':36,'kootas':kootas},
        'calculation':{'engine':'vedic-calc + Swiss Ephemeris','version':VERSION,'ruleset':RULESET,'ayanamsa':'lahiri','house_system':'whole_sign','calculated_at':datetime.now(timezone.utc).isoformat(),'role_order':'person1=groom-side; person2=bride-side','validation':'experimental; independent domain review pending','ephemeris':'Swiss Ephemeris default data lookup; Moshier fallback permitted','birth_utc':[p['birth_utc'] for p in people]},
        'warnings':warnings,'manglik':{'status':'unavailable'},
        'charts':[{'moon_longitude':m.longitude,'moon_sign':m.sign.name.lower(),'nakshatra':m.nakshatra_info.nakshatra.name.lower(),'pada':m.nakshatra_info.pada} for m in moons]
    }
