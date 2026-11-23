import sys
import unittest
from pathlib import Path
from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'edesk_bot'))
from edesk_recebidos import read_inbox


class ReceivedGridParserTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.playwright = sync_playwright().start()
        cls.browser = cls.playwright.chromium.launch()

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.playwright.stop()

    def setUp(self):
        self.page = self.browser.new_page()

    def tearDown(self):
        self.page.close()

    def test_grouped_header_is_not_mistaken_for_the_column_header(self):
        self.page.set_content('''<table id="ctl00_cph1_hgrSol_ctl00">
          <tr><th colspan="3">Meus trabalhos</th></tr>
          <tr><th>Solicitação / Trab.</th><th>Tipo de Trabalho</th><th>Solicitante</th></tr>
          <tr class="rgRow"><td>2266963 / 3</td><td>Implantação Plugin</td><td>Cliente</td></tr></table>''')
        result = read_inbox(self.page)
        self.assertTrue(result['complete'], result)
        self.assertEqual(result['rows'][0]['idTrabalho'], '3')
        self.assertEqual(result['rows'][0]['client'], 'Cliente')

    def test_static_header_outside_body_and_reference_inside_anchor(self):
        self.page.set_content('''<div class="RadGrid"><div class="rgHeaderDiv"><table>
          <tr><th>Solicitação/Trabalho</th><th>Cliente</th></tr></table></div>
          <table id="ctl00_cph1_hgrSol_ctl00"><tr class="rgRow"><td><a>2266963/3</a> Abrir</td><td>Cliente</td></tr></table></div>''')
        result = read_inbox(self.page)
        self.assertTrue(result['complete'], result)
        self.assertEqual(result['rows'][0]['solicitacao'], '2266963')

    def test_explicit_column_metadata_is_used_when_labels_are_icons(self):
        self.page.set_content('''<table id="ctl00_cph1_hgrSol_ctl00">
          <tr><th data-field="SolNumero">#</th><th data-field="TraNumero">#</th></tr>
          <tr><td>2266963</td><td>3</td></tr></table>''')
        result = read_inbox(self.page)
        self.assertTrue(result['complete'], result)
        self.assertEqual(result['rows'][0]['idTrabalho'], '3')

    def test_unknown_numeric_column_is_never_assumed_to_be_request(self):
        self.page.set_content('''<table id="ctl00_cph1_hgrSol_ctl00"><tr><th>Ordem</th></tr><tr><td>2266963</td></tr></table>''')
        result = read_inbox(self.page)
        self.assertFalse(result['complete'])
        self.assertEqual(result['rows'], [])
        self.assertEqual(result['headers'], ['Ordem'])

    def test_sol_abbreviation_and_department_grouping_from_user_screenshot(self):
        self.page.set_content('''<table id="ctl00_cph1_hgrSol_ctl00">
          <tr><th colspan="3">Departamento</th></tr>
          <tr><th></th><th>Sol.</th><th>Departamento</th></tr>
          <tr class="rgGroupHeader"><td colspan="3">Departamento A</td></tr>
          <tr class="rgRow"><td></td><td>2261345</td><td>Cliente A</td></tr>
          <tr class="rgAltRow"><td></td><td>2246969</td><td>Cliente B</td></tr></table>''')
        result = read_inbox(self.page)
        self.assertTrue(result['complete'], result)
        self.assertEqual(result['referenceLevel'], 'request')
        self.assertEqual([r['solicitacao'] for r in result['rows']], ['2261345', '2246969'])
        self.assertEqual(result['rows'][0]['client'], 'Cliente A')

    def test_three_visible_rows_do_not_omit_three_rows_in_a_collapsed_department(self):
        self.page.set_content('''<div class="RadGrid"><table id="ctl00_cph1_hgrSol_ctl00">
          <tr><th></th><th>Sol.</th></tr>
          <tr class="rgGroupHeader"><td colspan="2">Departamento A</td></tr>
          <tr class="rgRow"><td></td><td>2261001</td></tr>
          <tr class="rgAltRow"><td></td><td>2261002</td></tr>
          <tr class="rgRow"><td></td><td>2261003</td></tr>
          <tr class="rgGroupHeader"><td colspan="2"><input type="button" class="rgExpand" onclick="
            this.className='rgCollapse';document.querySelectorAll('.hidden-record').forEach(r=>r.style.display='');">Departamento B</td></tr>
          <tr class="rgAltRow hidden-record" style="display:none"><td></td><td>2261004</td></tr>
          <tr class="rgRow hidden-record" style="display:none"><td></td><td>2261005</td></tr>
          <tr class="rgAltRow hidden-record" style="display:none"><td></td><td>2261006</td></tr>
          </table></div>''')
        result = read_inbox(self.page)
        self.assertTrue(result['complete'], result)
        self.assertEqual(len(result['rows']), 6)
        self.assertEqual(result['rowsRead'], 6)

    def test_api_expands_department_and_loads_its_rows_before_reading(self):
        self.page.set_content('''<div class="RadGrid" id="personalGrid"><table id="ctl00_cph1_hgrSol_ctl00">
          <tr><th>Sol.</th></tr><tr class="rgGroupHeader" aria-expanded="false"><td>Departamento A</td></tr>
          </table></div><script>
          window.$find=()=>({get_masterTableView:()=>({expandGroup:(row,options)=>{
            setTimeout(()=>{row.setAttribute('aria-expanded','true');
              row.insertAdjacentHTML('afterend','<tr class="rgRow"><td>2261004</td></tr>')},150);
          }})});</script>''')
        result = read_inbox(self.page)
        self.assertTrue(result['complete'], result)
        self.assertEqual(result['rows'][0]['solicitacao'], '2261004')

    def test_unreadable_collapsed_department_never_reports_complete(self):
        self.page.set_content('''<table id="ctl00_cph1_hgrSol_ctl00"><tr><th>Sol.</th></tr>
          <tr class="rgRow"><td>2261001</td></tr>
          <tr class="rgGroupHeader" aria-expanded="false"><td>Departamento B</td></tr></table>''')
        result = read_inbox(self.page)
        self.assertFalse(result['complete'])
        self.assertIn('grupos', result['reason'])

    def test_grid_page_count_is_followed_even_without_visual_next_button(self):
        self.page.set_content('''<div class="RadGrid" id="personalGrid"><table id="ctl00_cph1_hgrSol_ctl00">
          <tr><th>Sol.</th></tr><tr class="rgRow"><td>2261001</td></tr></table></div>
          <script>let current=0;const view={get_currentPageIndex:()=>current,get_pageCount:()=>3,
            get_virtualItemCount:()=>3,page:command=>{current=command==='First'?0:current+1;
              document.querySelector('.rgRow td').textContent=String(2261001+current)}};
          window.$find=()=>({get_masterTableView:()=>view});</script>''')
        result = read_inbox(self.page)
        self.assertTrue(result['complete'], result)
        self.assertEqual(len(result['rows']), 3)
        self.assertEqual(result['pagesRead'], 3)
        self.assertEqual(result['expectedPages'], 3)

    def test_all_21_requests_across_two_pages_and_collapsed_departments_starting_on_page_two(self):
        self.page.set_content('''<div class="RadGrid" id="personalGrid"></div><script>
          let current=1;window.commands=[];
          function render(){
            const counts=current===0?[3,5]:[6,7];let number=current===0?2261001:2261009;
            let html='<table id="ctl00_cph1_hgrSol_ctl00"><tr><th></th><th>Sol.</th></tr>';
            for(let group=0;group<counts.length;group++){
              html+='<tr class="rgGroupHeader" aria-expanded="false" data-group="'+group+'"><td colspan="2"><input type="button" class="rgExpand">Departamento '+group+'</td></tr>';
              for(let i=0;i<counts[group];i++)html+='<tr class="rgRow" style="display:none" data-members="'+group+'"><td></td><td>'+(number++)+'</td></tr>';
            }
            document.getElementById('personalGrid').innerHTML=html+'</table>';
          }
          const view={get_currentPageIndex:()=>current,get_pageCount:()=>2,get_virtualItemCount:()=>21,
            page:command=>{window.commands.push(command);current=command==='First'?0:current+1;render()},
            expandGroup:row=>{const group=row.dataset.group;row.setAttribute('aria-expanded','true');
              row.querySelector('input').className='rgCollapse';
              document.querySelectorAll('[data-members="'+group+'"]').forEach(r=>r.style.display='');}};
          window.$find=()=>({get_masterTableView:()=>view});render();
          </script>''')
        result = read_inbox(self.page)
        self.assertTrue(result['complete'], result)
        self.assertEqual([r['solicitacao'] for r in result['rows']], [str(n) for n in range(2261001, 2261022)])
        self.assertEqual(result['rowsRead'], 21)
        self.assertEqual(result['expectedRows'], 21)
        self.assertEqual(result['pagesRead'], 2)
        self.assertEqual(result['expectedPages'], 2)
        self.assertEqual(self.page.evaluate('window.commands'), ['First', 'Next'])

    def test_known_larger_total_cannot_be_reported_as_complete(self):
        self.page.set_content('''<div class="RadGrid" id="personalGrid"><table id="ctl00_cph1_hgrSol_ctl00">
          <tr><th>Sol.</th></tr><tr class="rgRow"><td>2261001</td></tr></table></div>
          <script>window.$find=()=>({get_masterTableView:()=>({get_currentPageIndex:()=>0,
            get_pageCount:()=>1,get_virtualItemCount:()=>8})});</script>''')
        result = read_inbox(self.page)
        self.assertFalse(result['complete'])
        self.assertEqual(result['rowsRead'], 1)
        self.assertEqual(result['expectedRows'], 8)

    def test_ambiguous_column_mapping_is_rejected(self):
        self.page.set_content('''<table id="ctl00_cph1_hgrSol_ctl00"><tr><th>Solicitação</th><th>Trabalho</th></tr>
          <tr><th>Trabalho</th><th>Solicitação</th></tr><tr><td>2266963</td><td>3</td></tr></table>''')
        result = read_inbox(self.page)
        self.assertFalse(result['complete'])
        self.assertEqual(result['rows'], [])

    def test_request_only_grid_is_complete_when_all_request_pages_are_read(self):
        calls = []
        def fixture(route):
            self.assertEqual(route.request.method, 'GET')
            second = 'page=2' in route.request.url
            calls.append(2 if second else 1)
            pager = '<a href="/grid?page=1" onclick="/* Page$1 */">1</a><span>2</span>' if second else '<span>1</span><a href="/grid?page=2" onclick="/* Page$2 */">2</a>'
            route.fulfill(content_type='text/html; charset=utf-8', body=f'''<div class="RadGrid"><table id="ctl00_cph1_hgrSol_ctl00">
              <tr><th>Solicitação</th></tr><tr><td>{'2266964' if second else '2266963'}</td></tr>
              <tr class="rgPager"><td>{pager}</td></tr></table></div>''')
        self.page.route('**/*', fixture)
        self.page.goto('https://fixture.invalid/grid?page=1')
        result = read_inbox(self.page)
        self.assertTrue(result['complete'], result)
        self.assertEqual(result['referenceLevel'], 'request')
        self.assertEqual(len(result['rows']), 2)
        self.assertEqual(calls, [1, 2])

    def test_delayed_ajax_pagination_waits_for_the_new_records(self):
        self.page.set_content('''<div class="RadGrid"><table id="ctl00_cph1_hgrSol_ctl00">
          <tr><th>Solicitação/Trabalho</th></tr><tr class="rgRow"><td>2266963/3</td></tr>
          <tr class="rgPager"><td><span>1</span><a href="#" onclick="/* Page$2 */ event.preventDefault();
            setTimeout(()=>{document.querySelector('.rgRow td').textContent='2266963/4';
              document.querySelector('.rgPager td').innerHTML='<span>2</span>';},450)">2</a></td></tr></table></div>''')
        result = read_inbox(self.page)
        self.assertTrue(result['complete'], result)
        self.assertEqual([r['idTrabalho'] for r in result['rows']], ['3', '4'])

    def test_telerik_column_names_are_read_without_guessing_numeric_positions(self):
        self.page.set_content('''<div class="RadGrid" id="personalGrid"><table id="ctl00_cph1_hgrSol_ctl00">
          <tr class="rgRow"><td>2266963</td><td>3</td></tr></table></div>
          <script>window.$find=()=>({get_masterTableView:()=>({get_columns:()=>[
            {get_uniqueName:()=> 'SolNumero'}, {get_uniqueName:()=> 'TraNumero'}]})})</script>''')
        result = read_inbox(self.page)
        self.assertTrue(result['complete'], result)
        self.assertEqual(result['rows'][0]['idTrabalho'], '3')


if __name__ == '__main__':
    unittest.main()
