"""Controlled equivalent of the reviewed Atualiza_PL_Prj visibility routine.

Never enables workbook VBA. Only worksheet visibility and plan row visibility
are updated; all writes pass through the verified Excel staging/backup writer.
"""
import re
from html import unescape

PROJECT_TYPES = ['# Selecionar #', 'CATALOG (catalog + builder + construtor)',
    'CONSULTORIAS E PLUGINS', 'ENTERPRISE + CATALOG',
    'ENTERPRISE PRODUÇÃO COMPLETA', 'ENTERPRISE PRODUÇÃO SIMPLIFICADA',
    'PROFESSIONAL', 'REVITALIZAÇÃO']


def apply(book, entry_name):
    entry = book.Worksheets(entry_name)
    selection = book.Names('CHEK_PL_PROJ').RefersToRange
    if selection.Worksheet.Name != entry.Name or int(selection.Column) != 2 or int(selection.Columns.Count) != 2:
        raise ValueError('A seleção de produtos não corresponde ao modelo revisado. Nada foi salvo.')
    flags = {}
    for row in selection.Value2:
        label, answer = str(row[1] or '').strip(), str(row[0] or '').strip()
        if not label:
            continue
        if label in flags or answer not in ('Sim', 'Não'):
            raise ValueError('Os produtos do modelo não foram reconhecidos. Nada foi salvo.')
        flags[label] = answer == 'Sim'
    if not {'Enterprise', 'Consultoria', 'Professional', 'Catalog'} <= flags.keys():
        raise ValueError('O checklist de produtos não corresponde ao modelo revisado.')
    states = {}
    for label, names in [
        ('Enterprise', ['Plano de Projeto', 'Checklist-Processo', 'Implantação - Linha do Tempo']),
        ('Consultoria', ['Consultorias']),
        ('Professional', ['Professional Checklist-Processo']),
        ('Catalog', ['Checklist-Catalog', 'Cronograma Treinamento Catalog'])]:
        for name in names:
            book.Worksheets(name)  # Fail before making any changes if the model differs.
            states[name] = flags[label]
    if flags['Enterprise']:
        book.Worksheets('Processos de Atendimento')
        states['Processos de Atendimento'] = True
    rows = {}
    if flags['Enterprise']:
        plan = book.Worksheets('Plano de Projeto')
        end = int(plan.UsedRange.Row + plan.UsedRange.Rows.Count - 1)
        if not 1 <= end <= 2000:
            raise ValueError('Plano de Projeto fora dos limites do modelo.')
        marker = book.Names('Fim_Det_Etapas').RefersToRange
        if marker.Worksheet.Name != plan.Name:
            raise ValueError('O limite de etapas pertence a outra guia.')
        rows = {r: False for r in range(1, end+1)}
        # Each annotated row has the primary item in M and alternatives in N+.
        # A row stays visible if any reviewed product in that row is selected.
        annotations = plan.Range(f'M1:Z{end}').Value2
        for r, values in enumerate(annotations, 1):
            labels = [str(v).strip() for v in values if v is not None and str(v).strip()]
            if not labels:
                continue
            if any(label not in flags for label in labels):
                raise ValueError('Uma regra de visibilidade do Plano de Projeto não foi reconhecida.')
            rows[r] = not any(flags[label] for label in labels)
        rows[int(marker.Row)] = True
    # Apply only after all model validation has succeeded.
    entry.Visible = -1
    entry.Activate()
    for name, visible in states.items():
        book.Worksheets(name).Visible = -1 if visible else 0
    if rows:
        plan = book.Worksheets('Plano de Projeto')
        plan.Range(f'A1:A{max(rows)}').EntireRow.Hidden = False
        for r, hidden in rows.items():
            if hidden:
                plan.Rows(r).Hidden = True
    return {'sheets': states, 'planRows': rows, 'entry': entry.Name}


def row_xml(raw, states):
    for r, hidden in states.items():
        pattern = rf'<row\b[^>]*\br="{r}"[^>]*>'
        match = re.search(pattern, raw)
        if match:
            tag = re.sub(r'\s+hidden="[^"]*"', '', match[0])
            if hidden:
                tag = tag[:-2]+' hidden="1"/>' if tag.endswith('/>') else tag[:-1]+' hidden="1">'
            raw = raw[:match.start()]+tag+raw[match.end():]
        elif hidden:
            later = next((m for m in re.finditer(r'<row\b[^>]*\br="(\d+)"', raw) if int(m[1]) > int(r)), None)
            at = later.start() if later else raw.find('</sheetData>')
            if at < 0:
                raise ValueError('A estrutura das linhas não foi reconhecida.')
            raw = raw[:at]+f'<row r="{r}" hidden="1"/>'+raw[at:]
    return raw


def workbook_xml(raw, layout):
    index = -1
    entry_index = None
    def patch(match):
        nonlocal index, entry_index
        index += 1
        tag = match[0]
        name = unescape(re.search(r'\bname="([^"]+)"', tag)[1])
        if name == layout['entry']:
            entry_index = index
        if name not in layout['sheets']:
            return tag
        tag = re.sub(r'\s+state="[^"]*"', '', tag)
        if not layout['sheets'][name]:
            tag = tag[:-2]+' state="hidden"/>' if tag.endswith('/>') else tag[:-1]+' state="hidden">'
        return tag
    raw = re.sub(r'<sheet\b[^>]*>', patch, raw)
    if entry_index is None:
        raise ValueError('A guia de entrada não foi encontrada no arquivo original.')
    def view(match):
        tag = re.sub(r'\s+activeTab="[^"]*"', '', match[0])
        return tag[:-2]+f' activeTab="{entry_index}"/>' if tag.endswith('/>') else tag[:-1]+f' activeTab="{entry_index}">'
    return re.sub(r'<workbookView\b[^>]*>', view, raw)


def verify(book, layout):
    for name, visible in layout['sheets'].items():
        if (int(book.Worksheets(name).Visible) == -1) != visible:
            raise ValueError('Não foi possível confirmar as abas atualizadas. O original foi preservado.')
    for r, hidden in layout['planRows'].items():
        if bool(book.Worksheets('Plano de Projeto').Rows(r).Hidden) != hidden:
            raise ValueError('Não foi possível confirmar as etapas atualizadas. O original foi preservado.')
