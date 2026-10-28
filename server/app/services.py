"""External calculation boundary and deterministic, privacy-conscious PDF reports."""
import hashlib
import math
from html import escape
import httpx
import boto3
from botocore.config import Config
from .config import settings

KOOTAS = {'varna':1,'vashya':2,'tara':3,'yoni':4,'graha_maitri':5,'gana':6,'bhakoot':7,'nadi':8}
class PermanentFailure(Exception): pass

def validate_facts(facts,version=None,ruleset='provider-validated-v1'):
    try:
        score=facts['score']; rows=score['kootas']
        if len(rows)!=8 or {r['key'] for r in rows}!=set(KOOTAS): raise ValueError()
        for r in rows:
            if r['possible']!=KOOTAS[r['key']] or not math.isfinite(r['earned']) or not 0<=r['earned']<=r['possible']: raise ValueError()
        if score['possible']!=36 or not math.isclose(sum(r['earned'] for r in rows),score['earned']): raise ValueError()
        if facts['calculation']['version']!=(version or settings.astrology_engine_version): raise ValueError()
        if facts['calculation']['ayanamsa']!='lahiri': raise ValueError()
        if facts['calculation']['ruleset']!=ruleset: raise ValueError()
        warnings=facts.get('warnings',[])
        if not isinstance(warnings,list) or not all(isinstance(w,str) for w in warnings): raise ValueError()
        # Manglik stays unavailable until a validated rule variant exists; never pass through unreviewed verdicts.
        validated={'score':score,'calculation':facts['calculation'],'warnings':warnings,'manglik':{'status':'unavailable'}}
        if 'charts' in facts: validated['charts']=facts['charts']
        return validated
    except (KeyError,TypeError,ValueError): raise PermanentFailure('invalid_engine_response')

def calculate(snapshot):
    if any(p['time_accuracy']=='unknown' for p in snapshot['people']): raise PermanentFailure('birth_time_required')
    if settings.astrology_mode == 'local_experimental':
        from .local_engine import calculate_local, VERSION, RULESET
        facts = validate_facts(calculate_local(snapshot),VERSION,RULESET)
        if any(p['time_accuracy']=='approximate' for p in snapshot['people']): facts['warnings'].append('approximate_birth_time')
        return facts
    if not settings.astrology_url: raise PermanentFailure('calculation_unavailable')
    # Identifiers and names are deliberately excluded from the external request.
    fields=('birth_utc','latitude','longitude','birth_timezone','time_accuracy')
    body={'people':[{k:p[k] for k in fields} for p in snapshot['people']],'settings':snapshot['settings']}
    with httpx.Client(timeout=45) as client:
        response=client.post(settings.astrology_url,json=body,headers={'Authorization':f'Bearer {settings.astrology_api_key}'})
        response.raise_for_status()
    facts=validate_facts(response.json())
    if any(p['time_accuracy']=='approximate' for p in snapshot['people']): facts['warnings']=[*facts['warnings'],'approximate_birth_time']
    return facts

def s3():
    # SigV4 explicitly: regions launched after 2014 (e.g. ap-south-1) reject legacy SigV2 presigned URLs.
    # Regional endpoint on AWS: presigned URLs for the global host get a 307 to the region, which breaks the signature.
    endpoint=settings.s3_endpoint_url or f'https://s3.{settings.s3_region}.amazonaws.com'
    return boto3.client('s3',endpoint_url=endpoint,region_name=settings.s3_region,config=Config(signature_version='s3v4',s3={'addressing_style':'path' if settings.s3_endpoint_url else 'virtual'}))

KOOTA_NAMES={'en':{'varna':'Varna','vashya':'Vashya','tara':'Tara','yoni':'Yoni','graha_maitri':'Graha Maitri','gana':'Gana','bhakoot':'Bhakoot','nadi':'Nadi'},
 'hi':{'varna':'वर्ण','vashya':'वश्य','tara':'तारा','yoni':'योनि','graha_maitri':'ग्रह मैत्री','gana':'गण','bhakoot':'भकूट','nadi':'नाड़ी'}}
WARNINGS={'en':{'experimental_engine':'Experimental calculation engine.','independent_validation_pending':'Independent validation of the rules is pending.','approximate_birth_time':'At least one birth time is approximate.','moon_near_boundary_time_sensitive':'The Moon is near a nakshatra or sign boundary; an approximate birth time could change the result.'},
 'hi':{'experimental_engine':'प्रायोगिक गणना इंजन।','independent_validation_pending':'नियमों का स्वतंत्र सत्यापन लंबित है।','approximate_birth_time':'कम से कम एक जन्म समय अनुमानित है।','moon_near_boundary_time_sensitive':'चंद्रमा नक्षत्र या राशि सीमा के निकट है; अनुमानित जन्म समय से परिणाम बदल सकता है।'}}
LABELS={'en':{'title':'Kundli matching report','score':'Ashta Koota score','koota':'Koota','points':'Points','warnings':'Warnings','method':'Methodology','people':'Birth details','person1':'Person 1 (groom-side rule position)','person2':'Person 2 (bride-side rule position)','manglik':'Manglik assessment is unavailable in this version.','engine':'Engine','version':'Version','ruleset':'Ruleset','ayanamsa':'Ayanamsa','calculated_at':'Calculated at (UTC)','validation':'Validation status','exact':'exact time','approximate':'approximate time','unknown':'time unknown'},
 'hi':{'title':'कुंडली मिलान रिपोर्ट','score':'अष्टकूट गुण','koota':'कूट','points':'अंक','warnings':'चेतावनियाँ','method':'गणना पद्धति','people':'जन्म विवरण','person1':'व्यक्ति 1 (वर-पक्ष नियम स्थान)','person2':'व्यक्ति 2 (वधू-पक्ष नियम स्थान)','manglik':'इस संस्करण में मांगलिक मूल्यांकन उपलब्ध नहीं है।','engine':'इंजन','version':'संस्करण','ruleset':'नियम-सेट','ayanamsa':'अयनांश','calculated_at':'गणना समय (UTC)','validation':'सत्यापन स्थिति','exact':'सटीक समय','approximate':'अनुमानित समय','unknown':'समय अज्ञात'}}

def narrative(facts,locale):
    score=facts['score']['earned']
    if locale=='hi': return f'पारंपरिक अष्टकूट गणना में {score} / 36 गुण प्राप्त हुए। यह सांस्कृतिक व्याख्या है, रिश्ते की सफलता का वैज्ञानिक प्रमाण नहीं। आपसी समझ, सहमति और संवाद भी महत्वपूर्ण हैं।'
    return f'The traditional Ashta Koota calculation gives {score} / 36 points. This is a cultural interpretation, not scientific evidence of relationship success. Mutual understanding, consent and communication matter.'

def report_html(match,locale):
    """Deterministic report content: only stored facts and fixed copy, no generated claims."""
    facts=match.facts; L=LABELS[locale]; e=lambda v:escape(str(v))
    people=match.snapshot['people']
    names=' & '.join(e(p['display_name']) for p in people)
    rows=''.join(f"<tr><td>{e(KOOTA_NAMES[locale].get(r['key'],r['key']))}</td><td class='n'>{e(r['earned'])} / {e(r['possible'])}</td></tr>" for r in facts['score']['kootas'])
    births=''.join(f"<tr><td>{e(L['person1' if i==0 else 'person2'])}</td><td>{e(p['display_name'])}<br>{e(p['birth_date'])} {e(p['birth_time_local'])} ({e(p['birth_timezone'])}) · {e(L.get(p['time_accuracy'],p['time_accuracy']))}<br>{e(p['birth_place_name'])} · {e(p['latitude'])}, {e(p['longitude'])}</td></tr>" for i,p in enumerate(people))
    warnings=''.join(f"<li>{e(WARNINGS[locale].get(w,w))}</li>" for w in facts['warnings'])
    calc=facts['calculation']
    method=''.join(f"<tr><td>{e(L[k])}</td><td>{e(calc[k])}</td></tr>" for k in ('engine','version','ruleset','ayanamsa','calculated_at','validation') if k in calc)
    return f'''<html lang="{locale}"><meta charset="utf-8"><title>{e(L['title'])}</title><style>
    @page {{size:A4;margin:20mm;@bottom-center{{content:counter(page) " / " counter(pages);font-size:9pt;color:#666}}}}
    body{{font-family:'Noto Sans Devanagari','Noto Sans','DejaVu Sans',sans-serif;color:#202c28;font-size:11pt;line-height:1.5}}
    h1{{color:#355c50;margin:0 0 4mm}} h2{{font-size:13pt;margin:7mm 0 2mm}} .score{{font-size:30pt;color:#355c50;margin:2mm 0}}
    table{{width:100%;border-collapse:collapse}} td{{padding:5px 7px;border-bottom:1px solid #ddd;vertical-align:top}} td.n{{text-align:right;white-space:nowrap}}
    .small{{font-size:9pt;overflow-wrap:anywhere}} tr{{page-break-inside:avoid}}
    </style><h1>{e(L['title'])}</h1><p>{names}</p>
    <h2>{e(L['score'])}</h2><p class="score">{e(facts['score']['earned'])} / 36</p><p>{e(narrative(facts,locale))}</p>
    <table><tr><th align="left">{e(L['koota'])}</th><th align="right">{e(L['points'])}</th></tr>{rows}</table>
    {f"<h2>{e(L['warnings'])}</h2><ul>{warnings}</ul>" if warnings else ''}<p>{e(L['manglik'])}</p>
    <h2>{e(L['people'])}</h2><table class="small">{births}</table>
    <h2>{e(L['method'])}</h2><table class="small">{method}</table></html>'''

def render_pdf(match,locale):
    from weasyprint import HTML
    return HTML(string=report_html(match,locale)).write_pdf()

def store_report(report,match):
    if not settings.s3_bucket: raise PermanentFailure('storage_not_configured')
    pdf=render_pdf(match,report.locale)
    checksum=hashlib.sha256(pdf).hexdigest()
    key=f'reports/{report.owner_id}/{match.id}/{report.id}.pdf'
    extra={'ServerSideEncryption':settings.s3_sse} if settings.s3_sse else {}
    s3().put_object(Bucket=settings.s3_bucket,Key=key,Body=pdf,ContentType='application/pdf',Metadata={'sha256':checksum},**extra)
    return key,checksum
