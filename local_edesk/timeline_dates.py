"""Edit timeline dates through their inputs, never replacing C formulas."""
from datetime import datetime
import re

BASE = datetime(1899, 12, 30)


def annotate(book, source, fields, first):
    if not any(f.get('timelineDays') for f in fields):
        return fields
    mapped = {f['cell']: f for f in fields}
    for field in fields:
        if field['kind'] != 'date':
            continue
        row = int(field['cell'][1:])
        cell = source.Range(field['cell'])
        if not cell.HasFormula:
            # Direct values remain editable through the same validated mapping.
            if not field['readOnly']:
                field['timelineDateEditable'] = True
            continue
        # Array formulas are safe here too: only their input cell is changed.
        formula = str(cell.Formula)
        if row == first+1:
            match = re.fullmatch(r"='((?:[^']|'')+)'!\$?C\$?([1-9]\d*)", formula)
            if not match:
                continue
            try:
                entry = book.Worksheets(match[1].replace("''", "'"))
            except Exception:
                continue  # External/unrecognized references stay read-only.
            r = int(match[2])
            label = str(entry.Cells(r, 2).Value2 or '').strip()
            if label not in {'Assinatura da proposta', 'Início do projeto pela Consultoria'}:
                continue
            driver = entry.Range(f'C{r}')
            if driver.HasFormula:
                continue
            from local_edesk.excel_editor import value
            source_field = {'sheet': entry.Name, 'cell': f'C{r}', 'kind': 'date',
                'label': label, 'value': value(driver, 'date'), 'readOnly': False,
                'dateStorage': 'text' if isinstance(driver.Value2, str) or str(driver.NumberFormat) == '@' else 'number'}
            field.update(timelineDateEditable=True, dateDriver={'sheet': entry.Name, 'cell': f'C{r}', 'sourceField': source_field})
        elif (f'H{row-1}' in mapped and not mapped[f'H{row-1}']['readOnly'] and
                (('OFFSET(DetalhesProjeto[' in formula or
                  'OFFSET([@Data],-1,0,1,1)' in formula and
                  any(f'OFFSET([@[{label}]],-1,0,1,1)' in formula for label in ('Proxima Etapa|Dias', 'Próxima Etapa|Dias')))
                 and 'NETWORKDAYS.INTL(' in formula or
                 re.fullmatch(rf'=\$?C\$?{row-1}\+\$?H\$?{row-1}', formula))):
            field.update(timelineDateEditable=True,
                dateDriver={'sheet': source.Name, 'cell': f'H{row-1}', 'previousDate': f'C{row-1}'})
    return fields


def normalized_changes(book, snapshot, payload):
    """Resolve reviewed C edits in row order to H intervals or the seed date.

    Work is performed exclusively in the disposable workbook copy. The returned
    changes retain the original before-values for the verified writer.
    """
    from local_edesk.excel_editor import validated_changes, stored_date
    if not isinstance(payload, list) or len(payload) > 500:
        raise ValueError('Informe até 500 ajustes do cronograma.')
    if not payload:
        return []
    mapped = {(f['sheet'], f['cell']): f for f in snapshot['fields']}
    direct, dates, seen = [], [], set()
    for change in payload:
        if not isinstance(change, dict):
            raise ValueError('Ajuste de cronograma inválido.')
        key = (change.get('sheet'), change.get('cell'))
        field = mapped.get(key)
        if key in seen or field is None:
            raise ValueError('Célula de cronograma inválida ou repetida.')
        seen.add(key)
        if field.get('timelineDateEditable'):
            if change.get('before') != field['value']:
                raise ValueError('A data mudou desde a leitura. Recarregue o cronograma.')
            try:
                new = change['value']
                if not isinstance(new, str) or not re.fullmatch(r'\d{4}-\d{2}-\d{2}', new):
                    raise ValueError()
                datetime.strptime(new, '%Y-%m-%d')
            except (ValueError, KeyError):
                raise ValueError('Selecione uma data válida no cronograma.') from None
            dates.append((field, new))
        elif field.get('timelineDays') or field.get('timelineTime'):
            direct.append(change)
        else:
            raise ValueError('Ajuste apenas datas e dias reconhecidos do cronograma.')
    changes = validated_changes(snapshot, direct) if direct else []
    used = {(f['sheet'], f['cell']) for f, _ in changes}
    for field, new in changes:
        book.Worksheets(field['sheet']).Range(field['cell']).Value2 = new
    if not dates:
        return changes
    book.Application.CalculateFull()
    for field, new in sorted(dates, key=lambda item: int(item[0]['cell'][1:])):
        driver = field.get('dateDriver')
        if driver is None:
            target, value = field, new
        else:
            key = (driver['sheet'], driver['cell'])
            if key in used:
                raise ValueError('A data e os dias da mesma transição foram alterados juntos. Mantenha somente um desses ajustes.')
            target = mapped[key]
            if driver.get('previousDate'):
                previous = book.Worksheets(field['sheet']).Range(driver['previousDate']).Value2
                if not isinstance(previous, (int, float)) or isinstance(previous, bool):
                    raise ValueError('Ajuste primeiro a data anterior para calcular o intervalo de dias.')
                value = (datetime.strptime(new, '%Y-%m-%d')-BASE).days-int(previous)
                if value < 0:
                    raise ValueError('A data da etapa não pode ser anterior à etapa precedente.')
            else:
                value = new
        used.add((target['sheet'], target['cell']))
        changes.append((target, value))
        cell = book.Worksheets(target['sheet']).Range(target['cell'])
        if cell.HasFormula:
            raise ValueError('O ajuste tentaria substituir uma fórmula. Nada foi salvo.')
        cell.Value2 = stored_date(target, value) if target['kind'] == 'date' else value
        cell = None
        book.Application.CalculateFull()
        actual = book.Worksheets(field['sheet']).Range(field['cell']).Value2
        if not isinstance(actual, (float, int)) or isinstance(actual, bool) or int(actual) != (datetime.strptime(new, '%Y-%m-%d')-BASE).days:
            raise ValueError('O Excel não confirmou a data escolhida. Confira fins de semana, feriados e a fórmula desta etapa. Nada foi salvo.')
    return changes
