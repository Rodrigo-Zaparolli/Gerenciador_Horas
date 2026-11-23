"""Reviewed Zendesk tickets and authentic SLA screenshots in owner-isolated sessions."""
import base64
from datetime import datetime, timezone
import hashlib
import html
import json
import mimetypes
import os
from pathlib import Path
import re
import sys
import tempfile
import time
import uuid

ZENDESK = 'https://compusoftgrouphelp.zendesk.com'
SLA = 'https://sladevcyncly.netlify.app/'
UNITS = {'production': 'Production', 'design': 'Design', 'gestao': 'Sales'}
MAX_ATTACHMENT_BYTES = 8 * 1024 * 1024


class ZendeskRejected(ValueError):
    """A definitive HTTP rejection, as opposed to an unknown POST outcome."""


def text(value, label, limit, required=True):
    if not isinstance(value, str) or len(value) > limit or required and not value.strip():
        raise ValueError(f'Revise o campo {label}.')
    return value.strip()


def priority_input(data):
    if not isinstance(data, dict):
        raise ValueError('Informe os dados da priorização.')
    unit = data.get('unit')
    answers = data.get('answers')
    if not isinstance(unit, str) or unit not in UNITS or not isinstance(answers, list) or len(answers) != 5 or any(type(v) is not int or not 1 <= v <= 5 for v in answers):
        raise ValueError('Escolha a unidade e responda as cinco perguntas da priorização.')
    return {'unit': unit, 'product': text(data.get('product'), 'Produto SLA', 100), 'answers': answers}


def owner_root(owner):
    identity = hashlib.sha256(text(owner, 'usuário', 128).encode()).hexdigest()
    root = Path(os.environ.get('LOCALAPPDATA') or Path.home()) / 'GerenciadorHoras' / 'zendesk' / identity
    root.mkdir(parents=True, exist_ok=True)
    return root


def draft_path(root, draft_id):
    if not isinstance(draft_id, str) or not re.fullmatch(r'[0-9a-f]{32}', draft_id):
        raise ValueError('Recarregue a priorização antes de continuar.')
    folder = root / 'drafts' / draft_id
    if not folder.is_dir():
        raise ValueError('A captura não foi encontrada nesta conta/computador. Capture novamente.')
    return folder


def write_json(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False), encoding='utf-8')
    os.replace(temporary, path)


def capture_on_page(page, data, ticket_id=None):
    """Use live controls/results; never recreate the SLA score, page or image."""
    checked = priority_input(data)
    page.goto(SLA, wait_until='domcontentloaded', timeout=45000)
    page.locator(f'button[data-ud="{UNITS[checked["unit"]]}"]').click()
    page.wait_for_url(SLA + 'promob.html', timeout=30000)
    page.wait_for_function("typeof window.calcularPontuacao === 'function'", timeout=30000)
    if page.locator('#udSelect').input_value() != checked['unit']:
        raise ValueError('A unidade carregada pela ferramenta SLA não corresponde à escolha. Nada foi enviado.')
    available = page.locator('#produtoSelect option').evaluate_all('(items)=>items.map(e=>e.value)')
    if checked['product'] not in available:
        raise ValueError('O produto não está disponível nesta unidade na ferramenta oficial.')
    page.locator('#produtoSelect').select_option(checked['product'])
    for index, answer in enumerate(checked['answers'], 1):
        page.locator(f'#q{index}').select_option(str(answer))
    if ticket_id is not None:
        page.locator('#ticketInput').fill(str(ticket_id))
    page.wait_for_function("/^P[1-5]$/.test(document.querySelector('#prioMain')?.textContent.trim()||'')")
    priority = page.locator('#prioMain').inner_text().strip()
    points = page.locator('#pontosResumo').inner_text().strip()
    if not re.fullmatch(r'\d{1,3}', points) or not 10 <= int(points) <= 50:
        raise ValueError('A pontuação da ferramenta oficial não pôde ser conferida.')
    values = [int(page.locator(f'#q{i}').input_value()) for i in range(1, 6)]
    if values != checked['answers']:
        raise ValueError('A ferramenta oficial não confirmou todas as respostas.')
    result = {**checked, 'priority': priority, 'points': int(points),
              'forecast': page.locator('#idPrevisao').inner_text().strip(),
              'source': SLA, 'capturedAt': datetime.now(timezone.utc).isoformat()}
    return result


def capture(playwright, root, data):
    checked = priority_input(data)
    browser = playwright.chromium.launch(headless=False)
    try:
        page = browser.new_page(viewport={'width': 1440, 'height': 1000}, device_scale_factor=1)
        result = capture_on_page(page, checked)
        image = page.locator('.grid').first.screenshot(type='png', animations='disabled')
        if not image.startswith(b'\x89PNG\r\n\x1a\n') or len(image) > 3*1024*1024:
            raise ValueError('O print da ferramenta oficial não foi gerado corretamente.')
        draft_id = uuid.uuid4().hex
        folder = root / 'drafts' / draft_id
        folder.mkdir(parents=True)
        (folder / 'priorizacao.png').write_bytes(image)
        result.update(draftId=draft_id, imageSha256=hashlib.sha256(image).hexdigest(), state='prepared')
        write_json(folder / 'capture.json', result)
        return {**result, 'imageBase64': base64.b64encode(image).decode(), 'message': 'Print capturado na ferramenta oficial. Nenhum registro SLA foi salvo.'}
    finally:
        browser.close()


def api(context, path, *, method='GET', payload=None, data=None, csrf=None, content_type='application/octet-stream'):
    if not re.fullmatch(r'/api/v2/[a-z_0-9/.]+\.json(?:\?[a-zA-Z0-9_%=&.-]*)?', path):
        raise ValueError('Endereço interno do Zendesk inválido.')
    headers = {'Accept': 'application/json', 'Origin': ZENDESK, 'Referer': ZENDESK + '/agent/home/tickets'}
    if csrf:
        headers['X-CSRF-Token'] = csrf
    kwargs = {'headers': headers, 'timeout': 30000, 'max_redirects': 0}
    if payload is not None:
        kwargs['data'] = json.dumps(payload)
        headers['Content-Type'] = 'application/json'
    if data is not None:
        kwargs['data'] = data
        headers['Content-Type'] = content_type
    response = context.request.fetch(ZENDESK + path, method=method, **kwargs)
    if response.status in (401, 403) or 300 <= response.status < 400:
        raise ZendeskRejected('Entre no Zendesk com uma conta de agente autorizada na janela da integração.')
    if response.status >= 400:
        try:
            details = response.json()
            error = str(details.get('description') or details.get('error') or '')[:240]
        except Exception:
            error = ''
        failure = ZendeskRejected if 400 <= response.status < 500 and response.status not in (408, 429) else ValueError
        raise failure(f'Zendesk recusou a operação (HTTP {response.status}). {error}')
    return response.json()


def current_agent(context):
    user = api(context, '/api/v2/users/me.json').get('user') or {}
    if type(user.get('id')) is not int or user.get('role') not in {'agent', 'admin'}:
        raise ValueError('É necessário entrar no Zendesk com uma conta de agente.')
    return user


def login(context):
    try:
        return current_agent(context)
    except ValueError:
        page = context.pages[0] if context.pages else context.new_page()
        page.goto(ZENDESK + '/agent/home/tickets', wait_until='domcontentloaded', timeout=45000)
        deadline = time.monotonic() + 150
        while time.monotonic() < deadline:
            page.wait_for_timeout(1500)
            try:
                return current_agent(context)
            except ValueError:
                pass
        raise ValueError('Conclua o login na janela do Zendesk e tente Conectar novamente.')


def listing(context, endpoint, key, required=False):
    try:
        result, path = [], endpoint
        for _ in range(20):
            data = api(context, path)
            result.extend(data.get(key) or [])
            next_page = data.get('next_page')
            if not next_page:
                return result
            if not isinstance(next_page, str) or not next_page.startswith(ZENDESK + '/api/v2/'):
                raise ValueError('A paginação do Zendesk não foi reconhecida.')
            path = next_page[len(ZENDESK):]
        raise ValueError('Há mais opções no Zendesk que o limite desta consulta. Refine a configuração.')
    except ValueError:
        if required:
            raise
        return []


def metadata(context, user):
    brands = listing(context, '/api/v2/brands.json', 'brands')
    forms = listing(context, '/api/v2/ticket_forms.json', 'ticket_forms', True)
    fields = listing(context, '/api/v2/ticket_fields.json', 'ticket_fields', True)
    groups = listing(context, '/api/v2/groups.json', 'groups')
    statuses = listing(context, '/api/v2/custom_statuses.json', 'custom_statuses')
    # Keep field IDs/values exactly as returned by this tenant, never guess labels.
    return {'agent': {'id': user['id'], 'name': user.get('name', '')},
            'brands': [{'id': x['id'], 'name': x.get('name', '')} for x in brands if x.get('active', True)],
            'forms': [{'id': x['id'], 'name': x.get('display_name') or x.get('name', ''), 'fieldIds': x.get('ticket_field_ids', [])} for x in forms if x.get('active', True)],
            'groups': [{'id': x['id'], 'name': x.get('name', '')} for x in groups if not x.get('deleted')],
            'customStatuses': [{'id': x['id'], 'name': x.get('agent_label', ''), 'category': x.get('status_category')} for x in statuses if x.get('active')],
            'fields': [{'id': x['id'], 'name': x.get('title', ''), 'type': x.get('type'), 'required': bool(x.get('required')),
                        'options': [{'name': v.get('name', ''), 'value': v.get('value')} for v in x.get('custom_field_options', [])]}
                       for x in fields if x.get('active', True) and x.get('removable') and x.get('type') in {'text', 'textarea', 'checkbox', 'integer', 'decimal', 'date', 'tagger', 'multiselect'}]}


def load_capture(root, data):
    folder = draft_path(root, data.get('draftId'))
    capture = json.loads((folder / 'capture.json').read_text(encoding='utf-8'))
    image = (folder / 'priorizacao.png').read_bytes()
    if hashlib.sha256(image).hexdigest() != capture['imageSha256']:
        raise ValueError('O print mudou. Capture a priorização novamente.')
    if priority_input(data.get('sla')) != {key: capture[key] for key in ('unit', 'product', 'answers')}:
        raise ValueError('As respostas mudaram depois da captura. Capture o print novamente antes de enviar.')
    return folder, capture, image


def compose(description, capture, image_url):
    body = html.escape(text(description, 'Descrição', 20000)).replace('\n', '<br>')
    return f'<div>{body}</div><p><i>Prioridade da solicitação:</i> {capture["priority"]}</p><p><img src="{html.escape(image_url, quote=True)}" alt="Priorização oficial {capture["priority"]}: {capture["points"]} pontos" /></p>'


def validated_ticket(data, meta):
    subject = text(data.get('subject'), 'Assunto', 200)
    text(data.get('description'), 'Descrição', 20000)
    form = next((x for x in meta['forms'] if type(data.get('formId')) is int and x['id'] == data['formId']), None)
    if form is None:
        raise ValueError('Escolha um formulário existente no Zendesk.')
    ticket = {'subject': subject, 'requester_id': meta['agent']['id'], 'ticket_form_id': form['id'], 'type': data.get('type')}
    if ticket['type'] not in {'problem', 'incident', 'question', 'task'}:
        raise ValueError('Escolha um tipo de chamado válido.')
    status = data.get('status')
    if type(status) is int:
        custom = next((x for x in meta['customStatuses'] if x['id'] == status), None)
        if custom is None:
            raise ValueError('Escolha uma situação atual do Zendesk.')
        ticket.update(custom_status_id=status, status=custom['category'])
    elif status in {'new', 'open', 'pending', 'hold'}:
        ticket['status'] = status
    else:
        raise ValueError('Escolha uma situação válida para o novo chamado.')
    for key, collection in [('brandId', 'brands'), ('groupId', 'groups')]:
        selected = data.get(key)
        if selected is not None:
            if type(selected) is not int or not any(x['id'] == selected for x in meta[collection]):
                raise ValueError('Marca ou grupo não encontrado no Zendesk. Conecte novamente.')
            ticket['brand_id' if key == 'brandId' else 'group_id'] = selected
    values = data.get('fields') or {}
    if not isinstance(values, dict) or len(values) > 150:
        raise ValueError('Os campos adicionais do Zendesk são inválidos.')
    available = {str(x['id']): x for x in meta['fields'] if x['id'] in form['fieldIds']}
    if set(values) - set(available):
        raise ValueError('Há campos que não pertencem ao formulário selecionado.')
    custom_fields = []
    for key, field in available.items():
        value = values.get(key)
        if value in (None, '', []):
            if field['required']:
                raise ValueError('Preencha o campo obrigatório: ' + field['name'])
            continue
        kind = field['type']
        if kind == 'checkbox':
            valid = type(value) is bool
        elif kind == 'multiselect':
            valid = isinstance(value, list) and len(value) <= 50 and all(v in [o['value'] for o in field['options']] for v in value)
        elif kind == 'tagger':
            valid = isinstance(value, str) and value in [o['value'] for o in field['options']]
        else:
            valid = isinstance(value, str) and len(value) <= 10000
            if valid and kind in ('integer', 'decimal'):
                valid = bool(re.fullmatch(r'-?\d+' if kind == 'integer' else r'-?\d+(?:\.\d+)?', value))
            if valid and kind == 'date':
                try:
                    valid = datetime.strptime(value, '%Y-%m-%d').strftime('%Y-%m-%d') == value
                except ValueError:
                    valid = False
        if not valid:
            raise ValueError('Revise o campo adicional: ' + field['name'])
        custom_fields.append({'id': field['id'], 'value': value})
    ticket['custom_fields'] = custom_fields
    email = data.get('assigneeEmail', '')
    if email:
        if not isinstance(email, str) or len(email) > 254 or not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', email):
            raise ValueError('Informe o e-mail do responsável no Zendesk.')
        ticket['assignee_email'] = email
    return ticket


def attachments(data):
    items = data.get('attachments') or []
    if not isinstance(items, list) or len(items) > 5:
        raise ValueError('Selecione até cinco anexos.')
    result, total = [], 0
    for item in items:
        if not isinstance(item, dict):
            raise ValueError('Anexo inválido.')
        name = text(item.get('name'), 'Nome do anexo', 150)
        if '/' in name or '\\' in name or any(ord(c) < 32 for c in name):
            raise ValueError('Nome de anexo inválido.')
        try:
            raw = base64.b64decode(item.get('base64', ''), validate=True)
        except Exception:
            raise ValueError('Não foi possível ler um anexo.') from None
        total += len(raw)
        if not raw or total > MAX_ATTACHMENT_BYTES:
            raise ValueError('Use anexos com tamanho total de até 8 MB.')
        result.append((name, raw))
    return result


def create_ticket(context, root, data):
    if data.get('confirmed') is not True:
        raise ValueError('Confira e confirme a criação do chamado.')
    folder, capture, image = load_capture(root, data)
    receipt_path = folder / 'receipt.json'
    if receipt_path.exists():
        receipt = json.loads(receipt_path.read_text(encoding='utf-8'))
        if receipt.get('state') == 'confirmed':
            return receipt
        if receipt.get('state') != 'rejected':
            raise ValueError('O envio anterior não foi confirmado. Confira o Zendesk antes de criar outro chamado. Não repetimos o envio.')
    user = current_agent(context)
    if type(data.get('agentId')) is not int or user['id'] != data['agentId']:
        raise ValueError('A conta do Zendesk mudou. Conecte e confira os dados novamente.')
    meta = metadata(context, user)
    ticket = validated_ticket(data, meta)
    files = attachments(data)
    csrf = user.get('authenticity_token')
    if not isinstance(csrf, str) or not csrf:
        raise ValueError('A sessão do Zendesk não forneceu o token de confirmação. Conecte novamente.')
    from urllib.parse import quote
    tokens = []
    image_url = None
    for name, content in [('priorizacao-oficial.png', image), *files]:
        uploaded = api(context, '/api/v2/uploads.json?filename=' + quote(name, safe=''), method='POST', data=content, csrf=csrf,
                       content_type=mimetypes.guess_type(name)[0] or 'application/octet-stream').get('upload') or {}
        if not uploaded.get('token'):
            raise ValueError('O Zendesk não confirmou um anexo. Nenhum ticket foi criado.')
        tokens.append(uploaded['token'])
        if image_url is None:
            image_url = (uploaded.get('attachment') or {}).get('content_url')
    if not isinstance(image_url, str) or not image_url.startswith('https://'):
        raise ValueError('O Zendesk não confirmou o endereço da imagem. Nenhum ticket foi criado.')
    marker = 'gh-' + root.name[:16] + '-' + capture['draftId']
    ticket.update(external_id=marker, comment={'html_body': compose(data['description'], capture, image_url), 'public': False, 'uploads': tokens})
    write_json(receipt_path, {'state': 'sending', 'externalId': marker})
    posted = False
    try:
        created = api(context, '/api/v2/tickets.json', method='POST', payload={'ticket': ticket}, csrf=csrf).get('ticket') or {}
        posted = True
        ticket_id = created.get('id')
        if type(ticket_id) is not int or ticket_id <= 0:
            raise ValueError('O número do ticket não foi confirmado.')
        verified = api(context, f'/api/v2/tickets/{ticket_id}.json').get('ticket') or {}
        if verified.get('id') != ticket_id or verified.get('external_id') != marker:
            raise ValueError('O chamado não pôde ser conferido após a criação.')
        receipt = {'state': 'confirmed', 'ticketId': ticket_id, 'url': ZENDESK + f'/agent/tickets/{ticket_id}',
                   'priority': capture['priority'], 'draftId': capture['draftId'], 'slaRegistered': False,
                   'message': 'Chamado criado e conferido no Zendesk. A priorização ainda não foi registrada na ferramenta SLA.'}
        write_json(receipt_path, receipt)
        return receipt
    except Exception as error:
        if isinstance(error, ZendeskRejected) and not posted:
            write_json(receipt_path, {'state': 'rejected', 'message': str(error)})
            raise
        write_json(receipt_path, {'state': 'uncertain', 'externalId': marker, 'draftId': capture['draftId']})
        raise ValueError('O envio não pôde ser confirmado. Confira o Zendesk; este rascunho não será reenviado automaticamente.') from None


def register_sla(playwright, root, data):
    if data.get('confirmed') is not True:
        raise ValueError('Confirme o registro da priorização na ferramenta oficial.')
    folder, captured, _ = load_capture(root, data)
    receipt_path = folder / 'receipt.json'
    receipt = json.loads(receipt_path.read_text(encoding='utf-8')) if receipt_path.exists() else {}
    if receipt.get('state') != 'confirmed':
        raise ValueError('É necessário um chamado Zendesk criado e conferido antes de registrar a priorização.')
    if receipt.get('slaRegistered'):
        return receipt
    if receipt.get('slaAttempted'):
        raise ValueError('Confira o registro na ferramenta oficial antes de repetir. A tentativa anterior não foi confirmada.')
    browser = playwright.chromium.launch(headless=False)
    try:
        page = browser.new_page(viewport={'width':1440, 'height':1000})
        actual = capture_on_page(page, captured, receipt['ticketId'])
        if actual['priority'] != captured['priority'] or actual['points'] != captured['points']:
            raise ValueError('As regras da ferramenta SLA mudaram. Confira a prioridade antes de registrar.')
        receipt['slaAttempted'] = True
        write_json(receipt_path, receipt)
        page.get_by_role('button', name='Salvar Respostas', exact=True).click()
        page.wait_for_function("id=>{const e=document.querySelector('#mensagemOk');return e && e.getClientRects().length && e.textContent.includes(String(id))}", arg=receipt['ticketId'], timeout=30000)
        receipt.update(slaRegistered=True, message='Prioridade registrada na ferramenta oficial com o número do chamado Zendesk.')
        write_json(receipt_path, receipt)
        return receipt
    finally:
        browser.close()


def execute(owner, action, data):
    if not isinstance(data, dict):
        raise ValueError('Dados inválidos para o Zendesk.')
    root = owner_root(owner)
    if action == 'receipt':
        folder = draft_path(root, data.get('draftId'))
        path = folder / 'receipt.json'
        result = json.loads(path.read_text(encoding='utf-8')) if path.exists() else {'state': 'prepared'}
        return {**result, 'state': 'prepared'} if result.get('state') == 'rejected' else result
    from playwright.sync_api import sync_playwright
    with sync_playwright() as playwright:
        if action == 'capture':
            return capture(playwright, root, data)
        if action == 'register-sla':
            return register_sla(playwright, root, data)
        if action not in {'connect', 'create'}:
            raise ValueError('Ação do Zendesk não reconhecida.')
        profile = root / 'browser'
        context = playwright.chromium.launch_persistent_context(str(profile), headless=False, viewport={'width':1400,'height':950})
        try:
            if action == 'connect':
                return metadata(context, login(context))
            return create_ticket(context, root, data)
        finally:
            context.close()


if __name__ == '__main__':
    try:
        payload = json.loads(sys.stdin.read())
        print(json.dumps({'ok': True, **execute(payload['owner'], payload['action'], payload['data'])}, ensure_ascii=True))
    except ValueError as error:
        print(json.dumps({'ok': False, 'message': str(error)}, ensure_ascii=True))
    except Exception:
        print(json.dumps({'ok': False, 'message': 'Não foi possível concluir a operação. Confira o navegador, a conexão e a instalação da integração local.'}, ensure_ascii=True))
