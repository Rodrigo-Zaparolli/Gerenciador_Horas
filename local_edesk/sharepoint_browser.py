"""Read folder breadcrumbs in a user-authorized SharePoint browser session."""
import hashlib
import json
import os
from pathlib import Path
import sys
import time
from urllib.parse import urlsplit


def valid_link(value):
    if not isinstance(value, str) or len(value) > 4096:
        return False
    try:
        url = urlsplit(value)
        return (url.scheme == 'https' and url.hostname.endswith('.sharepoint.com')
                and not url.username and not url.password and url.port in (None, 443))
    except (AttributeError, ValueError):
        return False


def folder_name(page):
    # Never guess from a sharing token, browser title, or a truncated caption.
    return page.evaluate("""() => {
      const selectors = [
        '[data-automationid="breadcrumb"] [aria-current="page"]',
        '[data-automationid="breadcrumb"] li:last-child button',
        '.ms-Breadcrumb-list .ms-Breadcrumb-listItem:last-child .ms-Breadcrumb-itemLink',
        '[aria-label*="breadcrumb" i] [aria-current="page"]'
      ];
      for (const selector of selectors) {
        for (const el of document.querySelectorAll(selector)) {
          if (!el.getClientRects().length) continue;
          const name = (el.getAttribute('title') || el.getAttribute('aria-label') || el.textContent || '').trim();
          if (name && name.length <= 512 && !name.includes('…') && !name.endsWith('...')) return name;
        }
      }
      return null;
    }""")


def execute(owner, links):
    if not isinstance(owner, str) or not owner or not isinstance(links, list) or not 1 <= len(links) <= 5 or not all(valid_link(link) for link in links):
        raise ValueError('Informe de uma a cinco pastas SharePoint HTTPS válidas.')
    from playwright.sync_api import sync_playwright
    root = Path(os.environ.get('LOCALAPPDATA') or Path.home()) / 'GerenciadorHoras' / 'sharepoint-profiles'
    profile = root / hashlib.sha256(owner.encode()).hexdigest()
    profile.mkdir(parents=True, exist_ok=True)
    names, errors = {}, []
    with sync_playwright() as browser:
        context = browser.chromium.launch_persistent_context(str(profile), headless=False)
        try:
            page = context.pages[0] if context.pages else context.new_page()
            deadline = time.monotonic() + 150
            for link in dict.fromkeys(links):
                try:
                    page.goto(link, wait_until='domcontentloaded', timeout=30000)
                    name = None
                    while time.monotonic() < deadline:
                        if valid_link(page.url):
                            name = folder_name(page)
                            if name:
                                break
                        page.wait_for_timeout(500)
                    if name:
                        names[link] = name
                    else:
                        errors.append({'message': 'Nome não identificado. Confira o login e o acesso à pasta; você pode informar o nome manualmente.'})
                except Exception:
                    errors.append({'message': 'Não foi possível ler a pasta. Confira o acesso no navegador da integração.'})
        finally:
            context.close()
    return {'names': names, 'errors': errors}


if __name__ == '__main__':
    payload = json.loads(sys.stdin.read())
    print(json.dumps(execute(payload['owner'], payload['links']), ensure_ascii=True))
