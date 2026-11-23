"""Create a reviewed Go Live work in the selected request; never repeat Save."""
import json
import re
import sys
import time

GROUP = 'FLUXO DE IMPLANTAÇÃO PROMOB'
WORK_TYPE = 'Programação'
TEAM = 'Go Live'


def validate_adv_request(data):
    if not isinstance(data, dict) or not re.fullmatch(r'\d{1,12}', str(data.get('solicitacao', ''))):
        raise ValueError('Informe uma solicitação válida para o trabalho ADV.')
    for field, limit in [('subject', 200), ('description', 10000)]:
        value = data.get(field)
        if not isinstance(value, str) or not value.strip() or len(value) > limit:
            raise ValueError('Preencha assunto e detalhamento dentro dos limites informados.')
    if data.get('confirmed') is not True:
        raise ValueError('Revise e confirme a criação do trabalho ADV.')


def request_identity(page, number):
    text = page.locator('body').inner_text()
    found = re.search(r'Solicita[çc][ãa]o\s*:?\s*(\d+)', text, re.I)
    if not found or found[1] != str(number):
        raise RuntimeError('A tela não pertence à solicitação selecionada. Nenhum trabalho foi salvo.')


def existing_work(page, subject):
    from edesk_conferencia import show_works
    show_works(page)
    # Duplicate checks must include completed work and other attendants.
    filters = [s for s in page.locator('select').all() if s.is_visible()
        and 'Todas as situações' in s.locator('option').all_text_contents()]
    if len(filters) != 1:
        raise RuntimeError('Não foi possível consultar todas as situações dos trabalhos. Nada foi salvo.')
    filters[0].select_option(label='Todas as situações')
    page.wait_for_function("() => document.readyState!=='loading'&&!window.Sys?.WebForms?.PageRequestManager?.getInstance?.()?.get_isInAsyncPostBack?.()")
    attendant = control(page, 'Atendente')
    if attendant.input_value().strip():
        erasers = [e for e in attendant.locator('xpath=ancestor::td[1]').locator('input[type=image],a,button,img').all()
            if e.is_visible() and re.search(r'limp|clear|borracha|delete|del|remove|eras|apagar|excluir',
                e.evaluate("e => [e,...e.querySelectorAll('img')].map(n => ['id','title','alt','src','onclick','href'].map(a => n.getAttribute(a)||'').join(' ')).join(' ')").lower())]
        # An image inside a link/button is one action, not two erasers.
        erasers = [e for e in erasers if not e.evaluate(
            "e => e.tagName === 'IMG' && !!e.closest('a,button')")]
        if not erasers and attendant.is_editable() and not attendant.locator(
                'xpath=ancestor::td[1]').locator('input[type=hidden]').count():
            attendant.fill('')
            attendant.press('Tab')
        elif len(erasers) == 1:
            erasers[0].click()
        else:
            raise RuntimeError('Não foi possível remover o filtro de atendente para conferir duplicidade. Nada foi salvo.')
        page.wait_for_function("() => document.readyState!=='loading'&&!window.Sys?.WebForms?.PageRequestManager?.getInstance?.()?.get_isInAsyncPostBack?.()")
        if control(page, 'Atendente').input_value().strip():
            raise RuntimeError('O filtro de atendente permaneceu ativo. Nada foi salvo.')
    locate = page.get_by_role('button', name=re.compile(r'^Localizar$', re.I))
    if locate.count() != 1:
        raise RuntimeError('O filtro de trabalhos não foi reconhecido. Nada foi salvo.')
    locate.click()
    page.wait_for_function("() => !window.Sys?.WebForms?.PageRequestManager?.getInstance?.()?.get_isInAsyncPostBack?.()")
    table = page.locator('#cph1_gvwTra')
    if table.locator('a[href*="Page$"],.rgPager').count():
        raise RuntimeError('A tabela de trabalhos está paginada. Confira a duplicidade no E-Desk antes de criar.')
    rows = table.evaluate(r'''table => {
      const norm=s=>(s||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]/g,'');
      const rows=[...table.rows].filter(r=>r.closest('table')===table&&r.getClientRects().length);
      const header=rows.find(r=>[...r.cells].some(c=>norm(c.innerText)==='tipodetrabalho'));
      if(!header)throw Error('Cabecalho de trabalhos ausente.');
      const labels=[...header.cells].map(c=>norm(c.innerText));
      const index=name=>{const positions=labels.map((x,i)=>x===name?i:-1).filter(i=>i>=0);if(positions.length!==1)throw Error('Coluna nao reconhecida: '+name);return positions[0]};
      const type=index('tipodetrabalho'),team=index('equipedetrabalho'),subject=index('assunto');
      return rows.flatMap(r=>{
        const ids=[...new Set([...r.querySelectorAll('[onclick*="btnSelTra"],a[href*="btnSelTra"]')].map(a=>a.innerText.trim()).filter(v=>/^\d+$/.test(v)))];
        if(!ids.length)return [];
        if(ids.length!==1)throw Error('ID de trabalho ambiguo.');
        return [{id:ids[0],type:r.cells[type]?.innerText.trim(),team:r.cells[team]?.innerText.trim(),subject:r.cells[subject]?.innerText.trim()}];
      });
    }''')
    matches = [r for r in rows if r['type'] == WORK_TYPE and r['team'] == TEAM and r['subject'] == subject]
    if len(matches) > 1:
        raise RuntimeError('Há mais de um trabalho ADV com esse assunto. Confira no E-Desk; nenhum cadastro foi repetido.')
    return matches[0]['id'] if matches else None


def field_id(page, label):
    result = page.evaluate(r'''label => {
      const norm=s=>(s||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z]/g,'');
      const visible=e=>e&&e.getClientRects().length&&getComputedStyle(e).visibility!=='hidden';
      const result=new Set();
      for(const e of document.querySelectorAll('label,td,span,b,strong')){
        if(!visible(e)||norm(e.textContent)!==norm(label))continue;
        let inputs=[];
        if(e.htmlFor)inputs=[document.getElementById(e.htmlFor)];
        if(!inputs.filter(visible).length){
          const cell=e.closest('td');
          if(cell)inputs=[...cell.querySelectorAll('input:not([type=hidden]):not([type=image]):not([type=button]),textarea,select')];
          if(!inputs.filter(visible).length&&cell?.nextElementSibling)inputs=[...cell.nextElementSibling.querySelectorAll('input:not([type=hidden]):not([type=image]):not([type=button]),textarea,select')];
          if(!inputs.filter(visible).length&&e.nextElementSibling?.matches('input,textarea,select'))inputs=[e.nextElementSibling];
        }
        for(const input of inputs.filter(visible))if(input.id)result.add(input.id);
      }
      return [...result];
    }''', label)
    if len(result) != 1:
        raise RuntimeError(f'Não foi possível identificar o campo {label} de forma única. Nada foi salvo.')
    return result[0]


def control(page, label):
    identifier = field_id(page, label)
    return page.locator('[id=' + json.dumps(identifier) + ']')


def choose_lookup(page, label, value):
    field = control(page, label)
    tag = field.evaluate('(e)=>e.tagName')
    if tag == 'SELECT':
        field.select_option(label=value)
    elif field.input_value().strip() != value:
        cell = field.locator('xpath=ancestor::td[1]')
        buttons = cell.locator('input[type=image],a,button')
        candidates = []
        for item in buttons.all():
            if not item.is_visible():
                continue
            signature = ' '.join(item.get_attribute(a) or '' for a in ['id', 'title', 'alt', 'src', 'onclick']).lower()
            if re.search(r'loc|pesq|busc|search|find|lupa', signature) and not re.search(r'limp|clear|borracha', signature):
                candidates.append(item)
        if len(candidates) != 1:
            raise RuntimeError(f'O seletor de {label} não foi reconhecido. Nada foi salvo.')
        before = set(page.context.pages)
        candidates[0].click(timeout=10000)
        selected = False
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline and not selected:
            for candidate in list(page.context.pages):
                if candidate != page and candidate in before:
                    continue
                for frame in candidate.frames:
                    links = [e for e in frame.get_by_text(value, exact=True).all() if e.is_visible()]
                    if len(links) == 1:
                        links[0].click(timeout=5000)
                        selected = True
                        break
                if selected:
                    break
            if not selected:
                page.wait_for_timeout(200)
        if not selected:
            raise RuntimeError(f'Não foi possível selecionar {value}. Nada foi salvo.')
    identifier = field_id(page, label)
    page.wait_for_function(r'''args => {
      const e=document.getElementById(args[0]);
      const value=e?.tagName==='SELECT'?e.selectedOptions[0]?.textContent:e?.value;
      return value?.trim()===args[1]&&!window.Sys?.WebForms?.PageRequestManager?.getInstance?.()?.get_isInAsyncPostBack?.();
    }''', arg=[identifier, value], timeout=15000)
    field = control(page, label)
    actual = field.evaluate('(e)=>e.tagName==="SELECT"?e.selectedOptions[0]?.textContent:e.value')
    if (actual or '').strip() != value:
        raise RuntimeError(f'O E-Desk não confirmou {label}: {value}. Nada foi salvo.')


def save_and_confirm_work(page, save, timeout=30000):
    """Save once, accept the ensuing confirmation once; never retry a write."""
    confirmed = False
    unexpected_dialog = False

    def handle_dialog(dialog):
        nonlocal confirmed, unexpected_dialog
        if dialog.type == 'confirm' and not confirmed:
            confirmed = True
            dialog.accept()
        else:
            unexpected_dialog = True
            dialog.dismiss()

    page.on('dialog', handle_dialog)
    try:
        # The confirmation may be a browser confirm or an E-Desk/Telerik modal.
        # Register the listener before Save so a synchronous confirm cannot block it.
        save.click(timeout=15000)
        deadline = time.monotonic() + timeout / 1000
        while time.monotonic() < deadline:
            if unexpected_dialog:
                raise RuntimeError('O E-Desk exibiu uma confirmação inesperada. Confira o cadastro antes de tentar novamente.')
            if confirmed:
                return
            choices = []
            for frame in page.frames:
                buttons = frame.locator('[role="dialog"], .rwWindowContent, .ui-dialog, .modal').get_by_role(
                    'button', name=re.compile(r'^Sim$', re.I))
                choices.extend(button for button in buttons.all() if button.is_visible() and button.is_enabled())
            if len(choices) > 1:
                raise RuntimeError('Há mais de uma confirmação Sim. Confira o E-Desk antes de tentar novamente.')
            if len(choices) == 1:
                with page.expect_response(lambda r: r.request.method == 'POST'
                        and '/Portal/TrabalhoProximo.aspx' in r.url, timeout=30000) as confirmation:
                    choices[0].click(timeout=15000)
                confirmation.value.body()
                return
            page.wait_for_timeout(100)
        raise RuntimeError('O modal de confirmação Sim não apareceu após Salvar. Confira o E-Desk antes de tentar novamente.')
    finally:
        page.remove_listener('dialog', handle_dialog)


def create_work(page, data):
    validate_adv_request(data)
    number, subject = str(data['solicitacao']), data['subject'].strip()
    request_identity(page, number)
    existing = existing_work(page, subject)
    if existing:
        return {'ok': True, 'operation': 'adv', 'workId': existing, 'alreadyExists': True,
                'message': f'O trabalho ADV {existing} já existe nesta solicitação. Nenhum cadastro foi repetido.'}
    request_url = page.url
    insert = page.get_by_role('button', name=re.compile(r'^Inserir$', re.I))
    if insert.count() != 1:
        insert = page.get_by_role('link', name=re.compile(r'^Inserir$', re.I))
    if insert.count() != 1:
        raise RuntimeError('O botão Inserir não foi identificado. Nada foi salvo.')
    insert.click(timeout=10000)
    page.wait_for_url('**/TrabalhoProximo.aspx*', timeout=15000)
    request_identity(page, number)
    for label, value in [('Grupo de Tipos de Trabalho', GROUP), ('Tipo de Trabalho', WORK_TYPE), ('Equipe de Trabalho', TEAM)]:
        choose_lookup(page, label, value)
    control(page, 'Assunto do trabalho').fill(subject)
    control(page, 'Detalhamento do trabalho').fill(data['description'].strip())
    # Re-read all reviewed fields after the lookup postbacks, before the one Save.
    request_identity(page, number)
    for label, value in [('Grupo de Tipos de Trabalho', GROUP), ('Tipo de Trabalho', WORK_TYPE), ('Equipe de Trabalho', TEAM)]:
        field = control(page, label)
        actual = field.evaluate('(e)=>e.tagName==="SELECT"?e.selectedOptions[0]?.textContent:e.value')
        if (actual or '').strip() != value:
            raise RuntimeError('Os dados do formulário mudaram. Nada foi salvo.')
    if control(page, 'Assunto do trabalho').input_value().strip() != subject or control(page, 'Detalhamento do trabalho').input_value().strip() != data['description'].strip():
        raise RuntimeError('O E-Desk não preservou o assunto e o detalhamento. Nada foi salvo.')
    save = page.get_by_role('button', name=re.compile(r'^Salvar$', re.I))
    if save.count() != 1:
        raise RuntimeError('O botão Salvar não foi reconhecido. Nada foi salvo.')
    try:
        with page.expect_response(lambda r: r.request.method == 'POST'
                and '/Portal/TrabalhoProximo.aspx' in r.url, timeout=45000) as saved:
            save_and_confirm_work(page, save)
        saved.value.body()
    except Exception as error:
        raise RuntimeError('Não foi possível confirmar Salvar e Sim. Confira o E-Desk antes de tentar novamente. ' + str(error)) from error
    page.goto(request_url, wait_until='domcontentloaded', timeout=30000)
    request_identity(page, number)
    work = existing_work(page, subject)
    if not work:
        raise RuntimeError('Não foi possível confirmar o cadastro. Confira o E-Desk antes de tentar novamente.')
    return {'ok': True, 'operation': 'adv', 'workId': work, 'alreadyExists': False,
            'message': f'Trabalho ADV {work} confirmado na solicitação {number}, equipe Go Live.'}


def main():
    from edesk_comentario import (carregar_request, obter_credenciais_edesk, obter_url,
        aguardar_login, obter_guid_da_url, acessar_minha_grid, localizar_solicitacao_validada)
    from edesk_horas import abrir_trabalho
    from edesk_conferencia import show_works
    from config import PROFILE_DIR, HEADLESS, restore_session_cookies, save_session_cookies
    from playwright.sync_api import sync_playwright
    data = carregar_request()
    validate_adv_request(data)
    if data.get('enviar') is not True:
        raise ValueError('A criação exige confirmação.')
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
                raise RuntimeError('Sessão do E-Desk não identificada.')
            acessar_minha_grid(page, guid)
            source, row, opened = localizar_solicitacao_validada(page, context, str(data['solicitacao']))
            selected = abrir_trabalho(source, context, row, str(data['solicitacao']), '',
                pagina_solicitacao_preaberta=opened, abrir_retroativo=False,
                somente_solicitacao=True, validar_solicitacao=show_works)
            result = create_work(selected, data)
        finally:
            context.close()
    print(json.dumps(result, ensure_ascii=False), flush=True)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        print(json.dumps({'ok': False, 'operation': 'adv', 'message': str(error)}, ensure_ascii=False), flush=True)
        sys.exit(1)
