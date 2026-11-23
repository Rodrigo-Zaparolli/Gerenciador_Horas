"""Verify phase values from a fresh page; never infer success from a click."""
import unicodedata


def validate_phase_targets(requested, names, key):
    counts = {}
    for name in names:
        normalized = key(name)
        counts[normalized] = counts.get(normalized, 0) + 1
    for name in requested:
        count = counts.get(key(name), 0)
        if count != 1:
            raise ValueError(f'A fase {name} nao foi encontrada de forma unica no E-Desk. Nenhuma data foi salva.')


async def fill_empty_original_dates(adjusted_start, start, end):
    """Use the visible phase's labelled columns, never another phase's fields."""
    return await adjusted_start.evaluate(r'''(adjusted, dates) => {
      const visible = e => e.getClientRects().length && getComputedStyle(e).visibility !== 'hidden';
      const norm = s => (s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z]/g, '');
      let owner = adjusted.parentElement;
      while (owner && !(owner.querySelectorAll("input[id*='txtGFasDtIniAj']").length === 1 &&
          owner.querySelectorAll("input[id*='txtGFasDtTerAju']").length === 1 &&
          norm(owner.textContent).includes('datainicial') && norm(owner.textContent).includes('datafinal'))) owner = owner.parentElement;
      if (!owner) throw Error('Nao foi possivel identificar os campos da fase.');
      const result = {};
      for (const [label, value, key] of [['datainicial', dates[0], 'dataInicialOriginal'], ['datafinal', dates[1], 'dataFinalOriginal']]) {
        if (!value) continue;
        const labels = [...owner.querySelectorAll('label,span,td,th,div')]
          .filter(e => visible(e) && norm(e.textContent) === label);
        const fields = new Set();
        for (const item of labels) {
          if (item.htmlFor) {
            const linked = document.getElementById(item.htmlFor);
            if (linked && linked.matches('input') && visible(linked)) fields.add(linked);
          }
          const cell = item.closest('td');
          if (cell) {
            for (const input of cell.querySelectorAll('input')) if (visible(input)) fields.add(input);
            const nextCell = cell.parentElement.nextElementSibling?.children[cell.cellIndex];
            if (nextCell) for (const input of nextCell.querySelectorAll('input')) if (visible(input)) fields.add(input);
          }
          const next = item.nextElementSibling;
          if (next?.matches('input') && visible(next)) fields.add(next);
        }
        // E-Desk also renders original dates as text when already registered.
        // Only an unambiguous editable input can be initialized.
        if (fields.size > 1) throw Error('Campo de data original ambiguo.');
        if (!fields.size) continue;
        const field = [...fields][0];
        if (/txtGFasDtIniAj|txtGFasDtTerAju/.test(field.id)) throw Error('Campo original corresponde a data ajustada.');
        if (field.value.trim()) continue;
        if (field.disabled || field.readOnly) throw Error('Data original vazia nao permite edicao.');
        field.focus();
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(field, value);
        field.dispatchEvent(new Event('input', {bubbles:true}));
        field.dispatchEvent(new Event('change', {bubbles:true}));
        field.blur();
        if (field.value.trim() !== value) throw Error('Data original nao foi preenchida.');
        result[key] = value;
      }
      return result;
    }''', [start, end])

def phase_key(value):
    return ''.join(c for c in unicodedata.normalize('NFKD', str(value)).lower()
                   if c.isalnum())

def mismatched_phases(expected, actual):
    errors = []
    for phase in expected:
        if not phase.get('dataInicial') and not phase.get('dataFinal'):
            continue
        matches = [row for row in actual if phase_key(row['nome']) == phase_key(phase['nome'])]
        if len(matches) != 1:
            errors.append(f"Não foi possível reler a fase {phase['nome']} com segurança.")
            continue
        for field in ('dataInicial', 'dataFinal'):
            if phase.get(field) and matches[0].get(field, '').strip() != phase[field].strip():
                errors.append(f"A data {field} da fase {phase['nome']} não foi persistida.")
    return errors

async def read_phase_rows(page):
    view = page.locator('#cph1_rpvFasePro')
    names = view.locator("span[id*='lblGFasNome']")
    starts = view.locator("input[id*='txtGFasDtIniAj']")
    ends = view.locator("input[id*='txtGFasDtTerAju']")
    rows = []
    count = await names.count()
    if count != await starts.count() or count != await ends.count():
        raise ValueError('A estrutura das fases mudou; não foi possível confirmar o salvamento.')
    for i in range(count):
        rows.append({'nome': (await names.nth(i).inner_text()).strip(),
                     'dataInicial': await starts.nth(i).input_value(),
                     'dataFinal': await ends.nth(i).input_value()})
    return rows

async def close_new_duplicate_requests(context, selected, original_pages):
    for candidate in list(context.pages):
        if candidate == selected or candidate in original_pages or candidate.is_closed():
            continue
        if '/Portal/Solicitacao.aspx' in candidate.url and candidate.url == selected.url:
            await candidate.close()
