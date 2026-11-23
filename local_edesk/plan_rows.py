"""Reviewed row insertions in a disposable Plano de Projeto; atomic save only."""
from datetime import datetime
from pathlib import Path
import os
import shutil
import tempfile
import uuid


def split(payload, last):
    if not isinstance(payload, list) or not 1 <= len(payload) <= 500:
        raise ValueError('Informe até 500 ajustes do Plano de Projeto.')
    edits, operations, total = [], [], 0
    for item in payload:
        if not isinstance(item, dict):
            raise ValueError('Ajuste de linha inválido.')
        if 'operation' not in item:
            edits.append(item)
            continue
        if item['operation'] == 'remove-plan-guidance':
            names = item.get('names')
            if not isinstance(names, list) or not 1 <= len(names) <= 50 or any(not isinstance(name, str) or not name.strip() or len(name) > 255 for name in names) or len(set(names)) != len(names):
                raise ValueError('Selecione até 50 orientações válidas do plano.')
            operations.append(item)
            continue
        row, count = item.get('row'), item.get('count')
        if item['operation'] != 'insert-plan-rows' or type(row) is not int or type(count) is not int or not 1 <= row <= last+1 or not 1 <= count <= 20:
            raise ValueError('Escolha uma linha válida e uma quantidade de 1 a 20.')
        total += count
        if total > 100 or last+count > 500:
            raise ValueError('Insira até 100 linhas por gravação, sem exceder 500 linhas no plano.')
        operations.append(item)
        last += count
    if not operations:
        raise ValueError('Nenhuma inclusão de linha foi informada.')
    return edits, operations


def insert(book, sheet, row, count):
    # Do not split a multi-row merged field in half.
    for column in range(1, 13):
        cell = sheet.Cells(row, column)
        if cell.MergeCells:
            area = cell.MergeArea
            if int(area.Row) < row <= int(area.Row) + int(area.Rows.Count)-1:
                raise ValueError('A linha escolhida está dentro de uma célula mesclada. Insira antes ou depois do bloco completo.')
    template = max(1, row-1)
    height = float(sheet.Rows(template).RowHeight)
    if height <= 0:
        height = float(sheet.StandardHeight)
    merges = set()
    for column in range(1, 13):
        cell = sheet.Cells(template, column)
        if cell.MergeCells:
            area = cell.MergeArea
            if int(area.Rows.Count) == 1:
                first, columns = int(area.Column), int(area.Columns.Count)
                if first+columns-1 <= 12:
                    merges.add((first, first+columns-1))
    insertion_top = float(sheet.Rows(row).Top)
    shapes = [(str(shape.Name), float(shape.Top)) for shape in sheet.Shapes]
    sheet.Rows(f'{row}:{row+count-1}').Insert(Shift=-4121, CopyOrigin=0 if row>1 else 1)
    sheet.Rows(f'{row}:{row+count-1}').RowHeight = height
    sheet.Rows(f'{row}:{row+count-1}').Hidden = False
    region = sheet.Range(f'A{row}:L{row+count-1}')
    region.UnMerge()
    region.ClearContents()
    for current in range(row, row+count):
        for first, last in merges:
            sheet.Range(sheet.Cells(current, first), sheet.Cells(current, last)).Merge()
    delta = height * count
    for name, top in shapes:
        if top >= insertion_top:
            sheet.Shapes(name).Top = top + delta
    # Excel updates these normal hidden named ranges on later row insertions.
    # They keep empty inserted cells editable after closing/reopening the file.
    book.Names.Add(Name='_GH_PlanRows_'+uuid.uuid4().hex[:12],
        RefersTo="='"+sheet.Name.replace("'", "''")+f"'!$A${row}:$L${row+count-1}", Visible=False)


def execute(path, body):
    from local_edesk import excel_editor as editor
    from local_edesk.project_documents import plan_sheet, plan_last_row, plan_snapshot, plan_text_formula, plan_mirror, export_pdf, remove_plan_guidance
    from local_edesk.consultoria_rows import preserve_assets_and_check
    path = Path(path)
    if path.suffix.lower() not in {'.xlsx', '.xlsm'} or path.stat().st_size > 25*1024*1024:
        raise ValueError('Use uma planilha XLSX ou XLSM de até 25 MB.')
    if not editor.lock.acquire(blocking=False):
        raise ValueError('Aguarde a leitura ou gravação da planilha em andamento.')
    try:
        original = editor.revision(path)
        if body.get('revision') != original:
            raise ValueError('A planilha mudou. Recarregue antes de inserir linhas.')
        with tempfile.TemporaryDirectory(prefix='.gerenciador-plano-', dir=path.parent) as folder:
            staged = Path(folder)/path.name
            shutil.copy2(path, staged)
            with editor.workbook(staged, writable=True) as (app, book):
                sheet = plan_sheet(book)
                before = plan_snapshot(book, sheet.Name)
                edits, operations = split(body['changes'], plan_last_row(sheet))
                for operation in operations:
                    if operation['operation'] == 'remove-plan-guidance':
                        remove_plan_guidance(sheet, operation['names'])
                    else:
                        insert(book, sheet, operation['row'], operation['count'])
                app.CalculateFull()
                baseline = plan_snapshot(book, sheet.Name)
                if baseline['formulaCount'] != before['formulaCount']:
                    raise ValueError('A inserção mudou a quantidade de fórmulas. O original foi preservado.')
                changes = editor.validated_changes(baseline, edits) if edits else []
                for field, value in changes:
                    cell = sheet.Range(field['cell'])
                    if cell.HasFormula:
                        if not field.get('managedPlanTextFormula') or str(cell.Formula) != field.get('sourceFormula'):
                            raise ValueError('Uma fórmula do plano não pode ser sobrescrita.')
                        cell.Formula = plan_text_formula(str(cell.Formula), value)
                    else:
                        cell.Value2 = value
                    cell = None
                app.CalculateFull()
                expected = plan_snapshot(book, sheet.Name)
                if expected['formulaFingerprint'] != baseline['formulaFingerprint']:
                    raise ValueError('Uma fórmula inesperada foi alterada. O original foi preservado.')
                if body['operation'] == 'plan-preview':
                    result = {**expected, **export_pdf(sheet, folder), 'mirror': plan_mirror(book, expected),
                              'planEditBaseline': baseline, 'revision': original, 'preview': True, 'filename': path.name}
                elif body['operation'] == 'plan-save':
                    book.Save()
                    result = None
                else:
                    raise ValueError('Operação de linhas inválida.')
                sheet = None
            if editor.revision(path) != original:
                raise ValueError('A planilha mudou durante o ajuste. O original foi preservado.')
            if result is not None:
                return result
            preserve_assets_and_check(path, staged, expected['worksheet'])
            with editor.workbook(staged) as (_, book):
                checked = plan_snapshot(book, expected['worksheet'])
                removed = {name for operation in operations if operation['operation'] == 'remove-plan-guidance' for name in operation['names']}
                if any(str(shape.Name) in removed and bool(shape.Visible) for shape in book.Worksheets(expected['worksheet']).Shapes):
                    raise ValueError('A remoção das orientações não foi confirmada. O original foi preservado.')
            if checked['formulaFingerprint'] != expected['formulaFingerprint']:
                raise ValueError('As fórmulas inseridas não foram confirmadas. O original foi preservado.')
            actual = {f['cell']: f['value'] for f in checked['fields']}
            if any(actual.get(field['cell']) != field['value'] for field in expected['fields']):
                raise ValueError('Os campos do plano não foram preservados nas novas posições. O original foi preservado.')
            if any(actual.get(f['cell']) != value for f, value in changes):
                raise ValueError('Um texto inserido não foi confirmado. O original foi preservado.')
            if editor.vba(path) != editor.vba(staged):
                raise ValueError('As macros mudaram. O original foi preservado.')
            editor.check_assets(path, staged)
            if editor.revision(path) != original:
                raise ValueError('A planilha mudou antes da gravação. Recarregue.')
            backup_dir = path.parent/'.gerenciador-backups'
            backup_dir.mkdir(exist_ok=True)
            backup = backup_dir/f'{path.stem}-{datetime.now():%Y%m%d-%H%M%S}-{uuid.uuid4().hex[:8]}{path.suffix}'
            shutil.copy2(path, backup)
            if editor.revision(backup) != original or editor.revision(path) != original:
                raise ValueError('A revisão do backup não confere. O original foi preservado.')
            try:
                os.replace(staged, path)
            except PermissionError:
                raise ValueError('Feche esta planilha no Excel e tente salvar novamente. O original foi preservado.') from None
            from local_edesk.backup_policy import prune_workbook_backups
            cleanup_warning = prune_workbook_backups(path, latest_backup=backup)
            return {'saved': True, 'revision': editor.revision(path), 'backupCreated': True,
                    'backupCleanupWarning': cleanup_warning,
                    'rowsInserted': sum(op['count'] for op in operations if op['operation'] == 'insert-plan-rows')}
    finally:
        editor.lock.release()
