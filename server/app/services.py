"""External calculation boundary, PDF rendering and private report storage."""
import hashlib
import math
import httpx
import boto3
from botocore.config import Config
from .config import settings
from .report import report_html

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

def render_pdf(match,locale,summary=None):
    from weasyprint import HTML
    return HTML(string=report_html(match,locale,summary)).write_pdf()

def store_report(report,match,summary=None):
    if not settings.s3_bucket: raise PermanentFailure('storage_not_configured')
    pdf=render_pdf(match,report.locale,summary)
    checksum=hashlib.sha256(pdf).hexdigest()
    key=f'reports/{report.owner_id}/{match.id}/{report.id}.pdf'
    extra={'ServerSideEncryption':settings.s3_sse} if settings.s3_sse else {}
    s3().put_object(Bucket=settings.s3_bucket,Key=key,Body=pdf,ContentType='application/pdf',Metadata={'sha256':checksum},**extra)
    return key,checksum
