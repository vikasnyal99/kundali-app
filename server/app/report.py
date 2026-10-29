"""Janam patri milan style PDF: birth details, Avakhada chakra, Ashtakoot table, Lagna charts and the summary.

Scores come only from the validated match facts; chart details are recomputed for display (jyotish.py);
explanation text is the cached summary (summary.py), which falls back to fixed templates.
"""
from html import escape
from . import jyotish
from .summary import context, template, num

WARNINGS={'en':{'experimental_engine':'Experimental calculation engine.','independent_validation_pending':'Independent validation of the rules is pending.','approximate_birth_time':'At least one birth time is approximate.','moon_near_boundary_time_sensitive':'The Moon is near a nakshatra or sign boundary; an approximate birth time could change the result.'},
 'hi':{'experimental_engine':'प्रायोगिक गणना इंजन।','independent_validation_pending':'नियमों का स्वतंत्र सत्यापन लंबित है।','approximate_birth_time':'कम से कम एक जन्म समय अनुमानित है।','moon_near_boundary_time_sensitive':'चंद्रमा नक्षत्र या राशि सीमा के निकट है; अनुमानित जन्म समय से परिणाम बदल सकता है।'}}
LABELS={'en':{'title':'Kundli matching report','subtitle':'Ashta Koota Guna Milan','invocation':'॥ श्री गणेशाय नमः ॥',
  'groom':'Groom-side (Person 1)','bride':'Bride-side (Person 2)','gunas':'gunas','score':'Gunas matched','of':'out of 36',
  'scale':'Traditional scale: below 18 not recommended · 18–24 average · 25–32 good · 33–36 excellent',
  'doshas':'Doshas','no_dosha':'No Nadi, Bhakoot or Gana dosha','manglik':'Manglik: not evaluated in this version',
  'birth':'Birth details and Avakhada chakra','name':'Name','dob':'Date of birth','tob':'Time of birth','place':'Place of birth','coords':'Latitude / Longitude',
  'tz':'Time zone','accuracy':'Birth time','lagna':'Lagna (Ascendant)','rashi':'Rashi (Moon sign)','rashi_lord':'Rashi lord','nakshatra':'Nakshatra – Pada',
  'nak_lord':'Nakshatra lord','varna':'Varna','vashya':'Vashya','yoni':'Yoni','gana':'Gana','nadi':'Nadi','letter':'Name letter','tatva':'Tatva','paya':'Paya',
  'milan':'Ashtakoot Guna Milan','koota':'Koota','governs':'Governs','max':'Max','got':'Obtained','total':'Total',
  'charts':'Lagna Kundli (D1, North Indian style)','planets':'Planetary positions','planet':'Graha','sign':'Rashi','degree':'Degree','nak':'Nakshatra','retro':'* retrograde',
  'reading':'Interpretation','overview':'Overview','koota_notes':'Koota-wise reading','strengths':'Strengths','considerations':'Points to consider','guidance':'Guidance',
  'dosha_note':'Dosha analysis','method':'Method and notes','engine':'Engine','version':'Version','ruleset':'Ruleset','ayanamsa':'Ayanamsa','calculated_at':'Calculated at (UTC)',
  'validation':'Validation status','warnings':'Calculation notes','ai':'Explanations written with AI from the calculated facts; scores are not AI-generated.',
  'disclaimer':'Traditional astrology is a cultural framework, not scientific evidence of relationship success. Consider consent, communication and shared values.',
  'exact':'exact','approximate':'approximate','unknown':'unknown','footer':'KundliMilan · Guna Milan report'},
 'hi':{'title':'कुंडली मिलान रिपोर्ट','subtitle':'अष्टकूट गुण मिलान','invocation':'॥ श्री गणेशाय नमः ॥',
  'groom':'वर पक्ष (व्यक्ति 1)','bride':'वधू पक्ष (व्यक्ति 2)','gunas':'गुण','score':'मिलने वाले गुण','of':'36 में से',
  'scale':'पारंपरिक मान: 18 से कम अनुशंसित नहीं · 18–24 मध्यम · 25–32 उत्तम · 33–36 अति उत्तम',
  'doshas':'दोष','no_dosha':'नाड़ी, भकूट या गण दोष नहीं','manglik':'मांगलिक: इस संस्करण में मूल्यांकन नहीं',
  'birth':'जन्म विवरण एवं अवकहड़ा चक्र','name':'नाम','dob':'जन्म तिथि','tob':'जन्म समय','place':'जन्म स्थान','coords':'अक्षांश / देशांतर',
  'tz':'समय क्षेत्र','accuracy':'जन्म समय','lagna':'लग्न','rashi':'राशि (चंद्र राशि)','rashi_lord':'राशि स्वामी','nakshatra':'नक्षत्र – चरण',
  'nak_lord':'नक्षत्र स्वामी','varna':'वर्ण','vashya':'वश्य','yoni':'योनि','gana':'गण','nadi':'नाड़ी','letter':'नामाक्षर','tatva':'तत्व','paya':'पाया',
  'milan':'अष्टकूट गुण मिलान','koota':'कूट','governs':'विषय','max':'पूर्णांक','got':'प्राप्त','total':'कुल',
  'charts':'लग्न कुंडली (D1, उत्तर भारतीय शैली)','planets':'ग्रह स्थिति','planet':'ग्रह','sign':'राशि','degree':'अंश','nak':'नक्षत्र','retro':'* वक्री',
  'reading':'फलादेश','overview':'सारांश','koota_notes':'कूट-वार विवेचन','strengths':'अनुकूल पक्ष','considerations':'विचारणीय पक्ष','guidance':'मार्गदर्शन',
  'dosha_note':'दोष विचार','method':'गणना पद्धति एवं टिप्पणियाँ','engine':'इंजन','version':'संस्करण','ruleset':'नियम-सेट','ayanamsa':'अयनांश','calculated_at':'गणना समय (UTC)',
  'validation':'सत्यापन स्थिति','warnings':'गणना संबंधी टिप्पणियाँ','ai':'विवेचन गणना किए गए तथ्यों से AI द्वारा लिखा गया है; गुण AI द्वारा नहीं निकाले गए।',
  'disclaimer':'पारंपरिक ज्योतिष एक सांस्कृतिक दृष्टिकोण है, रिश्ते की सफलता का वैज्ञानिक प्रमाण नहीं। आपसी सहमति, संवाद और साझा मूल्यों पर भी विचार करें।',
  'exact':'सटीक','approximate':'अनुमानित','unknown':'अज्ञात','footer':'KundliMilan · गुण मिलान रिपोर्ट'}}

CSS='''
@page{size:A4;margin:16mm 15mm 18mm;background:#fffaf0;
 @bottom-center{content:FOOTER " · " counter(page) " / " counter(pages);font-size:8pt;color:#8a6a52}}
body{font-family:FONTS;color:#2b1d14;font-size:10pt;line-height:1.45;margin:0}
.frame{position:fixed;top:-8mm;bottom:-10mm;left:-7mm;right:-7mm;border:2.2pt double #8b2c1a;border-radius:2mm}
h1,h2,h3{font-family:HEADFONTS;color:#7a2e1d;margin:0}
h2{font-size:13.5pt;margin:0 0 3mm;padding-bottom:1.2mm;border-bottom:1pt solid #d9a441}
h2:before{content:"";display:inline-block;width:2.3mm;height:2.3mm;background:#d9822b;transform:rotate(45deg);margin:0 2.6mm .6mm .6mm}
h3{font-size:11pt;margin:3mm 0 1mm}
.page{page-break-after:always}.page:last-child{page-break-after:auto}
.inv{text-align:center;color:#c1611c;font-size:12pt;letter-spacing:.5pt;margin-top:2mm}
.title{text-align:center;margin:3mm 0 1mm;font-size:24pt}
.sub{text-align:center;color:#8a6a52;font-size:11pt;letter-spacing:1.5pt;text-transform:uppercase;margin-bottom:5mm}
.couple{display:flex;align-items:stretch;gap:4mm;margin-bottom:5mm}
.side{flex:1;background:#fff;border:1pt solid #e3c48f;border-radius:3mm;padding:3.5mm 4mm}
.side .role{font-size:8pt;color:#a0522d;text-transform:uppercase;letter-spacing:.8pt}
.side .nm{font-family:HEADFONTS;font-size:15pt;color:#2b1d14;margin:1mm 0}
.side .meta{font-size:9pt;color:#5b4636}
.knot{align-self:center;width:4mm;height:4mm;background:#c1611c;transform:rotate(45deg);border:1.2pt solid #fffaf0;outline:1pt solid #c1611c}
.medal{width:36mm;height:36mm;margin:0 auto 2mm;border-radius:50%;background:#7a2e1d;color:#fff;text-align:center;border:3pt solid #d9a441;box-shadow:0 0 0 2pt #fffaf0,0 0 0 3pt #d9a441}
.medal .big{font-family:HEADFONTS;font-size:30pt;line-height:1;padding-top:7mm}
.medal .of{font-size:8.5pt;color:#f6dfb6}
.band{text-align:center;font-family:HEADFONTS;font-size:14pt;color:#7a2e1d;margin:1.5mm 0 0}
.bar{position:relative;height:3.2mm;border-radius:2mm;margin:3mm 10mm 1mm;background:linear-gradient(to right,#c0392b 0%,#c0392b 50%,#e0a030 50%,#e0a030 69.4%,#5e9e4f 69.4%,#5e9e4f 91.6%,#2e7d32 91.6%)}
.pin{position:absolute;top:-1.6mm;width:2mm;height:6.4mm;margin-left:-1mm;background:#2b1d14;border-radius:1mm}
.scale{text-align:center;font-size:8pt;color:#8a6a52;margin-bottom:2mm}
.chips{text-align:center;margin:2mm 0 5mm}
.chip{display:inline-block;border-radius:5mm;padding:1mm 3.5mm;margin:0 1mm;font-size:9pt;border:1pt solid}
.chip.bad{color:#9b2c1f;border-color:#e2a99f;background:#fdf0ed}.chip.ok{color:#2e6b34;border-color:#a8d3ad;background:#f0f8f0}
.chip.na{color:#6b5a4a;border-color:#d9cbb8;background:#f7f1e8}
.box{background:#fff;border:1pt solid #e3c48f;border-left:3pt solid #d9822b;border-radius:2mm;padding:3mm 4mm;margin-bottom:4mm}
.box .hl{font-family:HEADFONTS;font-size:12pt;color:#7a2e1d;margin-bottom:1mm}
table{width:100%;border-collapse:collapse;margin-bottom:4mm}
th{background:#7a2e1d;color:#fff;font-weight:600;font-size:9pt;padding:1.6mm 2mm;text-align:left}
td{padding:1.4mm 2mm;border-bottom:.6pt solid #ead9bf;vertical-align:top}
tr:nth-child(even) td{background:#fdf4e4}
td.k{color:#7a2e1d;font-weight:600;width:34%}
td.c,th.c{text-align:center}
tr.total td{background:#f6e3c0;font-weight:700;color:#7a2e1d;border-top:1pt solid #d9a441}
.pts{display:inline-block;min-width:13mm;text-align:center;border-radius:1.5mm;padding:.3mm 1mm;font-weight:700}
.full{background:#e3f2e1;color:#2e6b34}.part{background:#fbefd5;color:#8a5a00}.zero{background:#f9dcd7;color:#9b2c1f}
.small{font-size:8.5pt}.muted{color:#7a6656}
.compact td{padding:1.05mm 2mm;font-size:9.4pt}
.milan td{padding:1.3mm 1.8mm}
.charts{display:flex;gap:6mm;margin-bottom:3mm}.charts>div{flex:1;text-align:center}
.nchart{position:relative;width:78mm;height:78mm;margin:0 auto}
.nchart svg{position:absolute;left:0;top:0}
.nchart .pl{position:absolute;width:30%;text-align:center;font-weight:700;font-size:9.6pt;line-height:1.25;transform:translateY(-50%)}
.charts .cn{font-family:HEADFONTS;color:#7a2e1d;font-size:11pt;margin-bottom:1.5mm}
.two{display:flex;gap:5mm}.two>div{flex:1}
.two table td,.two table th{font-size:8.6pt;padding:1.1mm 1.6mm}
.note{margin-bottom:1.6mm;page-break-inside:avoid;font-size:9.3pt;line-height:1.38}
.note .nh{font-weight:700;color:#7a2e1d}
ul{margin:1mm 0 3mm;padding-left:5mm}li{margin-bottom:1mm}
.disc{font-size:8.5pt;color:#6b5a4a;border-top:1pt solid #d9a441;padding-top:2mm;margin-top:4mm}
'''

def dms(degree):
    d=int(degree); m=int(round((degree-d)*60))
    if m==60: d,m=d+1,0
    return f"{d}°{m:02d}'"

def css_string(text):
    """A quoted CSS string that cannot end the string or the <style> element."""
    return '"'+''.join(f'\\{ord(c):x} ' if c in '\\"<>\n\r' else c for c in text)+'"'

def pts_class(earned,possible):
    return 'full' if earned==possible else 'zero' if earned==0 else 'part'

def report_html(match,locale,summary=None):
    """Complete report HTML; `summary` is the cached summary.py result, or None for the fixed template."""
    L=LABELS[locale]; e=lambda v:escape(str(v))
    ctx=context(match,locale)
    text=summary or {**template(ctx,locale),'source':'template'}
    notes=text['notes'] if 'notes' in text else {k['key']:k.get('note','') for k in text['kootas']}
    facts=match.facts; people=match.snapshot['people']; details=ctx['details']
    names=[e(p['display_name']) for p in people]
    fonts="'Noto Serif Devanagari','Noto Serif','Noto Sans Devanagari','DejaVu Serif',serif" if locale=='hi' else "'Noto Serif','Noto Serif Devanagari','Noto Sans Devanagari','DejaVu Serif',serif"
    footer=css_string(f"{L['footer']} · {people[0]['display_name']} & {people[1]['display_name']}")
    css=CSS.replace('HEADFONTS',fonts).replace('FONTS',fonts).replace('FOOTER',footer)
    score=facts['score']['earned']

    def side(i):
        p=people[i]; d=details[i]
        extra=''
        if d:
            moon=d['planets']['moon']
            extra=f"<br>{e(L['rashi'].split(' (')[0])}: {e(jyotish.name('sign',moon['sign'],locale))} · {e(L['nakshatra'].split(' –')[0])}: {e(jyotish.name('nakshatra',moon['nakshatra'],locale))}"
        return (f"<div class='side'><div class='role'>{e(L['groom' if i==0 else 'bride'])}</div><div class='nm'>{names[i]}</div>"
                f"<div class='meta'>{e(p['birth_date'])} · {e(str(p['birth_time_local'])[:5])} · {e(p['birth_place_name'])}{extra}</div></div>")

    doshas=''.join(f"<span class='chip bad'>{e(n)}</span>" for n in ctx['dosha_names']) or f"<span class='chip ok'>{e(L['no_dosha'])}</span>"
    cover=f'''<section class="page">
<div class="inv">{e(L['invocation'])}</div><h1 class="title">{e(L['title'])}</h1><div class="sub">{e(L['subtitle'])}</div>
<div class="couple">{side(0)}<div class="knot"></div>{side(1)}</div>
<div class="medal"><div class="big">{e(num(score))}</div><div class="of">{e(L['of'])} {e(L['gunas'])}</div></div>
<div class="band">{e(ctx['band_text'])}</div>
<div class="bar"><div class="pin" style="left:{min(max(score/36*100,0),100):.1f}%"></div></div>
<div class="scale">{e(L['scale'])}</div>
<div class="chips">{doshas}<span class="chip na">{e(L['manglik'])}</span></div>
<!--milan--></section>'''

    # Birth details and Avakhada chakra, one column per person.
    def row(label,values): return f"<tr><td class='k'>{e(label)}</td>"+''.join(f'<td>{v}</td>' for v in values)+'</tr>'
    rows=[row(L['name'],[f'<b>{n}</b>' for n in names]),
          row(L['dob'],[e(p['birth_date']) for p in people]),
          row(L['tob'],[f"{e(str(p['birth_time_local'])[:5])} ({e(L.get(p['time_accuracy'],p['time_accuracy']))})" for p in people]),
          row(L['place'],[e(p['birth_place_name']) for p in people]),
          row(L['coords'],[f"{float(p['latitude']):.4f}, {float(p['longitude']):.4f}" for p in people]),
          row(L['tz'],[e(p['birth_timezone']) for p in people])]
    if all(details):
        def ava(key,kind=''): return [e(jyotish.name(kind,d['avakhada'][key],locale)) for d in details]
        rows+=[row(L['lagna'],[f"{e(jyotish.name('sign',d['lagna']['sign'],locale))} {dms(d['lagna']['degree'])}" for d in details]),
               row(L['rashi'],[e(jyotish.name('sign',d['planets']['moon']['sign'],locale)) for d in details]),
               row(L['rashi_lord'],ava('sign_lord','planet')),
               row(L['nakshatra'],[f"{e(jyotish.name('nakshatra',d['planets']['moon']['nakshatra'],locale))} – {d['planets']['moon']['pada']}" for d in details]),
               row(L['nak_lord'],ava('nakshatra_lord','planet')),
               row(L['varna'],ava('varna')),row(L['vashya'],ava('vashya')),row(L['yoni'],ava('yoni')),row(L['gana'],ava('gana')),
               row(L['nadi'],ava('nadi')),row(L['letter'],ava('name_letter')),row(L['tatva'],ava('tatva')),row(L['paya'],ava('paya'))]
    birth=f"<h2>{e(L['birth'])}</h2><table class='compact'><tr><th></th><th>{e(L['groom'])}</th><th>{e(L['bride'])}</th></tr>{''.join(rows)}</table>"

    has_attr=bool(ctx['kootas']) and ctx['kootas'][0]['p1'] is not None
    milan_rows=''.join(
        f"<tr><td class='c'>{i}</td><td><b>{e(k['name'])}</b></td><td class='small'>{e(k['area'])}</td>"
        +(f"<td class='small'>{e(k['p1'])}</td><td class='small'>{e(k['p2'])}</td>" if has_attr else '')
        +f"<td class='c'>{e(num(k['possible']))}</td><td class='c'><span class='pts {pts_class(k['earned'],k['possible'])}'>{e(num(k['earned']))}</span></td></tr>"
        for i,k in enumerate(ctx['kootas'],1))
    attr_head=f"<th>{names[0]}</th><th>{names[1]}</th>" if has_attr else ''
    milan=(f"<h2>{e(L['milan'])}</h2><table class='milan'><tr><th class='c'>#</th><th>{e(L['koota'])}</th><th>{e(L['governs'])}</th>{attr_head}<th class='c'>{e(L['max'])}</th><th class='c'>{e(L['got'])}</th></tr>"
           f"{milan_rows}<tr class='total'><td></td><td colspan='{4 if has_attr else 2}'>{e(L['total'])}</td><td class='c'>36</td><td class='c'>{e(num(score))} / 36</td></tr></table>")
    cover=cover.replace('<!--milan-->',milan)
    dosha=f"<h3>{e(L['dosha_note'])}</h3><p>{e(', '.join(ctx['dosha_names']) or L['no_dosha'])}. {e(L['manglik'])}.</p>"
    tables=f'<section class="page">{birth}<div class="box"><div class="hl">{e(text["headline"])}</div>{e(text["overview"])}</div>{dosha}</section>'

    charts=''
    if all(details):
        def planet_table(d):
            body=''.join(f"<tr><td>{e(jyotish.name('planet',k,locale))}{'*' if p['retrograde'] and k not in ('rahu','ketu') else ''}</td><td>{e(jyotish.name('sign',p['sign'],locale))}</td><td>{dms(p['degree'])}</td><td>{e(jyotish.name('nakshatra',p['nakshatra'],locale))} – {p['pada']}</td></tr>"
                         for k,p in d['planets'].items())
            lagna=d['lagna']
            first=f"<tr><td><b>{e(L['lagna'].split(' (')[0])}</b></td><td>{e(jyotish.name('sign',lagna['sign'],locale))}</td><td>{dms(lagna['degree'])}</td><td>{e(jyotish.name('nakshatra',lagna['nakshatra'],locale))} – {lagna['pada']}</td></tr>"
            return f"<table><tr><th>{e(L['planet'])}</th><th>{e(L['sign'])}</th><th>{e(L['degree'])}</th><th>{e(L['nak'])}</th></tr>{first}{body}</table>"
        charts=(f'<section class="page"><h2>{e(L["charts"])}</h2><div class="charts">'
                +''.join(f"<div><div class='cn'>{names[i]}</div>{jyotish.north_chart(d,locale)}</div>" for i,d in enumerate(details))
                +f'</div><h2>{e(L["planets"])}</h2><div class="two">'
                +''.join(f"<div><h3>{names[i]}</h3>{planet_table(d)}</div>" for i,d in enumerate(details))
                +f"</div><div class='small muted'>{e(L['retro'])}</div></section>")

    note_html=''.join(f"<div class='note'><span class='nh'>{e(k['name'])}</span> <span class='pts {pts_class(k['earned'],k['possible'])}'>{e(num(k['earned']))} / {e(num(k['possible']))}</span><br>{e(notes.get(k['key'],''))}</div>" for k in ctx['kootas'])
    li=lambda items:'<ul>'+''.join(f'<li>{e(x)}</li>' for x in items)+'</ul>' if items else ''
    calc=facts['calculation']
    method=''.join(f"<tr><td class='k'>{e(L[k])}</td><td>{e(calc[k])}</td></tr>" for k in ('engine','version','ruleset','ayanamsa','calculated_at','validation') if k in calc)
    warnings=''.join(f"<li>{e(WARNINGS[locale].get(w,w))}</li>" for w in facts.get('warnings',[]))
    reading=f'''<section class="page"><h2>{e(L['reading'])}</h2>
<h3>{e(L['koota_notes'])}</h3>{note_html}
{f"<h3>{e(L['strengths'])}</h3>{li(text['strengths'])}" if text['strengths'] else ''}
{f"<h3>{e(L['considerations'])}</h3>{li(text['considerations'])}" if text['considerations'] else ''}
<div class="box"><div class="hl">{e(L['guidance'])}</div>{e(text['guidance'])}</div>
<h2>{e(L['method'])}</h2><table class="small">{method}</table>
{f"<h3>{e(L['warnings'])}</h3><ul class='small'>{warnings}</ul>" if warnings else ''}
<div class="disc">{e(L['ai']) + '<br>' if text.get('source')=='ai' else ''}{e(L['disclaimer'])}</div></section>'''
    return (f'<html lang="{locale}"><head><meta charset="utf-8"><title>{e(L["title"])}</title><style>{css}</style></head>'
            f'<body><div class="frame"></div>{cover}{tables}{charts}{reading}</body></html>')
