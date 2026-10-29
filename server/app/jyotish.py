"""Display-only chart details (Lagna, planets, Avakhada) and localized names for summaries and PDFs.

Scores never come from here: they stay in the validated match facts. Details are recomputed from the
stored birth snapshot with the same engine and Lahiri ayanamsa, so they need the optional engine.
"""
from datetime import datetime, timezone
from html import escape

SIGNS={'en':['Aries','Taurus','Gemini','Cancer','Leo','Virgo','Libra','Scorpio','Sagittarius','Capricorn','Aquarius','Pisces'],
 'hi':['मेष','वृषभ','मिथुन','कर्क','सिंह','कन्या','तुला','वृश्चिक','धनु','मकर','कुंभ','मीन']}
NAKSHATRAS={'en':['Ashwini','Bharani','Krittika','Rohini','Mrigashira','Ardra','Punarvasu','Pushya','Ashlesha','Magha','Purva Phalguni','Uttara Phalguni','Hasta','Chitra','Swati','Vishakha','Anuradha','Jyeshtha','Mula','Purva Ashadha','Uttara Ashadha','Shravana','Dhanishta','Shatabhisha','Purva Bhadrapada','Uttara Bhadrapada','Revati'],
 'hi':['अश्विनी','भरणी','कृत्तिका','रोहिणी','मृगशिरा','आर्द्रा','पुनर्वसु','पुष्य','आश्लेषा','मघा','पूर्वा फाल्गुनी','उत्तरा फाल्गुनी','हस्त','चित्रा','स्वाती','विशाखा','अनुराधा','ज्येष्ठा','मूल','पूर्वाषाढ़ा','उत्तराषाढ़ा','श्रवण','धनिष्ठा','शतभिषा','पूर्वा भाद्रपद','उत्तरा भाद्रपद','रेवती']}
PLANET_KEYS=['sun','moon','mars','mercury','jupiter','venus','saturn','rahu','ketu']
PLANETS={'en':dict(zip(PLANET_KEYS,['Sun','Moon','Mars','Mercury','Jupiter','Venus','Saturn','Rahu','Ketu'])),
 'hi':dict(zip(PLANET_KEYS,['सूर्य','चंद्र','मंगल','बुध','गुरु','शुक्र','शनि','राहु','केतु']))}
PLANET_ABBR={'en':dict(zip(PLANET_KEYS,['Su','Mo','Ma','Me','Ju','Ve','Sa','Ra','Ke'])),
 'hi':dict(zip(PLANET_KEYS,['सू','चं','मं','बु','गु','शु','श','रा','के']))}
# Avakhada values arrive as the engine's English names.
AVAKHADA_HI={'Brahmin':'ब्राह्मण','Kshatriya':'क्षत्रिय','Vaishya':'वैश्य','Shudra':'शूद्र',
 'Manava':'मानव','Vanachara':'वनचर','Chatushpada':'चतुष्पद','Jalchara':'जलचर','Keeta':'कीट',
 'Horse':'अश्व','Elephant':'गज','Sheep':'मेष (मेढ़ा)','Serpent':'सर्प','Dog':'श्वान','Cat':'मार्जार','Rat':'मूषक','Cow':'गौ',
 'Buffalo':'महिष','Tiger':'व्याघ्र','Deer':'मृग','Monkey':'वानर','Mongoose':'नकुल','Lion':'सिंह',
 'Deva':'देव','Manushya':'मनुष्य','Rakshasa':'राक्षस',
 'Aadi (Vata)':'आदि (वात)','Madhya (Pitta)':'मध्य (पित्त)','Antya (Kapha)':'अन्त्य (कफ)',
 'Fire':'अग्नि','Earth':'पृथ्वी','Air':'वायु','Water':'जल','Gold':'स्वर्ण','Silver':'रजत','Copper':'ताम्र','Iron':'लौह',
 'Adi':'आदि','Madhya':'मध्य','Antya':'अन्त्य'}

def name(kind,value,locale):
    """Localized name for a sign/nakshatra index, planet key or Avakhada value."""
    if kind=='sign': return SIGNS[locale][value]
    if kind=='nakshatra': return NAKSHATRAS[locale][value]
    if kind=='planet': return PLANETS[locale][value]
    return AVAKHADA_HI.get(value,value) if locale=='hi' else value

def details(person):
    """Lagna, planets and Avakhada for one stored person, or None when the engine is not installed."""
    try:
        from vedic_calc import calculate_chart
        from vedic_calc.core.constants import Ayanamsa, Planet
        from vedic_calc.compatibility.avakhada import calculate_avakhada
    except ImportError:
        return None
    dt=datetime.fromisoformat(person['birth_utc']).astimezone(timezone.utc)
    chart=calculate_chart(year=dt.year,month=dt.month,day=dt.day,hour=dt.hour,minute=dt.minute,second=dt.second,latitude=person['latitude'],longitude=person['longitude'],timezone_offset=0,ayanamsa=Ayanamsa.LAHIRI)
    def position(p):
        return {'sign':p.sign.value-1,'degree':round(p.degree_in_sign,2),'nakshatra':p.nakshatra_info.nakshatra.value-1,'pada':p.nakshatra_info.pada,'retrograde':bool(p.is_retrograde)}
    moon=chart.planets[Planet.MOON]
    ava=calculate_avakhada(moon.nakshatra_info.nakshatra,moon.nakshatra_info.pada,moon.sign)
    return {'lagna':position(chart.ascendant),
            'planets':{k:position(chart.planets[Planet(i)]) for i,k in enumerate(PLANET_KEYS)},
            'avakhada':{'varna':ava.varna,'vashya':ava.vashya,'yoni':ava.yoni,'gana':ava.gana,'nadi':ava.nadi,
                        'sign_lord':PLANET_KEYS[ava.sign_lord.value],'nakshatra_lord':PLANET_KEYS[ava.nakshatra_lord.value],
                        'name_letter':ava.name_letter,'tatva':ava.tatva,'paya':ava.paya}}

# North Indian chart: houses are fixed, signs rotate with the Lagna. Text anchor per house on a 300 grid.
HOUSE_TEXT={1:(150,78),2:(75,36),3:(36,80),4:(80,150),5:(36,222),6:(75,262),7:(150,222),8:(225,262),9:(264,222),10:(220,150),11:(264,80),12:(225,36)}
# Sign numbers sit near the inner corner of each house.
HOUSE_SIGN={1:(150,135),2:(75,64),3:(64,75),4:(135,150),5:(64,225),6:(75,236),7:(150,165),8:(225,236),9:(236,225),10:(165,150),11:(236,75),12:(225,64)}

def north_chart(d,locale):
    """Lagna (D1) chart in the North Indian diamond layout, as HTML for the PDF.

    Lines and sign numbers are SVG; planet labels are positioned HTML because WeasyPrint's SVG text
    does not shape Devanagari (vowel signs detach). Styles come from report.py (.nchart).
    """
    lagna=d['lagna']['sign']
    by_house={h:[] for h in range(1,13)}
    for key,p in d['planets'].items():
        by_house[(p['sign']-lagna)%12+1].append(PLANET_ABBR[locale][key]+('*' if p['retrograde'] and key not in ('rahu','ketu') else ''))
    by_house[1].insert(0,'La' if locale=='en' else 'ल')
    # Presentation attributes rather than CSS classes: WeasyPrint's SVG renderer ignores document styles.
    svg=['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 300" width="78mm" height="78mm" font-family="Noto Serif, serif">',
         '<rect x="1" y="1" width="298" height="298" fill="#fffaf0" stroke="#7a2e1d" stroke-width="2"/>',
         '<path d="M1 1L299 299M299 1L1 299M150 1L299 150L150 299L1 150Z" fill="none" stroke="#7a2e1d" stroke-width="1.3"/>']
    labels=[]
    for h in range(1,13):
        x,y=HOUSE_SIGN[h]
        svg.append(f'<text x="{x}" y="{y+3.5}" font-size="10" fill="#c1611c" text-anchor="middle">{(lagna+h-1)%12+1}</text>')
        x,y=HOUSE_TEXT[h]; items=by_house[h]
        # Narrow triangles hold two per line, central houses three.
        per=3 if h in (1,4,7,10) else 2
        lines='<br>'.join(escape(' '.join(items[i:i+per])) for i in range(0,len(items),per))
        if lines: labels.append(f'<div class="pl" style="left:{x/3-15:.2f}%;top:{y/3:.2f}%">{lines}</div>')
    svg.append('</svg>')
    return f'<div class="nchart">{"".join(svg)}{"".join(labels)}</div>'
