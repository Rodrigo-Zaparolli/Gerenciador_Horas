"""Explicit summary-date overrides; retain the original formula as fallback."""
from datetime import datetime
import re

_MANUAL = re.compile(r'^=IF\(TRUE,DATE\(\d{4},\d{1,2},\d{1,2}\),\((.*)\)\)$', re.S | re.I)


def original_formula(formula):
    match = _MANUAL.fullmatch(str(formula))
    return '=' + match[1] if match else formula


def adjusted_formula(formula, date):
    day = datetime.strptime(date, '%Y-%m-%d')
    original = original_formula(formula)
    if not isinstance(original, str) or not original.startswith('='):
        raise ValueError('A formula original da data nao foi identificada.')
    return f'=IF(TRUE,DATE({day.year},{day.month},{day.day}),({original[1:]}))'


def timeline_period_fields(book, checklist_name, date_value):
    name = 'Implantação - Linha do Tempo'
    try:
        sheet = book.Worksheets(name)
        dados = book.Worksheets('Dados')
    except Exception:
        return []
    title = str(sheet.Range('F1').Value2 or '').strip()
    headers = [str(sheet.Cells(2, c).Value2 or '').strip() for c in range(6, 10)]
    if title != 'Status Projeto' or headers not in [
        ['Trabalhos', '%', 'Inicio', 'Fim'], ['Trabalhos', '%', 'Início', 'Fim']
    ]:
        return []
    formula = str(sheet.Range('G1').Formula or '')
    reference = "'" + checklist_name.replace("'", "''") + "'!"
    if reference.casefold() not in formula.casefold() and not re.search(r"(?<![\w '\-])" + re.escape(checklist_name) + r'!', formula, re.I):
        return []
    if str(dados.Range('AG5').Value2 or '').strip() != 'Status Projeto':
        return []
    fields, labels = [], set()
    for row in range(3, 8):
        label = str(sheet.Cells(row, 6).Value2 or '').strip()
        if not label or label in labels:
            return []
        labels.add(label)
        mirrors = [r for r in range(7, 12) if str(dados.Cells(r, 33).Value2 or '').strip() == label]
        if len(mirrors) != 1:
            return []
        for col, endpoint, mirror_col in [(8, 'start', 35), (9, 'end', 36)]:
            address = f'{"H" if col == 8 else "I"}{row}'
            mirror_address = f'{"AI" if mirror_col == 35 else "AJ"}{mirrors[0]}'
            def mapped(source, cell_address):
                cell = source.Range(cell_address)
                raw = cell.Value2
                calculated = bool(cell.HasFormula)
                if calculated and bool(getattr(cell, 'HasArray', False)):
                    raise ValueError('Uma data do resumo pertence a uma formula matricial. O original nao sera alterado.')
                return {'sheet': source.Name, 'cell': cell_address, 'kind': 'date',
                    'value': date_value(cell, 'date'), 'readOnly': False,
                    'dateStorage': 'text' if isinstance(raw, str) and not calculated else 'number',
                    'managedDateFormula': calculated, 'sourceFormula': str(cell.Formula) if calculated else None}
            field = mapped(sheet, address)
            field.update({'label': f'{label} — {"Início" if endpoint == "start" else "Fim"}',
                'group': 'Datas das etapas', 'stagePeriod': label, 'endpoint': endpoint,
                'dateMirrors': [mapped(dados, mirror_address)], 'dateMode': 'summary-adjusted'})
            fields.append(field)
    return fields


def with_mirrors(changes):
    result = list(changes)
    seen = {(f['sheet'], f['cell']) for f, _ in changes}
    for field, new in changes:
        for mirror in field.get('dateMirrors', []):
            key = mirror['sheet'], mirror['cell']
            if key in seen:
                raise ValueError('Duas alteracoes tentam ajustar a mesma data do resumo.')
            seen.add(key)
            result.append((mirror, new))
    return result


def validate_summary_periods(preview):
    for row in preview.get('rows', []):
        if not row.get('start') or not row.get('end'):
            continue
        try:
            start = datetime.strptime(row['start'], '%Y-%m-%d')
            end = datetime.strptime(row['end'], '%Y-%m-%d')
        except (ValueError, TypeError):
            raise ValueError(f"Confira as datas calculadas de {row['label']} antes de salvar.") from None
        if end < start:
            raise ValueError(f"O ajuste deixou o fim de {row['label']} anterior ao inicio. O original foi preservado.")
