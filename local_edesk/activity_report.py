"""Generate a report from the bundled Word template; no customer template paths accepted."""
from pathlib import Path
from datetime import date
from zipfile import ZipFile
from html import escape, unescape
import base64, hashlib, re, uuid, tempfile, shutil, threading
import pythoncom, win32com.client
SOURCE = Path(__file__).resolve().parent / 'templates/relatorio-consultoria.docx'
LOCK = threading.Lock()

def generate(data):
    checksum = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    name = uuid.uuid4().hex
    folder = Path(tempfile.mkdtemp(prefix='gerenciador-relatorio-'))
    pdf = folder/(name+'.pdf')
    working = folder/(name+'.docx')
    replacements = {
        'Clique aqui para inserir uma data.': date.fromisoformat(data['date']).strftime('%d/%m/%Y'),
        'Número da Solicitação:': 'Número da Solicitação: ' + data['id'],
        'Promob XXXXX': data['system'] or '[Nome do sistema]',
        'Nome do Consultor': data['consultant'],
        'Nome de quem participou da consultoria': data['participants'] or '[Participantes]',
        'Nome Participantes': data['signatureParticipants'] or data['participants'] or '[Participantes]',
        'Nome da empresa': data['company'] or '[Nome da empresa]',
        '(INSERIR AQUI A LISTA DE ATIVIDADES REALIZADAS)': '\r'.join('• '+a for a in data['activities'] if a.strip()) or '• [Atividade realizada]',
    }
    counts = {}
    def paragraph(match):
        xml = match.group()
        for old, value in replacements.items():
            nodes = list(re.finditer(r'(<w:t\b[^>]*>)(.*?)(</w:t>)', xml, re.S))
            texts = [unescape(n[2]) for n in nodes]
            full = ''.join(texts)
            at = full.find(old)
            if at < 0: continue
            counts[old] = counts.get(old,0)+1
            if old == 'Nome da empresa' and counts[old] > 1:
                value = data['signatureCompany'] or data['company'] or '[Nome da empresa]'
            offset = 0
            changes = []
            inserted = False
            for node,text in zip(nodes,texts):
                end = offset+len(text)
                if end > at and offset < at+len(old):
                    left = max(0,at-offset)
                    right = min(len(text),at+len(old)-offset)
                    new = text[:left]+(value if not inserted else '')+text[right:]
                    inserted = True
                    encoded = escape(new, quote=False).replace('\r','</w:t><w:br/><w:t xml:space="preserve">')
                    changes.append((node.start(),node.end(),'<w:t xml:space="preserve">'+encoded+'</w:t>'))
                offset=end
            for start,end,new in reversed(changes): xml=xml[:start]+new+xml[end:]
        return xml
    with ZipFile(SOURCE) as source, ZipFile(working,'w') as dest:
        for info in source.infolist():
            content=source.read(info.filename)
            if info.filename=='word/document.xml':
                xml=content.decode('utf-8')
                xml=re.sub(r'<w:p\b[^>]*>.*?</w:p>',paragraph,xml,flags=re.S)
                xml=re.sub(r'<w:showingPlcHdr\s*/>', '',xml)
                content=xml.encode('utf-8')
            dest.writestr(info,content)
    app = doc = None
    pythoncom.CoInitialize()
    try:
        app=win32com.client.DispatchEx('Word.Application')
        app.Visible=False
        app.DisplayAlerts=0
        app.AutomationSecurity=3
        doc=app.Documents.Open(str(working),ReadOnly=True,AddToRecentFiles=False)
        print('Fields replaced; exporting PDF', flush=True)
        doc.ExportAsFixedFormat(str(pdf), 17, OpenAfterExport=False)
        return {'pdfBase64': base64.b64encode(pdf.read_bytes()).decode('ascii'), 'filename': 'Relatorio-atividades-'+data['id']+'.pdf'}
    finally:
        if doc is not None: doc.Close(False)
        if app is not None: app.Quit()
        pythoncom.CoUninitialize()
        shutil.rmtree(folder, ignore_errors=True)
        assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == checksum

def execute(body, user):
    data = dict(body.get('documentData') or {})
    data['id'] = str(body.get('projectId') or '')
    if not re.fullmatch(r'[0-9]{1,20}', data['id']):
        raise ValueError('ID de projeto invalido.')
    data['consultant'] = str(user.get('name') or user.get('email') or '').strip()
    if not data['consultant']:
        raise ValueError('Atualize o nome do consultor na sua conta.')
    for field in ['date','system','participants','company','signatureParticipants','signatureCompany']:
        if not isinstance(data.get(field),str) or len(data[field])>800:
            raise ValueError('Campo invalido ou muito longo.')
    date.fromisoformat(data['date'])
    activities=data.get('activities')
    if not isinstance(activities,list) or not 1<=len(activities)<=80 or any(not isinstance(a,str) or not a.strip() or len(a)>2000 for a in activities):
        raise ValueError('Informe de 1 a 80 atividades, com ate 2000 caracteres cada.')
    if not LOCK.acquire(blocking=False):
        raise ValueError('Aguarde o relatorio em geracao.')
    try:
        return generate(data)
    finally:
        LOCK.release()
