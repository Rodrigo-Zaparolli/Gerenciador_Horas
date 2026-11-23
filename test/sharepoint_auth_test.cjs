const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {webcrypto} = require('node:crypto');
const source = fs.readFileSync('web/sharepoint_auth.js', 'utf8');
const clientId='11111111-1111-1111-1111-111111111111';
const tenantId='22222222-2222-2222-2222-222222222222';
const link='https://cyncly.sharepoint.com/:f:/s/Client/token?e=abc';
function setup({status=200}={}) {
  const requests=[], listeners=new Set();let opened=0;
  const popup={close(){},location:{}};
  Object.defineProperty(popup.location,'href',{set(value){
    const auth=new URL(value);
    assert.equal(auth.origin,'https://login.microsoftonline.com');
    assert.equal(auth.searchParams.get('code_challenge_method'),'S256');
    assert.equal(auth.searchParams.get('scope'),'https://graph.microsoft.com/Files.ReadWrite');
    assert.equal(auth.searchParams.get('redirect_uri'),'https://gerenciador-horas.web.app/piloto/sharepoint-callback.html');
    const data={type:'gerenciador-sharepoint-auth',state:auth.searchParams.get('state'),code:'test-code'};
    setImmediate(()=>{
      for(const fn of listeners) {
        fn({origin:'https://evil.test',source:popup,data:{...data,code:'wrong'}});
        fn({origin:'https://gerenciador-horas.web.app',source:{},data:{...data,code:'wrong'}});
        fn({origin:'https://gerenciador-horas.web.app',source:popup,data});
      }
    });
  }});
  const window={open(){opened++;return popup;},addEventListener(_,fn){listeners.add(fn);},removeEventListener(_,fn){listeners.delete(fn);}};
  const context={window,location:{origin:'https://gerenciador-horas.web.app'},
    document:{baseURI:'https://gerenciador-horas.web.app/piloto/'},URL,URLSearchParams,
    TextEncoder,Uint8Array,crypto:webcrypto,btoa,AbortController,setTimeout,clearTimeout,
    fetch:async(url,options)=>{
      requests.push({url,options});
      if(url.includes('/token')) {
        assert.equal(options.body.get('code'),'test-code');
        assert.ok(options.body.get('code_verifier').length>=43);
        assert.equal(options.body.has('client_secret'),false);
        return {ok:true,json:async()=>({access_token:'fake-in-memory-token',expires_in:3600})};
      }
      assert.equal(new URL(url).origin,'https://graph.microsoft.com');
      assert.equal(options.method,undefined); // GET only
      assert.equal(new URL(url).searchParams.get('$select'),'name,folder');
      return {ok:status===200,status,json:async()=>({name:'Nome real da pasta',folder:{}})};
    }};
  vm.runInNewContext(source,context);
  return {requests,get opened(){return opened;},resolve:async changes=>JSON.parse(await window.sharePointResolveNames(JSON.stringify({
    owner:'owner-a',clientId,tenantId,links:[link],interactive:true,...changes}))) };
}
test('configuration and link validation prevent unwanted network requests',async()=>{
  const app=setup();
  assert.ok((await app.resolve({clientId:''})).error);
  assert.ok((await app.resolve({links:['https://cyncly.sharepoint.com.evil.test/x']})).error);
  assert.equal(app.requests.length,0);assert.equal(app.opened,0);
});
test('background lookup never opens a login window',async()=>{
  const app=setup();assert.equal((await app.resolve({interactive:false})).needsConnection,true);
  assert.equal(app.opened,0);assert.equal(app.requests.length,0);
});
test('PKCE popup validates origin and source; token stays out of returned result',async()=>{
  const app=setup();const result=await app.resolve({});
  assert.equal(result.names[link],'Nome real da pasta');assert.equal(app.opened,1);
  assert.equal(JSON.stringify(result).includes('fake-in-memory-token'),false);
  await app.resolve({interactive:false});assert.equal(app.opened,1);
  assert.equal(app.requests.filter(r=>r.url.includes('/token')).length,1);
  const graphUrl=app.requests.find(r=>r.url.includes('graph.microsoft.com')).url;
  const encoded=new URL(graphUrl).pathname.split('/')[3].slice(2);
  assert.equal(Buffer.from(encoded,'base64url').toString('utf8'),link);
  const other=await app.resolve({owner:'owner-b',interactive:false});
  assert.equal(other.needsConnection,true);
});
test('access failure is explicit, without inventing a folder name',async()=>{
  const app=setup({status:403});const result=await app.resolve({});
  assert.deepEqual(result.names,{});assert.match(result.errors[0].message,/acesso|TI/);
});
