"""Authenticated project document tools; edits use the existing verified Excel writer."""
import base64
from datetime import datetime
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import tempfile
from zipfile import ZipFile
from xml.etree import ElementTree as ET

MAIN = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
NS = {'m': MAIN}
PLAN_NAMES = ('Plano de Projeto', 'Plano de Projeto Start')
_PLAN_TEXT = re.compile(r'^=IF\(TRUE,(?:"(?:[^"]|"")*"&)*"(?:[^"]|"")*",\((.*)\)\)$', re.S | re.I)


def plan_original_formula(formula):
    match = _PLAN_TEXT.fullmatch(str(formula))
    return '=' + match[1] if match else formula


def plan_text_formula(formula, text):
    if not isinstance(text, str):
        raise ValueError('Informe um texto para a conclusão do projeto.')
    original = plan_original_formula(formula)
    if not isinstance(original, str) or not original.startswith('='):
        raise ValueError('A fórmula original do Plano de Projeto não foi identificada.')
    chunks = [text[i:i+100] for i in range(0, len(text), 100)] or ['']
    literal = '&'.join('"' + chunk.replace('"', '""') + '"' for chunk in chunks)
    result = f'=IF(TRUE,{literal},({original[1:]}))'
    if len(result.encode('utf-16-le')) // 2 > 8192:
        raise ValueError('O texto excede o limite de fórmula do Excel. Reduza a conclusão antes de salvar.')
    return result


def restore_summary_formulas(book):
    """Return dates to their original calculation when switching to day-driven edits."""
    from local_edesk.stage_dates import original_formula
    for name, addresses in [
        ('Implantação - Linha do Tempo', [f'{c}{r}' for c in ('H','I') for r in range(3,8)]),
        ('Dados', [f'{c}{r}' for c in ('AI','AJ') for r in range(7,12)])]:
        try:
            sheet=book.Worksheets(name)
        except Exception:
            continue
        for address in addresses:
            cell=sheet.Range(address)
            if cell.HasFormula:
                formula=str(cell.Formula)
                original=original_formula(formula)
                if original!=formula:
                    if bool(getattr(cell,'HasArray',False)):
                        raise ValueError('A data pertence a uma fórmula matricial. O original será preservado.')
                    cell.Formula=original
            cell=None


def plan_sheet(book):
    found = []
    for name in PLAN_NAMES:
        try:
            found.append(book.Worksheets(name))
        except Exception:
            pass
    if len(found) != 1:
        raise ValueError('Não foi possível identificar um único Plano de Projeto nesta planilha.')
    return found[0]


def plan_last_row(sheet):
    try:
        used = sheet.UsedRange
        last = int(used.Row) + int(used.Rows.Count) - 1
    except AttributeError:
        last = 205  # Minimal sheet doubles used by unit tests.
    if last > 500:
        raise ValueError('O Plano de Projeto excede o limite de 500 linhas do editor.')
    return max(205, last)


def plan_inserted_rows(book, sheet_name):
    result = set()
    for name in getattr(book, 'Names', []):
        if not str(name.Name).split('!')[-1].startswith('_GH_PlanRows_'):
            continue
        region = name.RefersToRange
        if str(region.Worksheet.Name) != sheet_name:
            continue
        first, count = int(region.Row), int(region.Rows.Count)
        if int(region.Column) != 1 or int(region.Columns.Count) != 12 or not 1 <= first <= first+count-1 <= 500:
            raise ValueError('O vínculo das linhas inseridas no Plano de Projeto é inválido.')
        result.update(range(first, first+count))
    return result


def plan_snapshot(book, name):
    sheet = plan_sheet(book)
    if sheet.Name != name:
        raise ValueError('O Plano de Projeto selecionado não corresponde ao arquivo.')
    fields, formulas = [], []
    last = plan_last_row(sheet)
    inserted = plan_inserted_rows(book, name)
    values = sheet.Range(f'A1:L{last}').Value2
    expressions = sheet.Range(f'A1:L{last}').Formula
    for r, row in enumerate(values, 1):
        for c, raw in enumerate(row, 1):
            address = f'{chr(64+c)}{r}'
            formula = expressions[r-1][c-1]
            calculated = isinstance(formula, str) and formula.startswith('=')
            formulas.append([address, plan_original_formula(formula) if calculated else None])
            # Existing text and blank agreement items adjacent to a numbered item.
            blank_item = c == 2 and isinstance(row[0], str) and re.fullmatch(r'\d+\.\d+\.\d+', row[0].strip())
            inserted_blank = r in inserted and raw in (None, '') and not calculated
            if inserted_blank:
                cell = sheet.Range(address)
                if cell.MergeCells and (int(cell.MergeArea.Row) != r or int(cell.MergeArea.Column) != c):
                    inserted_blank = False
            conclusion = calculated and (plan_original_formula(formula) != formula or
                isinstance(raw, str) and raw.startswith('O cliente ') and 'homologa' in raw and 'aceita' in raw)
            if conclusion and bool(getattr(sheet.Range(address), 'HasArray', False)):
                conclusion = False
            if conclusion or not calculated and (isinstance(raw, str) and raw.strip() or blank_item or inserted_blank):
                field = {'sheet': name, 'cell': address, 'kind': 'text',
                               'label': address, 'group': 'Plano de Projeto',
                               'value': '' if raw is None else str(raw), 'readOnly': False}
                if conclusion:
                    field.update(managedPlanTextFormula=True, sourceFormula=formula)
                fields.append(field)
    return {'fields': fields, 'tasks': [], 'worksheet': name,
            'planRowsVersion': 1, 'planGuidanceVersion': 1, 'planLastRow': last,
            'formulaCount': sum(1 for _, formula in formulas if formula is not None),
            'formulaFingerprint': hashlib.sha256(json.dumps(formulas).encode()).hexdigest()}


def plan_view_region(sheet):
    """Include visible guidance shapes outside the printed A:L document."""
    last_column, last_row = 12, plan_last_row(sheet)
    notes = []
    page = sheet.Range(f'A1:L{last_row}')
    document_right = float(page.Left) + float(page.Width)
    for shape in sheet.Shapes:
        if not bool(shape.Visible):
            continue
        # Read geometry only; never invoke a shape's assigned macro.
        bottom = shape.BottomRightCell
        column, row = int(bottom.Column), int(bottom.Row)
        if column > 32 or row > 500:
            raise ValueError('O Plano de Projeto possui objetos fora da área de visualização suportada. Confira o modelo antes de editar.')
        last_column = max(last_column, column + (1 if column > 12 else 0))
        last_row = max(last_row, row)
        try:
            text = str(shape.TextFrame2.TextRange.Text or '').strip()
        except Exception:
            text = ''
        if text and float(shape.Left) + float(shape.Width) > document_right:
            notes.append({'name': str(shape.Name), 'text': text})
    def letter(column):
        result = ''
        while column:
            column, digit = divmod(column - 1, 26)
            result = chr(65 + digit) + result
        return result
    return sheet.Range(f'A1:{letter(last_column)}{last_row}'), notes


def remove_plan_guidance(sheet, names):
    """Remove guidance from view/print, preserving embedded workbook assets."""
    _, notes = plan_view_region(sheet)
    allowed = {note['name'] for note in notes}
    if not names or any(name not in allowed for name in names):
        raise ValueError('Selecione somente as orientações identificadas ao lado do plano.')
    shapes = {str(shape.Name): shape for shape in sheet.Shapes}
    for name in names:
        shapes[name].Visible = False


def plan_mirror(book, snapshot):
    """Capture Excel's actual sheet, with editable cell positions in its own coordinates."""
    import io
    import time
    import win32clipboard
    from PIL import Image, ImageGrab
    sheet = book.Worksheets(snapshot['worksheet'])
    region, notes = plan_view_region(sheet)
    sheet.Activate()
    app = book.Application
    app.ScreenUpdating = True
    # Copy the document, not Excel's page-break-view watermarks or gridlines.
    app.ActiveWindow.View = 1
    app.ActiveWindow.DisplayGridlines = False
    sheet.DisplayPageBreaks = False
    left, top = float(region.Left), float(region.Top)
    width, height = float(region.Width), float(region.Height)
    positions = []
    for field in snapshot['fields']:
        cell = sheet.Range(field['cell'])
        area = cell.MergeArea if cell.MergeCells else cell
        if float(area.Width) <= 0 or float(area.Height) <= 0:
            continue
        positions.append({
            'cell': field['cell'], 'left': (float(area.Left)-left)/width,
            'top': (float(area.Top)-top)/height, 'width': float(area.Width)/width,
            'height': float(area.Height)/height,
            'fontSize': float(cell.Font.Size), 'bold': bool(cell.Font.Bold),
            'italic': bool(cell.Font.Italic), 'fontName': str(cell.Font.Name),
            'fontColor': int(cell.Font.Color), 'fillColor': int(cell.Interior.Color),
            'alignment': int(cell.HorizontalAlignment),
        })
        cell = area = None
    image = None
    for attempt in range(4):
        win32clipboard.OpenClipboard()
        try:
            win32clipboard.EmptyClipboard()
        finally:
            win32clipboard.CloseClipboard()
        sequence = win32clipboard.GetClipboardSequenceNumber()
        region.CopyPicture(Appearance=1, Format=2)
        time.sleep(.35 + attempt*.15)
        if win32clipboard.GetClipboardSequenceNumber() != sequence:
            captured = ImageGrab.grabclipboard()
            if isinstance(captured, Image.Image):
                image = captured
                break
    if image is None:
        raise ValueError('O Excel não conseguiu gerar o espelho editável do Plano de Projeto. Recarregue; o arquivo original foi preservado.')
    if image.width * image.height > 40_000_000:
        raise ValueError('O Plano de Projeto excede o tamanho de visualização permitido.')
    stream = io.BytesIO()
    image.save(stream, format='PNG')
    payload = stream.getvalue()
    if len(payload) > 15*1024*1024:
        raise ValueError('O espelho do Plano de Projeto excede 15 MB.')
    row_positions = []
    for number in range(1, plan_last_row(sheet) + 1):
        row = sheet.Rows(number)
        if float(row.Height) > 0:
            row_positions.append({'row': number, 'top': (float(row.Top)-top)/height,
                                  'height': float(row.Height)/height})
        row = None
    return {'imageBase64': base64.b64encode(payload).decode('ascii'),
            'width': image.width, 'height': image.height, 'cells': positions,
            'renderer': 'excel', 'range': str(region.Address),
            'documentRange': f'A1:L{plan_last_row(sheet)}', 'printArea': str(sheet.PageSetup.PrintArea),
            'adjustmentNotes': notes, 'rows': row_positions, 'planMirrorVersion': 3}


def timeline_seconds(raw, duration=False):
    if isinstance(raw, (int, float)) and not isinstance(raw, bool) and math.isfinite(raw) and raw >= 0:
        seconds = round(raw * 86400)
    elif isinstance(raw, str) and re.fullmatch(r'\d+:[0-5]\d(?::[0-5]\d)?', raw.strip()):
        parts = [int(part) for part in raw.strip().split(':')]
        seconds = parts[0] * 3600 + parts[1] * 60 + (parts[2] if len(parts) == 3 else 0)
    else:
        return None
    return seconds if duration or seconds < 86400 else None


def timeline_clock(seconds):
    return '' if seconds is None else f'{seconds//3600:02}:{seconds//60%60:02}:{seconds%60:02}'


def timeline_grid(book):
    from local_edesk.excel_editor import timeline_fields, BASE
    fields, cached = timeline_fields(book)
    if cached is None or not any(f.get('timelineDays') for f in fields):
        raise ValueError('Esta planilha não possui a tabela DetalhesProjeto com ajuste de dias. Use Escolher guia para editar o cronograma correspondente ao modelo.')
    source = cached.source
    table = next(t for t in source.ListObjects if str(t.Name) == 'DetalhesProjeto')
    first = int(table.Range.Row)
    last = int(table.Range.Row + table.Range.Rows.Count - 1)
    values = source.Range(f'A{first}:V{last}').Value2
    columns = [{'letter': chr(65+c), 'label': str(values[0][c] or ''),
                'width': min(440, max(65, float(source.Columns(c+1).ColumnWidth)*7))} for c in range(22)]
    rows = []
    for offset, values_row in enumerate(values[1:], 1):
        r = first+offset
        cells = []
        for c, raw in enumerate(values_row, 1):
            if c == 3:
                raw = str(source.Range(f'C{r}').Text)
            elif c in (10, 11):
                seconds = timeline_seconds(raw, duration=c == 11)
                raw = timeline_clock(seconds) if seconds is not None else str(raw or '')
            elif raw is None:
                raw = ''
            elif isinstance(raw, float) and raw.is_integer():
                raw = int(raw)
            cells.append(raw)
        from local_edesk.excel_editor import value
        rows.append({'row': r, 'cells': cells, 'date': value(source.Range(f'C{r}'), 'date'),
                     'startSeconds': timeline_seconds(values_row[9]),
                     'durationSeconds': timeline_seconds(values_row[10], duration=True)})
    warnings = [f'C{row["row"]}' for row in rows if not isinstance(source.Range(f'C{row["row"]}').Value2, (float, int))]
    periods=[]
    for r in range(3,8):
        label=str(source.Cells(r,6).Value2 or '').strip()
        start, end=source.Cells(r,8).Value2, source.Cells(r,9).Value2
        def day(v):
            from datetime import timedelta
            return (BASE+timedelta(days=v)).strftime('%Y-%m-%d') if isinstance(v,(float,int)) and not isinstance(v,bool) and v>1 else None
        periods.append({'label':label,'start':day(start),'end':day(end)})
    return {'sheet': source.Name, 'columns': columns, 'rows': rows, 'fields': fields, 'periods':periods,
            'warnings': warnings, 'timelineVersion': 1, 'timelineCalculationVersion': 1}


def timeline_snapshot(book):
    from local_edesk.excel_editor import timeline_fields
    fields, sheet = timeline_fields(book)
    if sheet is None or not any(f.get('timelineDays') for f in fields):
        raise ValueError('A tabela de dias deste modelo não foi identificada.')
    from local_edesk.stage_dates import original_formula
    seen = {(f['sheet'], f['cell']) for f in fields}
    for field in list(fields):
        source = (field.get('dateDriver') or {}).get('sourceField')
        if source and (source['sheet'], source['cell']) not in seen:
            fields.append(source)
            seen.add((source['sheet'], source['cell']))
    formulas = [(r, c, original_formula(f) if 3<=r<=7 and c in (8,9) else f)
                for r, row in enumerate(sheet.formulas, 1)
                for c, f in enumerate(row, 1) if isinstance(f, str) and f.startswith('=')]
    return {'fields': fields, 'tasks': [], 'worksheet': sheet.Name,
            'formulaFingerprint': hashlib.sha256(json.dumps(formulas).encode()).hexdigest()}


def export_pdf(sheet, folder, timeline=False):
    if timeline:
        sheet.PageSetup.PrintArea = '$A$1:$I$16'
        sheet.PageSetup.Zoom = False
        sheet.PageSetup.FitToPagesWide = 1
        sheet.PageSetup.FitToPagesTall = 1
    target = Path(folder)/'documento.pdf'
    sheet.ExportAsFixedFormat(0, str(target), Quality=0, IncludeDocProperties=False,
                             IgnorePrintAreas=False, OpenAfterPublish=False)
    payload = target.read_bytes()
    if not payload.startswith(b'%PDF') or len(payload) > 20*1024*1024:
        raise ValueError('O PDF gerado é inválido ou excede 20 MB. Confira a área de impressão.')
    return {'pdfBase64': base64.b64encode(payload).decode('ascii'), 'sheet': sheet.Name}


def execute(path, body):
    from local_edesk import excel_editor as editor
    operation = body.get('operation')
    if operation not in {'timeline-read', 'timeline-preview', 'timeline-calculate', 'timeline-save', 'plan-read', 'plan-preview', 'plan-save'}:
        raise ValueError('Operação de documento inválida.')
    plan = operation.startswith('plan-')
    kind = 'plan' if plan else 'timeline'
    if plan and isinstance(body.get('changes'), list) and any(isinstance(c, dict) and 'operation' in c for c in body['changes']):
        if operation not in {'plan-preview', 'plan-save'}:
            raise ValueError('Confira a inserção de linhas antes de recarregar o plano.')
        from local_edesk.plan_rows import execute as execute_rows
        return execute_rows(path, body)
    # Saves retain backups, formula/VBA verification and revision checks.
    if operation.endswith('-save'):
        request = {**body, 'action': 'excel-editor-write'}
        if plan:
            with editor.workbook(path) as (_, book):
                request.update(worksheet=plan_sheet(book).Name, documentKind='plan')
        else:
            edits = body.get('changes')
            if not isinstance(edits, list) or any(not isinstance(c, dict) or c.get('sheet') != 'Implantação - Linha do Tempo' or not re.fullmatch(r'[CHJK][1-9]\d*', str(c.get('cell', ''))) for c in edits):
                raise ValueError('Neste controle, ajuste apenas as datas e dias da Linha do Tempo.')
            request.update(worksheet='Implantação - Linha do Tempo', documentKind='timeline')
            checked = execute(path, {**body, 'operation': 'timeline-preview', '_validationOnly': True})
            if checked['warnings']:
                raise ValueError('Há datas sem cálculo: '+', '.join(checked['warnings'])+'. Ajuste os dias e confira a prévia antes de salvar. Nenhuma alteração foi gravada.')
            request['changes'] = checked['normalizedChanges']
        saved = editor.edit(path, request)
        return {'saved': True, 'revision': saved['revision'], 'backupCreated': bool(saved.get('backup'))}
    if not editor.lock.acquire(blocking=False):
        raise ValueError('Aguarde a leitura ou gravação da planilha em andamento.')
    try:
        original = editor.revision(path)
        if body.get('revision') is not None and body['revision'] != original:
            raise ValueError('O arquivo mudou. Recarregue antes de aplicar ajustes.')
        with tempfile.TemporaryDirectory(prefix='gerenciador-documento-') as folder:
            copy = Path(folder)/Path(path).name
            shutil.copy2(path, copy)
            with editor.workbook(copy, writable=True) as (app, book):
                before = plan_snapshot(book, plan_sheet(book).Name) if plan else timeline_snapshot(book)
                payload = body.get('changes')
                if not plan:
                    from local_edesk.timeline_dates import normalized_changes
                    changes = normalized_changes(book, before, payload or [])
                else:
                    changes = [] if payload is None or payload == [] else editor.validated_changes(before, payload)
                for field, value in changes:
                    if kind == 'timeline' and not (field.get('timelineDays') or field.get('timelineTime') or field['kind'] == 'date' and not field['readOnly']):
                        raise ValueError('Neste controle, ajuste apenas os dias e datas reconhecidos da Linha do Tempo.')
                    cell = book.Worksheets(field['sheet']).Range(field['cell'])
                    if cell.HasFormula:
                        if field.get('managedPlanTextFormula') and str(cell.Formula) == field.get('sourceFormula'):
                            cell.Formula = plan_text_formula(str(cell.Formula), value)
                            cell = None
                            continue
                        raise ValueError('Uma célula calculada não pode ser sobrescrita.')
                    cell.Value2 = editor.stored_date(field, value) if field['kind'] == 'date' else value
                    cell = None
                if changes:
                    if not plan:
                        restore_summary_formulas(book)
                    app.CalculateFull()
                result = plan_snapshot(book, plan_sheet(book).Name) if plan else timeline_grid(book)
                if not plan:
                    result['normalizedChanges'] = [dict(sheet=f['sheet'], cell=f['cell'], before=f['value'], value=v) for f,v in changes]
                sheet = plan_sheet(book) if plan else book.Worksheets(result['sheet'])
                if not body.get('_validationOnly') and operation != 'timeline-calculate':
                    result.update(export_pdf(sheet, folder, timeline=not plan))
                    if plan:
                        result['mirror'] = plan_mirror(book, result)
            if editor.revision(path) != original:
                raise ValueError('O arquivo mudou durante a prévia. Recarregue.')
            return {**result, 'revision': original, 'preview': True, 'filename': Path(path).name}
    finally:
        editor.lock.release()
