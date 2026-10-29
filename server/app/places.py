"""Offline birthplace suggestions from GeoNames cities15000 and India postal codes (CC BY 4.0, https://www.geonames.org/).

A query of digits searches Indian pincodes; a name searches cities first, then post-office names (towns,
villages and localities that the city list lacks).

No third-party request is made, so typed places never leave the server. Suggestions only pre-fill the
form; users confirm place, coordinates and timezone, and PersonInput still validates them on save.
Rebuild the data with scripts/build_places.py and scripts/build_pincodes.py.
"""
import gzip
import unicodedata
from functools import lru_cache
from pathlib import Path
from zoneinfo import available_timezones

DATA=Path(__file__).parent/'data'/'places.tsv.gz'
PINCODES=Path(__file__).parent/'data'/'pincodes.tsv.gz'

def fold(text):
    # Case-insensitive, and Latin accents ignored (São Paulo == sao paulo); Devanagari is left intact.
    return ''.join(c for c in unicodedata.normalize('NFKD',text.casefold()) if not '̀'<=c<='ͯ')

@lru_cache(1)
def places():
    zones=available_timezones(); rows=[]
    with gzip.open(DATA,'rt',encoding='utf-8') as f:
        for line in f:
            if line.startswith('#'): continue
            name,region,country,lat,lon,tz,_population,hindi=line.rstrip('\n').split('\t')
            if tz not in zones: continue
            keys=(fold(name),*(fold(h) for h in hindi.split('|') if h))
            rows.append((keys,{'name':name,'region':region,'country':country,'latitude':float(lat),'longitude':float(lon),'timezone':tz}))
    return rows  # already ordered by population, largest first

@lru_cache(1)
def offices():
    """(pincode, folded office name, row) tuples, sorted by pincode then office name."""
    rows=[]
    with gzip.open(PINCODES,'rt',encoding='utf-8') as f:
        for line in f:
            if line.startswith('#'): continue
            pincode,office,district,state,lat,lon=line.rstrip('\n').split('\t')
            rows.append((pincode,fold(office),(office,district,state,lat,lon)))
    return rows

def office(pincode,row):
    name,district,state,lat,lon=row
    return {'name':name,'region':', '.join(x for x in (district,state) if x),'country':'IN','pincode':pincode,
            'latitude':float(lat),'longitude':float(lon),'timezone':'Asia/Kolkata'}

def search(query,limit=8):
    q=fold(query.strip())
    if len(q)<2: return []
    if q.isdigit():
        # Pincode prefix; at least three digits so a search is never "every office in India".
        return [office(p,r) for p,_,r in offices() if p.startswith(q)][:limit] if len(q)>=3 else []
    exact=[]; prefix=[]
    for keys,place in places():
        if q in keys: exact.append(place)
        elif len(prefix)<limit and any(k.startswith(q) for k in keys): prefix.append(place)
    found=(exact+prefix)[:limit]
    if len(found)<limit:
        # Towns, villages and localities missing from the city list, by post-office name.
        seen={(p['name'].casefold(),p['region']) for p in found}
        for pincode,name,row in offices():
            if not name.startswith(q): continue
            place=office(pincode,row)
            if (place['name'].casefold(),place['region']) in seen: continue
            seen.add((place['name'].casefold(),place['region'])); found.append(place)
            if len(found)>=limit: break
    return found
