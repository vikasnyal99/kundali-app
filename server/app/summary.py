"""Match summaries: OpenAI-written explanation around the engine's facts, with a deterministic fallback.

The model never produces or changes a score. It receives only the koota table, Moon-chart attributes and
dosha flags (no names, birth dates or places); it writes {P1}/{P2} and names are filled in here. An answer
that mentions a number absent from the facts is rejected and the template is used instead.
"""
import json
import logging
import re
import threading
import httpx
from .config import settings
from . import jyotish

log=logging.getLogger('summary')
VERSION='v1'
KOOTA_ORDER=['varna','vashya','tara','yoni','graha_maitri','gana','bhakoot','nadi']
KOOTA_NAMES={'en':{'varna':'Varna','vashya':'Vashya','tara':'Tara','yoni':'Yoni','graha_maitri':'Graha Maitri','gana':'Gana','bhakoot':'Bhakoot','nadi':'Nadi'},
 'hi':{'varna':'वर्ण','vashya':'वश्य','tara':'तारा','yoni':'योनि','graha_maitri':'ग्रह मैत्री','gana':'गण','bhakoot':'भकूट','nadi':'नाड़ी'}}
AREAS={'en':{'varna':'Spiritual temperament and approach to duty','vashya':'Mutual attraction and influence','tara':'Well-being and fortune (birth stars)',
  'yoni':'Instinctive nature and physical compatibility','graha_maitri':'Mental wavelength and friendship','gana':'Temperament',
  'bhakoot':'Emotional bond, family welfare and prosperity','nadi':'Health and progeny (carries the most weight)'},
 'hi':{'varna':'आध्यात्मिक स्वभाव और कर्तव्य-बोध','vashya':'परस्पर आकर्षण और प्रभाव','tara':'स्वास्थ्य और भाग्य (जन्म तारा)','yoni':'स्वाभाविक प्रकृति और शारीरिक अनुकूलता',
  'graha_maitri':'मानसिक तालमेल और मित्रता','gana':'स्वभाव','bhakoot':'भावनात्मक संबंध, परिवार का कल्याण और समृद्धि','nadi':'स्वास्थ्य और संतान (सबसे अधिक महत्त्व)'}}
# Which per-person attribute each koota compares.
ATTRIBUTE={'varna':'varna','vashya':'vashya','tara':'nakshatra','yoni':'yoni','graha_maitri':'sign_lord','gana':'gana','bhakoot':'rashi','nadi':'nadi'}
BANDS={'en':{'excellent':'Excellent match (Ati-uttam)','good':'Good match (Uttam)','average':'Average match (Madhyam)','low':'Below the traditional threshold (Adham)'},
 'hi':{'excellent':'अति उत्तम मिलान','good':'उत्तम मिलान','average':'मध्यम मिलान','low':'पारंपरिक सीमा से कम (अधम)'}}
DOSHAS={'en':{'nadi':'Nadi Dosha','bhakoot':'Bhakoot Dosha','gana':'Gana Dosha'},'hi':{'nadi':'नाड़ी दोष','bhakoot':'भकूट दोष','gana':'गण दोष'}}

def band(score):
    return 'excellent' if score>=33 else 'good' if score>=25 else 'average' if score>=18 else 'low'

def num(v):
    return str(int(v)) if float(v).is_integer() else str(v)

def attributes(d,locale):
    """Per-person values compared by each koota, localized; None without chart details."""
    if not d: return None
    a=d['avakhada']; moon=d['planets']['moon']
    return {'varna':jyotish.name('',a['varna'],locale),'vashya':jyotish.name('',a['vashya'],locale),'yoni':jyotish.name('',a['yoni'],locale),
            'gana':jyotish.name('',a['gana'],locale),'nadi':jyotish.name('',a['nadi'],locale),'sign_lord':jyotish.name('planet',a['sign_lord'],locale),
            'rashi':jyotish.name('sign',moon['sign'],locale),'nakshatra':f"{jyotish.name('nakshatra',moon['nakshatra'],locale)} ({moon['pada']})"}

def context(match,locale,details=None):
    """Everything a summary or report states, taken from stored facts plus recomputed chart details."""
    facts=match.facts; people=match.snapshot['people']
    if details is None: details=[safe_details(p) for p in people]
    attrs=[attributes(d,locale) for d in details]
    rows={r['key']:r for r in facts['score']['kootas']}
    kootas=[{'key':k,'name':KOOTA_NAMES[locale][k],'area':AREAS[locale][k],'earned':rows[k]['earned'],'possible':rows[k]['possible'],
             'p1':attrs[0][ATTRIBUTE[k]] if attrs[0] else None,'p2':attrs[1][ATTRIBUTE[k]] if attrs[1] else None} for k in KOOTA_ORDER if k in rows]
    score=facts['score']['earned']
    doshas=[k for k in ('nadi','bhakoot','gana') if k in rows and rows[k]['earned']==0]
    return {'names':[p['display_name'] for p in people],'score':score,'possible':36,'band':band(score),'band_text':BANDS[locale][band(score)],
            'kootas':kootas,'doshas':doshas,'dosha_names':[DOSHAS[locale][k] for k in doshas],'details':details,'warnings':facts.get('warnings',[])}

def safe_details(person):
    try: return jyotish.details(person)
    except Exception:
        log.warning('chart details unavailable')
        return None

TEXT={'en':{
  'overview':'{P1} and {P2} share {score} of 36 gunas in the traditional Ashta Koota (Guna Milan) method.',
  'excellent':'Traditionally this is regarded as a very strong match.','good':'Traditionally a score in this range is considered a good match.',
  'average':'Traditionally this is an acceptable match; families usually also look at the individual kootas and both full charts.',
  'low':'Traditionally a score below 18 is not recommended without a detailed review of both charts by an astrologer.',
  'dosha':'{doshas} is present here; traditionally it is reviewed together with its cancellation (parihar) rules, which this report does not evaluate.',
  'cultural':'This is a cultural reading, not a prediction about the relationship.',
  'compare':'{P1}: {a}; {P2}: {b}.','full':'Fully matched.','partial':'Partly matched ({earned} of {possible}).','zero':'Not matched (0 of {possible}).',
  'strength':'{name} is fully matched: {area}.','concern':'{name} scores {earned} of {possible}: {area}.',
  'guidance':'Use this as one input among many. Talk openly about values, family expectations and life goals, and consult a trusted astrologer for Manglik and dosha-cancellation checks before any decision.'},
 'hi':{
  'overview':'पारंपरिक अष्टकूट (गुण मिलान) पद्धति में {P1} और {P2} के 36 में से {score} गुण मिलते हैं।',
  'excellent':'परंपरा के अनुसार यह बहुत श्रेष्ठ मिलान माना जाता है।','good':'परंपरा के अनुसार इस श्रेणी के गुण अच्छा मिलान माने जाते हैं।',
  'average':'परंपरा के अनुसार यह स्वीकार्य मिलान है; परिवार प्रायः अलग-अलग कूट और दोनों पूरी कुंडलियाँ भी देखते हैं।',
  'low':'परंपरा के अनुसार 18 से कम गुण होने पर ज्योतिषी से दोनों कुंडलियों की विस्तृत समीक्षा के बिना विवाह की सलाह नहीं दी जाती।',
  'dosha':'यहाँ {doshas} है; परंपरा में इसे परिहार (दोष-निवारण) नियमों के साथ देखा जाता है, जिनका मूल्यांकन यह रिपोर्ट नहीं करती।',
  'cultural':'यह सांस्कृतिक व्याख्या है, रिश्ते के बारे में भविष्यवाणी नहीं।',
  'compare':'{P1}: {a}; {P2}: {b}।','full':'पूर्ण मिलान।','partial':'आंशिक मिलान ({possible} में से {earned})।','zero':'मिलान नहीं ({possible} में से 0)।',
  'strength':'{name} पूर्ण रूप से मिलता है: {area}।','concern':'{name} में {possible} में से {earned} गुण: {area}।',
  'guidance':'इसे निर्णय के कई आधारों में से एक मानें। मूल्यों, पारिवारिक अपेक्षाओं और जीवन-लक्ष्यों पर खुलकर बात करें, और किसी भी निर्णय से पहले मांगलिक व दोष-परिहार की जाँच किसी विश्वसनीय ज्योतिषी से कराएँ।'}}

def template(ctx,locale):
    """Deterministic summary built only from the context; also the fallback for any AI failure."""
    T=TEXT[locale]; P1,P2=ctx['names']
    overview=[T['overview'].format(P1=P1,P2=P2,score=num(ctx['score'])),T[ctx['band']]]
    if ctx['doshas']: overview.append(T['dosha'].format(doshas=', '.join(ctx['dosha_names'])))
    overview.append(T['cultural'])
    notes={}
    for k in ctx['kootas']:
        status=T['full'] if k['earned']==k['possible'] else T['zero'] if k['earned']==0 else T['partial']
        compare=T['compare'].format(P1=P1,P2=P2,a=k['p1'],b=k['p2']) if k['p1'] else ''
        notes[k['key']]=' '.join(x for x in (k['area']+('.' if locale=='en' else '।'),compare,status.format(earned=num(k['earned']),possible=num(k['possible']))) if x)
    return {'headline':ctx['band_text'],'overview':' '.join(overview),'notes':notes,
            'strengths':[T['strength'].format(name=k['name'],area=k['area'].lower() if locale=='en' else k['area']) for k in ctx['kootas'] if k['earned']==k['possible']],
            'considerations':[T['concern'].format(name=k['name'],earned=num(k['earned']),possible=num(k['possible']),area=k['area'].lower() if locale=='en' else k['area']) for k in ctx['kootas'] if k['earned']<k['possible']/2],
            'guidance':T['guidance']}

SYSTEM='''You explain a traditional Vedic Ashta Koota (Guna Milan) marriage-matching result to an Indian family, the way an experienced, kind pandit would, in plain language.
Rules:
- Use ONLY the facts provided. Never calculate, change, round or invent scores, kootas, doshas, planets or chart features.
- Write NO numbers at all, neither digits nor number words (no scores, points, totals or counts): the app shows every score next to your text. Never mention birth dates, times or places.
- Use the koota names, attribute values and band exactly as given (same spelling and script).
- Refer to the two people only as {P1} and {P2}, exactly with the braces. {P1} holds the groom-side rule position, {P2} the bride-side.
- The listed doshas come from kootas with zero points; say traditional cancellation (parihar) rules exist but were not evaluated. Manglik was not evaluated.
- Be balanced and respectful; no fear, no guarantees, no predictions about health or children, no advice to marry or not marry. Mention once that this is a cultural tradition, not a prediction.
- headline: one short line naming the traditional verdict. overview: 3-5 sentences. kootas: exactly one 1-2 sentence note per koota key explaining what the two attributes mean together. strengths/considerations: 2-4 short points each (considerations may be empty if nothing is weak). guidance: 2-3 practical sentences.
- Write in {language}.'''

SCHEMA={'type':'object','additionalProperties':False,'required':['headline','overview','kootas','strengths','considerations','guidance'],'properties':{
  'headline':{'type':'string'},'overview':{'type':'string'},
  'kootas':{'type':'array','items':{'type':'object','additionalProperties':False,'required':['key','note'],'properties':{'key':{'type':'string','enum':KOOTA_ORDER},'note':{'type':'string'}}}},
  'strengths':{'type':'array','items':{'type':'string'}},'considerations':{'type':'array','items':{'type':'string'}},'guidance':{'type':'string'}}}

def ai_enabled():
    return bool(settings.openai_api_key and settings.openai_model)

def ai_payload(ctx):
    return {'total_gunas':ctx['score'],'maximum':36,'traditional_band':ctx['band_text'],'doshas':ctx['dosha_names'],
            'kootas':[{'key':k['key'],'name':k['name'],'governs':k['area'],'points':k['earned'],'maximum':k['possible'],'P1':k['p1'],'P2':k['p2']} for k in ctx['kootas']],
            'not_evaluated':['manglik','dosha cancellation (parihar)'],
            'calculation_notes':ctx['warnings']}

DIGITS=str.maketrans('०१२३४५६७८९','0123456789')

def check(answer,ctx):
    """Reject an AI answer that is incomplete or states any number (scores are shown from the facts)."""
    keys=[k['key'] for k in answer['kootas']]
    if sorted(keys)!=sorted(k['key'] for k in ctx['kootas']): raise ValueError('koota_notes')
    text=' '.join([answer['headline'],answer['overview'],answer['guidance'],*answer['strengths'],*answer['considerations'],*(k['note'] for k in answer['kootas'])])
    if not answer['overview'].strip() or len(text)>12000: raise ValueError('length')
    if re.search(r'\d',re.sub(r'\{P[12]\}','',text).translate(DIGITS)): raise ValueError('unexpected_number')
    if re.search(r'\{(?!P[12]\})[^}]*\}',text): raise ValueError('placeholder')

def ask_openai(ctx,locale):
    system=SYSTEM.replace('{language}','Hindi (Devanagari script, simple everyday Hindi; the method is called अष्टकूट गुण मिलान)' if locale=='hi' else 'English')
    body={'model':settings.openai_model,'max_completion_tokens':2500,
          'messages':[{'role':'system','content':system},{'role':'user','content':json.dumps(ai_payload(ctx),ensure_ascii=False)}],
          'response_format':{'type':'json_schema','json_schema':{'name':'match_summary','strict':True,'schema':SCHEMA}}}
    with httpx.Client(timeout=settings.openai_timeout_seconds) as client:
        response=client.post(f'{settings.openai_base_url}/chat/completions',json=body,headers={'Authorization':f'Bearer {settings.openai_api_key}'})
        response.raise_for_status()
    answer=json.loads(response.json()['choices'][0]['message']['content'])
    check(answer,ctx)
    P1,P2=ctx['names']
    fill=lambda s:s.replace('{P1}',P1).replace('{P2}',P2)
    return {'headline':fill(answer['headline']),'overview':fill(answer['overview']),'notes':{k['key']:fill(k['note']) for k in answer['kootas']},
            'strengths':[fill(s) for s in answer['strengths']],'considerations':[fill(s) for s in answer['considerations']],'guidance':fill(answer['guidance'])}

def build(match,locale):
    """Returns (summary, cacheable). An AI failure falls back to the template without caching it."""
    ctx=context(match,locale)
    source='template'; text=None; cacheable=True
    if ai_enabled():
        try:
            text=ask_openai(ctx,locale); source='ai'
        except httpx.HTTPStatusError as exc:
            log.warning('summary for match %s: openai http %s',match.id,exc.response.status_code); cacheable=False
        except Exception as exc:
            # Never log prompts or answers: they contain the people's chart attributes.
            log.warning('summary for match %s: %s',match.id,type(exc).__name__ if not isinstance(exc,ValueError) else exc); cacheable=False
    if text is None: text=template(ctx,locale)
    summary={'version':VERSION,'source':source,'locale':locale,'names':ctx['names'],'score':ctx['score'],'possible':36,'band':ctx['band'],'band_text':ctx['band_text'],
             'headline':text['headline'],'overview':text['overview'],'strengths':text['strengths'],'considerations':text['considerations'],'guidance':text['guidance'],
             'doshas':[{'key':k,'name':n} for k,n in zip(ctx['doshas'],ctx['dosha_names'])],
             'kootas':[{**{f:k[f] for f in ('key','name','area','earned','possible','p1','p2')},'note':text['notes'].get(k['key'],'')} for k in ctx['kootas']]}
    return summary,cacheable

# One lock per (match, locale) bucket so a pre-warm and a page view do not both call the API.
LOCKS=[threading.Lock() for _ in range(64)]

def fresh(cached):
    return bool(cached) and cached.get('version')==VERSION and (cached.get('source')=='ai' or not ai_enabled())

def ensure(db,match,locale):
    """Cached summary for a ready match, generating and storing it on first use."""
    cached=(match.summaries or {}).get(locale)
    if fresh(cached): return cached
    with LOCKS[hash((match.id,locale))%len(LOCKS)]:
        db.refresh(match)
        cached=(match.summaries or {}).get(locale)
        if fresh(cached): return cached
        summary,cacheable=build(match,locale)
        if cacheable:
            match.summaries={**(match.summaries or {}),locale:summary}; db.commit()
        return summary
