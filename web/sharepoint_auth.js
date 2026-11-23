/* Microsoft delegated authorization. Credentials stay in memory, never storage. */
(() => {
  'use strict';
  let session = null;
  let running = false;
  const scope = 'https://graph.microsoft.com/Files.ReadWrite';
  const guid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  const encode = bytes => btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const random = () => encode(crypto.getRandomValues(new Uint8Array(32)));
  const validLink = value => {
    try {
      const url = new URL(value);
      return url.protocol === 'https:' && !url.username && !url.password &&
        (!url.port || url.port === '443') && url.hostname.endsWith('.sharepoint.com');
    } catch (_) { return false; }
  };
  async function request(url, options) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 20000);
    try { return await fetch(url, {...options, signal: controller.signal, credentials: 'omit', redirect: 'error'}); }
    finally { clearTimeout(timeout); }
  }
  async function authorize(config) {
    // Open before the first await so the browser recognizes the user's click.
    const popup = window.open('about:blank', 'gerenciador-sharepoint', 'popup,width=580,height=720');
    if (!popup) throw Error('Permita a janela de conexão Microsoft neste navegador.');
    const state = random(), verifier = random();
    const redirect = new URL('sharepoint-callback.html', document.baseURI).href;
    let removeListeners = () => {};
    try {
      const challenge = encode(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier))));
      const response = new Promise((resolve, reject) => {
        // BroadcastChannel also supports browsers that isolate the Microsoft
        // popup from window.opener through Cross-Origin-Opener-Policy.
        const channel = typeof BroadcastChannel === 'function'
          ? new BroadcastChannel('gerenciador-sharepoint-' + state) : null;
        const timer = setTimeout(() => reject(Error('A conexão Microsoft não foi concluída em 3 minutos. Tente novamente.')), 180000);
        const receive = data => {
          if (data?.type !== 'gerenciador-sharepoint-auth' || data.state !== state) return;
          if (data.error) reject(Error(data.error === 'access_denied'
            ? 'A conexão Microsoft foi cancelada ou não autorizada. Consulte a TI.'
            : 'Não foi possível autorizar a conexão Microsoft. Confira o aplicativo e o diretório com a TI.'));
          else if (typeof data.code === 'string' && data.code.length < 10000) resolve(data.code);
        };
        const listener = event => {
          if (event.origin === location.origin && event.source === popup) receive(event.data);
        };
        window.addEventListener('message', listener);
        if (channel) channel.onmessage = event => receive(event.data);
        removeListeners = () => { clearTimeout(timer); window.removeEventListener('message', listener); channel?.close(); };
      });
      const params = new URLSearchParams({client_id: config.clientId, response_type: 'code',
        redirect_uri: redirect, response_mode: 'query', scope, state,
        code_challenge: challenge, code_challenge_method: 'S256', prompt: 'select_account'});
      popup.location.href = `https://login.microsoftonline.com/${config.tenantId}/oauth2/v2.0/authorize?${params}`;
      const code = await response;
      const tokenResponse = await request(`https://login.microsoftonline.com/${config.tenantId}/oauth2/v2.0/token`, {
        method: 'POST', body: new URLSearchParams({client_id: config.clientId, grant_type: 'authorization_code',
          code, redirect_uri: redirect, code_verifier: verifier, scope})
      });
      if (!tokenResponse.ok) throw Error('A Microsoft não concluiu a conexão. Confira com a TI a URI de retorno e o registro como SPA.');
      const token = await tokenResponse.json();
      if (typeof token.access_token !== 'string' || !(Number(token.expires_in) > 0)) throw Error('A Microsoft não retornou uma sessão válida.');
      return {token: token.access_token, until: Date.now() + (Number(token.expires_in) - 60) * 1000};
    } finally { removeListeners(); try { popup.close(); } catch (_) {} }
  }
  async function resolveNames(config) {
    if (!config || !guid.test(config.clientId || '') || !guid.test(config.tenantId || '') || !config.owner) {
      throw Error('Configure o ID do aplicativo e o ID do diretório fornecidos pela TI.');
    }
    if (!Array.isArray(config.links) || config.links.length > 12 || config.links.some(link => !validLink(link))) {
      throw Error('Use somente links HTTPS válidos do SharePoint, até 12 por consulta.');
    }
    if (!config.links.length) return {names: {}, errors: []};
    const key = `${config.owner}|${config.tenantId}|${config.clientId}`;
    if (session?.key !== key) session = null;
    if (!session || session.until <= Date.now()) {
      session = null;
      if (!config.interactive) return {names: {}, errors: [], needsConnection: true};
      session = {...await authorize(config), key};
    }
    const names = {}, errors = [];
    for (const link of [...new Set(config.links)]) {
      const sharingId = 'u!' + encode(new TextEncoder().encode(link));
      const response = await request(`https://graph.microsoft.com/v1.0/shares/${sharingId}/driveItem?$select=name,folder`, {
        headers: {Authorization: 'Bearer ' + session.token}
      });
      if (!response.ok) {
        if (response.status === 401) session = null;
        const message = response.status === 401 ? 'A sessão Microsoft expirou. Conecte novamente.'
          : response.status === 403 ? 'Sua conta não tem acesso à pasta ou a TI ainda não autorizou a consulta.'
          : response.status === 404 ? 'Pasta não encontrada. Confira o link e o acesso da sua conta.'
          : response.status === 429 ? 'O SharePoint está limitando as consultas. Tente novamente em instantes.'
          : 'O SharePoint não concluiu a consulta. Tente novamente.';
        errors.push({url: link, message});
        if (response.status === 401) break;
        continue;
      }
      const item = await response.json();
      if (item.folder && typeof item.name === 'string' && item.name.trim() && item.name.length <= 512) {
        names[link] = item.name.trim();
      } else errors.push({url: link, message: 'O link não retornou o nome de uma pasta.'});
    }
    return {names, errors};
  }
  window.sharePointResolveNames = async raw => {
    if (running) return JSON.stringify({error: 'Aguarde a consulta ao SharePoint em andamento.'});
    running = true;
    try { return JSON.stringify(await resolveNames(JSON.parse(raw))); }
    catch (error) {
      const known = error instanceof TypeError || error?.name === 'AbortError';
      return JSON.stringify({error: known ? 'Não foi possível conectar à Microsoft. Confira a rede e tente novamente.' : error.message || 'Falha na consulta ao SharePoint.'});
    } finally { running = false; }
  };
})();
