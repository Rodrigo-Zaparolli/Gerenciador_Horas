(() => {
  const previews = new Map();
  function windowFeatures() {
    const width = Math.max(320, Math.min(1500, window.innerWidth - 32, screen.availWidth - 40));
    const height = Math.max(300, Math.min(Math.round(window.innerHeight * .94), screen.availHeight - 80));
    return `popup=yes,width=${width},height=${height},resizable=yes,scrollbars=yes`;
  }
  function paint(entry, encoded, title, draft) {
    const bytes = Uint8Array.from(atob(encoded), c => c.charCodeAt(0));
    if (bytes.length < 5 || String.fromCharCode(...bytes.slice(0,5)) !== '%PDF-') throw new Error('PDF inválido.');
    const url = URL.createObjectURL(new Blob([bytes], {type:'application/pdf'}));
    const doc = entry.window.document;
    doc.title = title;
    const old = entry.url;
    doc.body.replaceChildren();
    doc.body.style.cssText = 'margin:0;display:flex;flex-direction:column;height:100vh;background:#132236;color:#e6edf7;font:13px system-ui';
    const bar = doc.createElement('div');
    bar.style.cssText = 'padding:12px 16px;flex:none;display:flex;gap:12px;align-items:center';
    const label = doc.createElement('span');
    label.textContent = title + (draft ? ' · PRÉVIA: alterações ainda não salvas' : ' · Documento gerado');
    entry.label=label;
    entry.title=title;
    bar.append(label);
    const close = doc.createElement('button');
    close.textContent = 'Fechar';
    close.style.cssText = 'margin-left:auto;cursor:pointer;padding:6px 12px';
    close.onclick = () => entry.window.close();
    bar.append(close);
    const frame = doc.createElement('iframe');
    frame.title = title;
    frame.style.cssText = 'flex:1;width:100%;border:0;background:#fff';
    frame.src = url + '#view=FitH';
    doc.body.append(bar,frame);
    entry.url = url;
    if (old) URL.revokeObjectURL(old);
  }
  function dispose(key) {
    const entry = previews.get(key);
    if (!entry) return;
    if (!entry.window.closed) entry.window.close();
    if (entry.url) URL.revokeObjectURL(entry.url);
    previews.delete(key);
  }
  window.projectPdfWindows = {
    isOpen(key) {const entry=previews.get(key);return !!entry && !entry.window.closed;},
    open(key, encoded, title, draft) {
      let entry = previews.get(key);
      if (!entry || entry.window.closed) {
        const popup = window.open('', 'gerenciador-pdf-'+crypto.randomUUID(), windowFeatures());
        if (!popup) return false;
        entry = {window:popup, url:null};
        previews.set(key,entry);
      }
      try {paint(entry,encoded,title,draft);entry.window.focus();return true;}
      catch (_) {dispose(key);return false;}
    },
    update(key,encoded,title,draft) {
      const entry=previews.get(key);
      if (!entry) return;
      if (entry.window.closed) {dispose(key);return;}
      try {paint(entry,encoded,title,draft);} catch (_) {dispose(key);}
    },
    stale(key) {
      const entry=previews.get(key);
      if (entry && !entry.window.closed && entry.label) entry.label.textContent=entry.title+' · DESATUALIZADO: aplique os ajustes no Gerenciador para atualizar';
    },
    close:dispose
  };
  window.addEventListener('pagehide',()=>{for(const key of [...previews.keys()])dispose(key);});
})();
