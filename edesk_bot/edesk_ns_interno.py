"""Create one reviewed internal NS request through SolicitacaoRapida."""
import hashlib
import json
import re
import sys
import time
from pathlib import Path
from urllib.parse import urlsplit, urlencode

if str(Path(__file__).resolve().parents[1]) not in sys.path:
    sys.path.append(str(Path(__file__).resolve().parents[1]))

GROUP = 'Sales OPS'
SERVICE = 'Serviços Internos'
PROCESS = 'Uso Interno - Novo NS'
OPERATION = 'ns-interno'


def validate_request(data):
    if not isinstance(data, dict) or data.get('confirmed') is not True:
        raise ValueError('Revise e confirme a solicitação de NS para uso interno.')
    if not isinstance(data.get('operationId'), str) or not re.fullmatch(r'[0-9a-f]{32}', data['operationId']):
        raise ValueError('Identificador da tentativa inválido. Abra o formulário novamente.')
    for field, limit in [('subject', 200), ('description', 10000)]:
        if not isinstance(data.get(field), str) or not data[field].strip() or len(data[field]) > limit:
            raise ValueError('Preencha assunto e detalhamento dentro dos limites informados.')


def fingerprint(data):
    return hashlib.sha256(json.dumps([GROUP, SERVICE, PROCESS, data['subject'].strip(),
        data['description'].strip()], ensure_ascii=False).encode()).hexdigest()


class NsLedger:
    def __init__(self, uid):
        self.uid = uid

    def connection(self):
        from local_edesk.journal import database
        return database()

    def table(self, con):
        con.execute('CREATE TABLE IF NOT EXISTS internal_ns (uid TEXT, operation TEXT, digest TEXT, '
                    'state TEXT, request_id TEXT, PRIMARY KEY(uid,operation))')

    def lookup(self, operation, digest):
        with self.connection() as con:
            self.table(con)
            row = con.execute('SELECT digest,state,request_id FROM internal_ns WHERE uid=? AND operation=?',
                (self.uid, operation)).fetchone()
        if row is None:
            return None
        if row[0] != digest:
            raise ValueError('O conteúdo desta tentativa mudou. Nada foi repetido.')
        if row[1] != 'confirmed':
            raise RuntimeError('Esta tentativa já chegou à etapa de salvar. Confira a solicitação no E-Desk antes de repetir; nenhum novo cadastro foi feito nesta tentativa.')
        return row[2]

    def claim(self, operation, digest):
        with self.connection() as con:
            self.table(con)
            cursor = con.execute('INSERT OR IGNORE INTO internal_ns VALUES(?,?,?,?,?)',
                (self.uid, operation, digest, 'attempted', None))
            return cursor.rowcount == 1

    def confirm(self, operation, digest, number):
        with self.connection() as con:
            self.table(con)
            con.execute('UPDATE internal_ns SET state="confirmed",request_id=? WHERE uid=? AND operation=? AND digest=? AND state="attempted"',
                (number, self.uid, operation, digest))


def trusted(page):
    parsed = urlsplit(page.url)
    if parsed.scheme != 'https' or parsed.hostname != 'promob.e-desk.com.br' or parsed.port not in (None, 443):
        raise RuntimeError('A tela não pertence ao E-Desk autorizado. Nada foi salvo.')


def receipt(number, repeated=False):
    return {'ok': True, 'operation': OPERATION, 'requestId': number, 'alreadyExists': repeated,
        'message': f'Solicitação {number} de NS para uso interno confirmada no E-Desk.'}


def read_created_number(context, original, previous_pages, excluded=frozenset()):
    candidates = [p for p in context.pages if not p.is_closed() and (p == original or p not in previous_pages)]
    found = set()
    for page in candidates:
        if page.url in ('', 'about:blank'):
            continue
        trusted(page)
        path = urlsplit(page.url).path.lower()
        if path.endswith('/solicitacao.aspx'):
            text = page.locator('body').inner_text()
            numbers = re.findall(r'Solicita[çc][ãa]o\s*[:#-]?\s*(\d{5,12})\b', text, re.I)
            found.update(numbers)
        elif path.endswith('/solicitacaorapida.aspx'):
            for notice in page.locator('.alert-success,[id*="lblMensagem"],[id*="lblMsg"]').all():
                if notice.is_visible():
                    found.update(re.findall(r'Solicita[çc][ãa]o\s*[:#-]?\s*(\d{5,12})\b', notice.inner_text(), re.I))
    found.difference_update(excluded)
    if len(found) > 1:
        raise RuntimeError('A tela retornou mais de um número. Confira o E-Desk antes de repetir.')
    return next(iter(found), None)


def create_request(page, data, ledger, *, confirmation_timeout=30):
    from edesk_adv import choose_lookup, control
    validate_request(data)
    trusted(page)
    digest = fingerprint(data)
    prior = ledger.lookup(data['operationId'], digest)
    if prior:
        return receipt(prior, True)
    if not urlsplit(page.url).path.lower().endswith('/solicitacaorapida.aspx'):
        raise RuntimeError('Abra a tela Solicitação Rápida do E-Desk. Nada foi salvo.')
    for label, value in [('Grupo de Serviço', GROUP), ('Serviço', SERVICE), ('Processo', PROCESS)]:
        choose_lookup(page, label, value)
    # The video leaves classification and the attachment option empty.
    classification = control(page, 'Classificação')
    current = classification.evaluate('(e)=>e.tagName==="SELECT"?e.selectedOptions[0]?.textContent:e.value')
    if (current or '').strip():
        raise RuntimeError('A classificação está preenchida e não corresponde ao fluxo revisado. Nada foi salvo.')
    attach = page.get_by_role('checkbox', name=re.compile(r'Quero anexar um arquivo', re.I))
    if attach.count() == 0 and 'Quero anexar um arquivo ao gravar esta solicitação' in page.locator('body').inner_text():
        attach = page.locator('input[type="checkbox"]:visible')
    if attach.count() != 1 or attach.is_checked():
        raise RuntimeError('A opção de anexar arquivo não corresponde ao fluxo revisado. Nada foi salvo.')
    control(page, 'Assunto').fill(data['subject'].strip())
    control(page, 'Detalhamento').fill(data['description'].strip())
    trusted(page)
    if not urlsplit(page.url).path.lower().endswith('/solicitacaorapida.aspx'):
        raise RuntimeError('A tela mudou antes de salvar. Nada foi salvo.')
    for label, expected in [('Grupo de Serviço', GROUP), ('Serviço', SERVICE), ('Processo', PROCESS),
                            ('Assunto', data['subject'].strip()), ('Detalhamento', data['description'].strip())]:
        value = control(page, label).evaluate('(e)=>e.tagName==="SELECT"?e.selectedOptions[0]?.textContent:e.value')
        if (value or '').strip() != expected:
            raise RuntimeError('O formulário mudou após a revisão. Nada foi salvo.')
    classification = control(page, 'Classificação')
    if (classification.evaluate('(e)=>e.tagName==="SELECT"?e.selectedOptions[0]?.textContent:e.value') or '').strip() or attach.is_checked():
        raise RuntimeError('Classificação ou anexos mudaram após a revisão. Nada foi salvo.')
    save = page.get_by_role('button', name=re.compile(r'^Salvar$', re.I))
    if save.count() != 1 or not save.is_enabled():
        raise RuntimeError('O botão Salvar não foi reconhecido. Nada foi salvo.')
    previous_pages = set(page.context.pages)
    previous_number = read_created_number(page.context, page, previous_pages)
    previous_numbers = {previous_number} if previous_number else set()
    if not ledger.claim(data['operationId'], digest):
        return receipt(ledger.lookup(data['operationId'], digest), True)
    # Reserve durably before exactly one click. A timeout cannot cause retry.
    try:
        with page.expect_response(lambda r: r.request.method == 'POST' and
                urlsplit(r.url).path.lower().endswith('/solicitacaorapida.aspx'), timeout=30000) as pending:
            save.click(timeout=15000)
        response = pending.value
        if response.status >= 400:
            raise RuntimeError('O E-Desk recusou a tentativa de salvar. Confira antes de repetir.')
    except Exception:
        # A redirect or popup can interrupt the click wait. Confirm by the
        # visible new request number; never click Save again.
        pass
    deadline = time.monotonic() + confirmation_timeout
    while time.monotonic() < deadline:
        number = read_created_number(page.context, page, previous_pages, previous_numbers)
        if number:
            ledger.confirm(data['operationId'], digest, number)
            return receipt(number)
        remaining = next((p for p in page.context.pages if not p.is_closed()), None)
        if remaining is None:
            break
        remaining.wait_for_timeout(200)
    raise RuntimeError('O número da nova solicitação não foi confirmado. Confira no E-Desk antes de repetir. Esta tentativa não será reenviada automaticamente.')


def main():
    from edesk_comentario import (carregar_request, obter_credenciais_edesk, obter_url,
        aguardar_login, obter_guid_da_url)
    from config import PROFILE_DIR, HEADLESS, restore_session_cookies, save_session_cookies
    from playwright.sync_api import sync_playwright
    import os
    data = carregar_request()
    validate_request(data)
    if data.get('enviar') is not True:
        raise ValueError('A criação exige confirmação.')
    uid = os.environ.get('EDESK_AUTH_UID', '')
    if not uid:
        raise ValueError('A conta autenticada da integração não foi identificada.')
    ledger = NsLedger(uid)
    prior = ledger.lookup(data['operationId'], fingerprint(data))
    if prior:
        print(json.dumps(receipt(prior, True), ensure_ascii=False), flush=True)
        return
    with sync_playwright() as p:
        context = p.chromium.launch_persistent_context(str(PROFILE_DIR), headless=HEADLESS, viewport=None)
        try:
            restore_session_cookies(context)
            page = context.pages[0] if context.pages else context.new_page()
            page.goto(obter_url(data), wait_until='domcontentloaded', timeout=60000)
            aguardar_login(page, credenciais=obter_credenciais_edesk(data))
            save_session_cookies(context)
            guid = obter_guid_da_url(page.url)
            if not guid:
                raise RuntimeError('Não foi possível identificar a sessão do E-Desk.')
            page.goto('https://promob.e-desk.com.br/Portal/SolicitacaoRapida.aspx?'+urlencode({'GUID': guid}),
                wait_until='domcontentloaded', timeout=30000)
            result = create_request(page, data, ledger)
            print(json.dumps(result, ensure_ascii=False), flush=True)
        finally:
            context.close()


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(json.dumps({'ok': False, 'operation': OPERATION, 'message': str(error)}, ensure_ascii=False), flush=True)
        sys.exit(1)
