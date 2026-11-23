import json
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch, MagicMock
from contextlib import redirect_stdout
import io

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'edesk_bot'))
from edesk_adv import validate_adv_request, create_work, save_and_confirm_work


class AdvWorkTest(unittest.TestCase):
    def test_attendant_filter_clear_variants_and_fail_closed(self):
        from edesk_adv import existing_work
        from playwright.sync_api import sync_playwright
        os.environ['PLAYWRIGHT_BROWSERS_PATH'] = str(ROOT / 'python/ms-playwright')
        with sync_playwright() as driver:
            browser = driver.chromium.launch(headless=True)
            try:
                page = browser.new_page()
                cases = [
                    '<input id="att" value="Rodrigo">',
                    '<input id="att" value="Rodrigo" readonly><img title="Erase" onclick="att.value=\'\'">',
                    '<input id="att" value="Rodrigo" readonly><a href="#" onclick="att.value=\'\';return false"><img alt="Limpar"></a>',
                ]
                for field in cases:
                    with self.subTest(field=field):
                        page.set_content('<select><option>Todas as situações</option></select>'
                            '<table><tr><td>Atendente</td><td>' + field + '</td></tr></table>'
                            '<button onclick="window.searched=true">Localizar</button>'
                            '<table id="cph1_gvwTra"><tr><th>Tipo de Trabalho</th>'
                            '<th>Equipe de Trabalho</th><th>Assunto</th></tr></table>')
                        with patch('edesk_conferencia.show_works'):
                            self.assertIsNone(existing_work(page, 'Finalizada'))
                        self.assertEqual(page.locator('#att').input_value(), '')
                        self.assertTrue(page.evaluate('window.searched'))
                page.set_content('<script>window.searched=null</script><select><option>Todas as situações</option></select>'
                    '<table><tr><td>Atendente</td><td><input id="att" value="Rodrigo" readonly>'
                    '<input type="hidden" value="123"></td></tr></table>'
                    '<button onclick="window.searched=true">Localizar</button>')
                with patch('edesk_conferencia.show_works'), self.assertRaises(RuntimeError):
                    existing_work(page, 'Finalizada')
                self.assertIsNone(page.evaluate('window.searched'))
            finally:
                browser.close()

    def test_startup_passes_required_url_and_request_to_work_creation(self):
        from edesk_adv import main
        data={'url':'https://promob.e-desk.com.br/','solicitacao':'2250455',
              'subject':'Implantação Finalizada','description':'Cobrança conforme comercialização.',
              'confirmed':True,'enviar':True,
              'edeskCredenciais':{'email':'fixture@example.test','senha':'test-only'}}
        page=MagicMock();context=MagicMock();context.pages=[page]
        with patch('playwright.sync_api.sync_playwright') as driver, \
             patch('edesk_comentario.carregar_request',return_value=data), \
             patch('edesk_comentario.aguardar_login'), patch('edesk_comentario.obter_guid_da_url',return_value='fixture'), \
             patch('edesk_comentario.acessar_minha_grid') as grid, \
             patch('edesk_comentario.localizar_solicitacao_validada',return_value=(page,None,True)), \
             patch('edesk_horas.abrir_trabalho',return_value=page), \
             patch('config.restore_session_cookies'),patch('config.save_session_cookies'), \
             patch('edesk_adv.create_work',return_value={'ok':True,'operation':'adv','workId':'12'}) as create, \
             redirect_stdout(io.StringIO()):
            driver.return_value.__enter__.return_value.chromium.launch_persistent_context.return_value=context
            self.assertEqual(main(),0)
        self.assertEqual(page.goto.call_args.args[0],'https://promob.e-desk.com.br/')
        grid.assert_called_once_with(page,'fixture')
        create.assert_called_once_with(page,data)
        context.close.assert_called_once()
    def test_requires_reviewed_numeric_request_and_nonempty_text(self):
        data = {'solicitacao': '2263800', 'subject': 'Implantação Finalizada',
                'description': 'Concluída.', 'confirmed': True}
        validate_adv_request(data)
        for change in [{'solicitacao': '../other'}, {'subject': ''}, {'description': ''}, {'confirmed': False}]:
            with self.assertRaises(ValueError):
                validate_adv_request({**data, **change})

    def test_saves_once_and_verifies_grid_then_prevents_duplicate(self):
        from playwright.sync_api import sync_playwright
        os.environ['PLAYWRIGHT_BROWSERS_PATH'] = str(ROOT / 'python/ms-playwright')
        with sync_playwright() as driver:
            browser = driver.chromium.launch(headless=True, executable_path=driver.chromium.executable_path)
            try:
                page = browser.new_page()
                saved = []
                base = 'https://promob.e-desk.com.br/Portal/'
                def route_handler(route):
                    request = route.request
                    if request.method == 'POST':
                        saved.append(json.loads(request.post_data))
                        route.fulfill(body='ok')
                    elif 'TrabalhoProximo.aspx' in request.url:
                        route.fulfill(content_type='text/html; charset=utf-8', body='''<div>Solicitação 2263800</div><table>
                          <tr><td>Grupo de Tipos de Trabalho</td><td><select id="g"><option>FLUXO DE IMPLANTAÇÃO PROMOB</option></select></td></tr>
                          <tr><td>Tipo de Trabalho</td><td><select id="t"><option>Programação</option></select></td></tr>
                          <tr><td>Equipe de Trabalho</td><td><select id="e"><option>Consultoria Promob</option><option>Go Live</option></select></td></tr>
                          <tr><td>Assunto do trabalho</td><td><input id="s"></td></tr>
                          <tr><td>Detalhamento do trabalho</td><td><textarea id="d"></textarea></td></tr></table>
                          <button onclick="document.querySelector('[role=dialog]').hidden=false">Salvar</button>
                          <div role="dialog" hidden><p>Confirma o cadastro?</p>
                          <button onclick="this.disabled=true;fetch(location.href,{method:'POST',body:JSON.stringify({subject:s.value,description:d.value,team:e.value})})">Sim</button>
                          <button>Não</button></div>''')
                    else:
                        extra = '''<tr><td><a onclick="/* btnSelTra */">12</a></td><td>Programação</td><td>Go Live</td><td>Implantação Finalizada</td></tr>''' if saved else ''
                        route.fulfill(content_type='text/html; charset=utf-8', body='''<div>Solicitação: 2263800 - Cliente</div>
                          <div class="rtsLevel1"><a class="rtsLink" onclick="void(0)">Trabalhos (2)</a></div>
                          <table><tr><td>Situação</td><td><select><option>Todas as situações</option></select></td>
                          <td>Atendente</td><td><input id="a"></td></tr></table><button>Localizar</button>
                          <a href="TrabalhoProximo.aspx?id=abc">Inserir</a>
                          <table id="cph1_gvwTra"><tr><th>ID</th><th>Tipo de Trabalho</th><th>Equipe de Trabalho</th><th>Assunto</th></tr>
                          <tr><td><a onclick="/* btnSelTra */">3</a></td><td>Implantação (OH)</td><td>Consultoria Promob</td><td>Implantação</td></tr>''' + extra + '</table>')
                page.route('**/*', route_handler)
                page.goto(base + 'Solicitacao.aspx?id=abc')
                data = {'solicitacao': '2263800', 'subject': 'Implantação Finalizada',
                        'description': 'Concluída.', 'confirmed': True}
                result = create_work(page, data)
                self.assertEqual(result['workId'], '12')
                self.assertFalse(result['alreadyExists'])
                self.assertEqual(saved, [{'subject': data['subject'], 'description': data['description'], 'team': 'Go Live'}])
                result = create_work(page, data)
                self.assertTrue(result['alreadyExists'])
                self.assertEqual(len(saved), 1)
                with self.assertRaisesRegex(RuntimeError, 'não pertence'):
                    create_work(page, {**data, 'solicitacao': '999'})
            finally:
                browser.close()

    def test_save_confirmation_native_missing_and_ambiguous(self):
        from playwright.sync_api import sync_playwright
        os.environ['PLAYWRIGHT_BROWSERS_PATH'] = str(ROOT / 'python/ms-playwright')
        with sync_playwright() as driver:
            browser = driver.chromium.launch(headless=True)
            try:
                page = browser.new_page()
                page.set_content('''<script>window.saves=0;window.accepted=0;</script>
                  <button onclick="saves++;if(confirm('Confirma o cadastro?'))accepted++">Salvar</button>''')
                save_and_confirm_work(page, page.get_by_role('button', name='Salvar'))
                self.assertEqual(page.evaluate('[saves,accepted]'), [1, 1])
                page.set_content('''<script>window.saves=0;</script><button onclick="saves++">Salvar</button>
                  <button onclick="throw Error('outside modal')">Sim</button>''')
                with self.assertRaisesRegex(RuntimeError, 'não apareceu'):
                    save_and_confirm_work(page, page.get_by_role('button', name='Salvar'), timeout=200)
                self.assertEqual(page.evaluate('saves'), 1)
                page.set_content('''<script>window.saves=0;</script><button onclick="saves++">Salvar</button>
                  <div role="dialog"><button>Sim</button><button>Sim</button></div>''')
                with self.assertRaisesRegex(RuntimeError, 'mais de uma'):
                    save_and_confirm_work(page, page.get_by_role('button', name='Salvar'), timeout=200)
                self.assertEqual(page.evaluate('saves'), 1)
            finally:
                browser.close()


if __name__ == '__main__':
    unittest.main()
