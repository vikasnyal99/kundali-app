"""PDF content and rendering. Hindi glyph checks need Noto Sans Devanagari (installed in infra/Dockerfile)."""
import io
import shutil
import subprocess
from types import SimpleNamespace
import pytest
pytest.importorskip('weasyprint')
from pypdf import PdfReader
from app.services import render_pdf, report_html, KOOTAS

def match():
    people=[{'display_name':'Asha <b>&','birth_date':'1997-09-14','birth_time_local':'09:30:00','birth_timezone':'Asia/Kolkata','birth_place_name':'Delhi','latitude':28.6139,'longitude':77.209,'time_accuracy':'exact'},
            {'display_name':'रवि','birth_date':'1996-01-02','birth_time_local':'23:10:00','birth_timezone':'Asia/Kolkata','birth_place_name':'वाराणसी','latitude':25.3,'longitude':83.0,'time_accuracy':'approximate'}]
    kootas=[{'key':k,'earned':m/2,'possible':m} for k,m in KOOTAS.items()]
    facts={'score':{'earned':18.0,'possible':36,'kootas':kootas},'warnings':['approximate_birth_time','independent_validation_pending','new_unmapped_code'],
           'calculation':{'engine':'test-double','version':'v-test','ruleset':'r-test','ayanamsa':'lahiri','calculated_at':'2026-10-28T00:00:00+00:00'},'manglik':{'status':'unavailable'}}
    return SimpleNamespace(id='m1',facts=facts,snapshot={'people':people,'settings':{}})

def fonts(pdf):
    return {str(f['/BaseFont']) for page in PdfReader(io.BytesIO(pdf)).pages for f in page['/Resources']['/Font'].get_object().values()}

@pytest.mark.parametrize('locale,title,koota,warning',[
    ('en','Kundli matching report','Graha Maitri','At least one birth time is approximate.'),
    ('hi','कुंडली मिलान रिपोर्ट','ग्रह मैत्री','कम से कम एक जन्म समय अनुमानित है।')])
def test_report_content_is_localised_escaped_and_complete(locale,title,koota,warning):
    html=report_html(match(),locale)
    assert title in html and koota in html and warning in html and 'new_unmapped_code' in html
    assert 'Asha &lt;b&gt;&amp;' in html and '<b>&' not in html
    assert html.count('<tr><td>')>=8+2  # eight koota rows plus both birth-detail rows
    assert '18.0 / 36' in html and 'v-test' in html and ('approximate time' in html or 'अनुमानित समय' in html)

@pytest.mark.parametrize('locale',['en','hi'])
def test_pdf_renders_with_embedded_fonts(locale):
    pdf=render_pdf(match(),locale)
    assert pdf.startswith(b'%PDF') and len(PdfReader(io.BytesIO(pdf)).pages)>=1
    names=fonts(pdf)
    assert names and all('+' in n for n in names)  # subset-embedded, not referenced from the reader's system
    if locale=='hi':
        if not shutil.which('fc-list') or 'Noto Sans Devanagari' not in subprocess.run(['fc-list'],capture_output=True,text=True).stdout:
            pytest.skip('Noto Sans Devanagari not installed on this machine')
        assert any('NotoSansDevanagari' in n.replace('-','') for n in names)
