"""Read the current user's Minha Grid; no work creation or updates in E-Desk."""
import json
import sys

GRID = r'''() => {
  const table=document.querySelector('#ctl00_cph1_hgrSol_ctl00');
  const visible=e=>e&&e.getClientRects().length&&getComputedStyle(e).visibility!=='hidden';
  const norm=s=>(s||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]/g,'');
  if(!visible(table))return {rows:[],complete:false,reason:'Tabela da Minha Grid nao identificada.'};
  const rows=[...table.rows].filter(r=>r.closest('table')===table);
  const scope=table.closest('.RadGrid')||table;
  const aliases={solicitacao:['solicitacao','solicitacoes','solicitacaon','solicitacaonumero','idsolicitacao','solcodigo','numerodasolicitacao','numerosolicitacao','nsolicitacao','nrosolicitacao','solicitacaotrabalho','solicitacaotrab','nsolicitacaotrabalho','nsolicitacaontrabalho','solnumero','numerosol','nrosol','numsol','nsol','sol'],
    idTrabalho:['trabalho','iddotrabalho','idtrabalho','numerodotrabalho','numerotrabalho','ntrabalho','ntrab','trab','nrotrabalho','tranumero'],
    client:['cliente','empresa','razaosocial','solicitante','departamento'],serviceType:['tipodeservico','servico','produto','tipo','tipodetrabalho'],
    leader:['lider','liderdoprojeto','liderprojeto'],hours:['horasprevistas','horasestimadas','tempoprevisto'],
    name:['atividade','descricaodotrabalho','nomedotrabalho','descricao'],status:['situacao','status']};
  const headers=[...new Set([...rows.filter(r=>r.querySelector('th')), ...scope.querySelectorAll('.rgHeaderDiv tr')])];
  const schema=names=>Object.fromEntries(Object.entries(aliases).map(([k,values])=>[k,names.findIndex(options=>options.some(n=>values.includes(n)))]));
  const candidates=headers.map(header=>({header, columns:schema([...header.cells].flatMap(c=>{
    const names=[c.textContent,c.getAttribute('data-field'),c.getAttribute('data-uniquename'),c.getAttribute('abbr')].filter(Boolean).map(norm);
    return Array.from({length:c.colSpan||1},()=>names);
  }))}));
  let view=null;
  // Telerik can render the header outside the body table when scrolling is enabled.
  try {
    const grid=window.$find?.(scope.id)||window.$find?.('ctl00_cph1_hgrSol');
    view=grid?.get_masterTableView?.();
    const cols=view?.get_columns?.();
    if(cols?.length)candidates.push({header:null,columns:schema(cols.map(c=>[c.get_uniqueName?.(),c.get_headerText?.()].filter(Boolean).map(norm)))});
  } catch (_) {}
  const valid=candidates.filter(c=>c.columns.solicitacao>=0);
  const mappings=new Set(valid.map(c=>c.columns.solicitacao));
  if(mappings.size!==1)return {rows:[],complete:false,reason:mappings.size?'Cabecalhos de solicitacao ambiguos.':'Coluna de solicitacao nao reconhecida.',headers:headers.map(r=>[...r.cells].map(c=>c.textContent.trim()).join(' | '))};
  valid.sort((a,b)=>Object.values(b.columns).filter(v=>v>=0).length-Object.values(a.columns).filter(v=>v>=0).length);
  const {columns}=valid[0];
  const result={rows:[],complete:true,index:1};
  let pagerUncertain=false;
  const pagers=[...scope.querySelectorAll('.rgPager,.pager'),...rows.filter(r=>r.querySelector('a[href*="Page$"]'))];
  const commands=[...new Set(pagers.flatMap(r=>[...r.querySelectorAll('a,button,input')]))].filter(visible).map(e=>{
    let arg=(((e.getAttribute('href')||'')+' '+(e.getAttribute('onclick')||'')).match(/Page\$(First|Next|Last|Previous|Prev|\d+)/i)||[])[1];
    if(arg&&!/^\d+$/.test(arg))arg=arg[0].toUpperCase()+arg.slice(1).toLowerCase();
    if(e.matches('.rgPageNext'))arg='Next';if(e.matches('.rgPageFirst'))arg='First';
    const disabled=e.disabled||e.getAttribute('aria-disabled')==='true'||/disabled/i.test(e.className);
    return {e,arg,disabled};
  });
  const current=scope.querySelector('.rgCurrentPage')?.textContent.trim();
  if(current&&/^\d+$/.test(current))result.index=Number(current);
  else if(pagers.length){
    const numbers=[...new Set(pagers.flatMap(r=>[...r.querySelectorAll('span')]).filter(e=>!e.closest('a')&&/^\d+$/.test(e.textContent.trim())).map(e=>Number(e.textContent.trim())))];
    if(numbers.length===1)result.index=numbers[0];else pagerUncertain=true;
  }
  const first=commands.find(c=>!c.disabled&&(c.arg==='First'||c.arg==='1'));
  const next=commands.find(c=>!c.disabled&&c.arg==='Next')||commands.filter(c=>!c.disabled&&/^\d+$/.test(c.arg||'')&&Number(c.arg)>result.index).sort((a,b)=>Number(a.arg)-Number(b.arg))[0];
  for(const e of document.querySelectorAll('[data-gh-inbox-page]'))e.removeAttribute('data-gh-inbox-page');
  if(first){first.e.setAttribute('data-gh-inbox-page','first');result.first='[data-gh-inbox-page="first"]';}
  if(next){next.e.setAttribute('data-gh-inbox-page','next');result.next='[data-gh-inbox-page="next"]';}
  if(commands.some(c=>!c.arg&&!c.e.matches('.rgCurrentPage,.rgPagePrev,.rgPageLast')))pagerUncertain=true;
  // The visual pager can be absent or custom. Prefer the grid's own page count.
  try {
    const count=view?.get_pageCount?.(), index=view?.get_currentPageIndex?.();
    if(Number.isInteger(count)&&count>0&&Number.isInteger(index)&&index>=0&&index<count){
      result.index=index+1;result.pageCount=count;pagerUncertain=false;
      if(typeof view.page==='function'){
        delete result.next;delete result.first;
        if(index>0)result.first='api:First';
        if(index+1<count)result.next='api:Next';
      }else if(index+1<count&&!result.next){
        result.complete=false;result.reason='A grade informa outras paginas, mas o comando de navegacao nao foi identificado.';
      }
    }
    const total=view?.get_virtualItemCount?.();
    if(Number.isInteger(total)&&total>0)result.expectedRows=total;
  } catch (_) {result.complete=false;}
  if(pagerUncertain){result.complete=false;result.reason='Os controles de paginacao nao foram reconhecidos por completo.';}
  const actual=rows.filter(r=>r.matches('.rgRow,.rgAltRow'));
  for(const row of actual.length?actual:rows){
    if(row.querySelector('th')||row.matches('.rgFilterRow,.rgGroupHeader,.rgFooter')||pagers.includes(row))continue;
    const cells=[...row.cells];
    if(cells.length<=columns.solicitacao)continue;
    const cell=cells[columns.solicitacao];
    const refs=[cell.innerText.trim(),...[...cell.querySelectorAll('a')].map(a=>a.innerText.trim())];
    const matches=refs.map(ref=>ref.match(/^(\d{5,12})(?:\s*\/\s*(\d+))?$/)).filter(Boolean);
    const distinct=new Set(matches.map(m=>m[1]+'/'+(m[2]||'')));
    const match=distinct.size===1?matches[0]:null;
    if(!match){if(!/nenhum|semregistro|norecord/.test(norm(row.innerText)))result.complete=false;continue;}
    const item={solicitacao:match[1]};
    for(const [key,index]of Object.entries(columns))if(key!=='solicitacao'&&index>=0&&cells[index])item[key]=cells[index].innerText.trim();
    if(match[2])item.idTrabalho=match[2];
    if(item.idTrabalho&&!/^\d+$/.test(item.idTrabalho))delete item.idTrabalho;
    result.rows.push(item);
  }
  const requestHeading=valid[0].header?.cells[columns.solicitacao]?.textContent||'';
  const expectsWork=columns.idTrabalho>=0 || norm(requestHeading).includes('trab');
  if(expectsWork && result.rows.some(r=>!r.idTrabalho)) {
    result.complete=false;
    result.reason='A grid identifica solicitacoes, mas nao informa o numero de todos os trabalhos. Confira os vinculos indicados.';
  }
  return result;
}'''

GROUPS = r'''() => {
  const table=document.querySelector('#ctl00_cph1_hgrSol_ctl00');
  const scope=table?.closest('.RadGrid')||table;
  if(!scope)return {count:0};
  const headers=[...scope.querySelectorAll('tr.rgGroupHeader')];
  const collapsed=headers.filter(r=>r.getClientRects().length &&
    (r.getAttribute('aria-expanded')==='false'||r.querySelector('.rgExpand,.rgExpandIcon')));
  for(const row of scope.querySelectorAll('[data-gh-expand-group]'))row.removeAttribute('data-gh-expand-group');
  if(!collapsed.length)return {count:0};
  const row=collapsed[0];row.setAttribute('data-gh-expand-group','pending');
  const grid=window.$find?.(scope.id)||window.$find?.('ctl00_cph1_hgrSol');
  return {count:collapsed.length,api:typeof grid?.get_masterTableView?.()?.expandGroup==='function',
    clickable:!!row.querySelector('input.rgExpand,button.rgExpand,a.rgExpand,button:has(.rgExpandIcon)')};
}'''


def expand_groups(page, max_groups=200):
    for _ in range(max_groups):
        state=page.evaluate(GROUPS)
        if not state['count']:
            return True
        try:
            if state.get('api'):
                page.evaluate('''() => {
                  const row=document.querySelector('[data-gh-expand-group="pending"]');
                  const scope=row.closest('.RadGrid');
                  const grid=window.$find?.(scope?.id)||window.$find?.('ctl00_cph1_hgrSol');
                  grid.get_masterTableView().expandGroup(row,{expandChildren:true});
                }''')
            elif state.get('clickable'):
                page.locator('[data-gh-expand-group="pending"] input.rgExpand,[data-gh-expand-group="pending"] button.rgExpand,[data-gh-expand-group="pending"] a.rgExpand,[data-gh-expand-group="pending"] button:has(.rgExpandIcon)').first.click()
            else:
                return False
            page.wait_for_function('''() => {
              if(window.Sys?.WebForms?.PageRequestManager?.getInstance?.()?.get_isInAsyncPostBack?.())return false;
              const row=document.querySelector('[data-gh-expand-group="pending"]');
              return !row || (row.getAttribute('aria-expanded')!=='false'&&!row.querySelector('.rgExpand,.rgExpandIcon'));
            }''', timeout=15000)
        except Exception:
            return False
    return False


def read_inbox(page, max_pages=100):
    page.locator('#ctl00_cph1_hgrSol_ctl00').wait_for(state='visible', timeout=30000)
    collected, seen, reasons, pages = {}, set(), [], set()
    rows_read, expected_rows, expected_pages = 0, None, None
    def advance(selector, current):
        if selector in ('api:First','api:Next'):
            page.evaluate('''command => {
              const table=document.querySelector('#ctl00_cph1_hgrSol_ctl00');
              const scope=table.closest('.RadGrid')||table;
              const grid=window.$find?.(scope.id)||window.$find?.('ctl00_cph1_hgrSol');
              grid.get_masterTableView().page(command);
            }''', selector.split(':')[1])
        else:
            page.locator(selector).click()
        page.wait_for_function('''previous => {
          if(document.readyState==='loading'||window.Sys?.WebForms?.PageRequestManager?.getInstance?.()?.get_isInAsyncPostBack?.())return false;
          const current=('''+GRID+''')();
          return current.index!==undefined && (current.index!==previous.index || JSON.stringify(current.rows)!==JSON.stringify(previous.rows));
        }''', arg={'index':current.get('index'), 'rows':current.get('rows',[])}, timeout=20000)
    for step in range(max_pages):
        page.wait_for_function("() => document.readyState!=='loading'&&!window.Sys?.WebForms?.PageRequestManager?.getInstance?.()?.get_isInAsyncPostBack?.()", timeout=20000)
        if not expand_groups(page) and 'Nao foi possivel expandir todos os grupos da Minha Grid.' not in reasons:
            reasons.append('Nao foi possivel expandir todos os grupos da Minha Grid.')
        current=page.evaluate(GRID)
        if step==0 and current.get('index',1)>1:
            if not current.get('first'):
                return {'rows':[],'complete':False,'reason':'Nao foi possivel consultar a primeira pagina.'}
            try:
                advance(current['first'], current)
            except Exception:
                return {'rows':[],'complete':False,'reason':'A paginacao nao retornou ao inicio.'}
            current=page.evaluate(GRID)
            if current.get('index')!=1:
                return {'rows':[],'complete':False,'reason':'A paginacao nao retornou ao inicio.'}
            if not expand_groups(page):
                reasons.append('Nao foi possivel expandir todos os grupos da Minha Grid.')
            current=page.evaluate(GRID)
        identity=(current.get('index'),json.dumps(current.get('rows',[]),sort_keys=True))
        if identity in seen:
            return {'rows':list(collected.values()),'complete':False,'reason':'A paginacao nao avancou.'}
        seen.add(identity)
        pages.add(current.get('index',1))
        rows_read += len(current.get('rows',[]))
        expected_pages=current.get('pageCount',expected_pages)
        expected_rows=current.get('expectedRows',expected_rows)
        for item in current['rows']:
            key=(item['solicitacao'],item.get('idTrabalho',''))
            if key in collected and collected[key]!=item:
                return {'rows':list(collected.values()),'complete':False,'reason':'Dados divergentes para a mesma referencia.'}
            collected[key]=item
        if current.get('complete') is not True:
            reason=current.get('reason','Parte da Minha Grid nao foi reconhecida.')
            if reason not in reasons: reasons.append(reason)
            if 'index' not in current:
                return {'rows':list(collected.values()),'complete':False,'reason':reason, 'headers':current.get('headers',[])}
        if not current.get('next'):
            values=list(collected.values())
            level='work' if values and all(r.get('idTrabalho') for r in values) else 'mixed' if any(r.get('idTrabalho') for r in values) else 'request'
            if expected_pages and pages != set(range(1,expected_pages+1)):
                reasons.append('Nem todas as paginas informadas pela grade foram consultadas.')
            if expected_rows and rows_read < expected_rows:
                reasons.append('A quantidade lida e menor que o total informado pela grade.')
            return {'rows':values,'complete':not reasons,'referenceLevel':level,
                'pagesRead':len(pages),'expectedPages':expected_pages,'rowsRead':rows_read,'expectedRows':expected_rows,
                **({'reason':' '.join(reasons)} if reasons else {})}
        try:
            advance(current['next'], current)
        except Exception:
            return {'rows':list(collected.values()),'complete':False,'reason':'A paginacao nao avancou.'}
    return {'rows':list(collected.values()),'complete':False,'reason':'Limite de paginas atingido.'}


def main():
    from edesk_comentario import (carregar_request, obter_credenciais_edesk, obter_url,
                                 aguardar_login, obter_guid_da_url, acessar_minha_grid)
    from config import PROFILE_DIR, HEADLESS, restore_session_cookies, save_session_cookies
    from edesk_conferencia import protect_read_only
    from playwright.sync_api import sync_playwright
    data=carregar_request()
    if data.get('enviar') is not False:
        raise ValueError('A busca de recebidos permite apenas consulta.')
    with sync_playwright() as p:
        context=p.chromium.launch_persistent_context(str(PROFILE_DIR),headless=HEADLESS,viewport=None)
        try:
            context.route('**/*',protect_read_only)
            restore_session_cookies(context)
            page=context.pages[0] if context.pages else context.new_page()
            page.goto(obter_url(data),wait_until='domcontentloaded',timeout=60000)
            aguardar_login(page,credenciais=obter_credenciais_edesk(data))
            guid=obter_guid_da_url(page.url)
            if not guid:raise RuntimeError('Sessao nao identificada.')
            save_session_cookies(context)
            acessar_minha_grid(page,guid)
            search=page.locator('#cph1_txtSol')
            if search.count()==1 and search.input_value().strip():
                search.fill('')
                page.locator('#cph1_btnLocSol').click(timeout=15000)
                page.wait_for_timeout(500)
            result=read_inbox(page)
        finally:
            context.close()
    print(json.dumps({'ok':True,'operation':'recebidos',**result,
        'message':'Minha Grid consultada. Nenhum trabalho foi cadastrado automaticamente.'},ensure_ascii=False),flush=True)
    return 0


if __name__=='__main__':
    try:sys.exit(main())
    except Exception:
        print(json.dumps({'ok':False,'operation':'recebidos','message':'Nao foi possivel consultar a Minha Grid. Confira a integracao e o login.'}),flush=True)
        sys.exit(1)
