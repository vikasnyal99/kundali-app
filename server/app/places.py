"""Offline birthplace suggestions from GeoNames cities15000 (CC BY 4.0, https://www.geonames.org/).

No third-party request is made, so typed places never leave the server. Suggestions only pre-fill the
form; users confirm place, coordinates and timezone, and PersonInput still validates them on save.
Rebuild the data with scripts/build_places.py.
"""
import gzip
import unicodedata
from functools import lru_cache
from pathlib import Path
from zoneinfo import available_timezones

DATA=Path(__file__).parent/'data'/'places.tsv.gz'

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

def search(query,limit=8):
    q=fold(query.strip()); exact=[]; prefix=[]
    if len(q)<2: return []
    for keys,place in places():
        if q in keys: exact.append(place)
        elif len(prefix)<limit and any(k.startswith(q) for k in keys): prefix.append(place)
    return (exact+prefix)[:limit]
