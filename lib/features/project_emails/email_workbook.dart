import 'email_workbook_xml.dart';
import 'email_document.dart';

String _key(String value) {
  var s = value.toLowerCase().trim();
  for (final pair in [
    ('áàãâ', 'a'),
    ('éê', 'e'),
    ('í', 'i'),
    ('óôõ', 'o'),
    ('ú', 'u'),
    ('ç', 'c')
  ]) {
    for (final c in pair.$1.split('')) {
      s = s.replaceAll(c, pair.$2);
    }
  }
  return s.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

class EmailWorkbookData {
  final Map<String, String> fields;
  final List<EmailContact> contacts;
  final List<EmailContact> externalRecipients;
  final List<EmailContact> internalRecipients;
  EmailWorkbookData(this.fields, this.contacts, {this.externalRecipients = const [], this.internalRecipients = const []});
}

int? _recipientRow(List<List<String>> rows, int preferred, List<String> roles, {int labelColumn = 4}) {
  final keys = roles.map(_key).toSet();
  final matches = <int>[];
  for (var i = 0; i < rows.length && i < 80; i++) {
    if (rows[i].length > labelColumn && keys.contains(_key(rows[i][labelColumn]))) matches.add(i + 1);
  }
  if (matches.length == 1) return matches.single;
  if (matches.length > 1) return null;
  // Older layouts without a role label can use the explicit cell contract.
  // A different labeled role must never be treated as the requested person.
  final label = rows.length >= preferred && rows[preferred - 1].length > labelColumn
      ? rows[preferred - 1][labelColumn].trim() : '';
  return label.isEmpty ? preferred : null;
}

List<String> _recipientRoleAliases(String role) => switch (_key(role)) {
  'participante1' => ['Participante 1', 'Participante adicional 01', 'Participante adicional 1'],
  'participante2' => ['Participante 2', 'Participante adicional 02', 'Participante adicional 2'],
  'executivoderelacionamento' => ['Executivo de Relacionamento', 'Exec. de Relacionamento'],
  'executivodevendas' => ['Executivo de Vendas', 'Exec. de Vendas'],
  'liderdoprojeto' => ['Líder do Projeto', 'Líder de Projetos'],
  'coordenadordaimplantacao' => ['Coordenador da Implantação', 'Coordenadora Implantação', 'Coordenador de Implantação'],
  'gestordeservicos' => ['Gestor de Serviços', 'Gestora Serviços'],
  'coordenadordesuporte' => ['Coordenador de Suporte', 'Coordenador Suporte'],
  'liderdeprojetosservicos' => ['Líder de Projetos (Serviços)'],
  _ => [role],
};

List<EmailContact> internalRecipientsFromRows(List<List<String>> rows) {
  String cell(int row, int column) => rows.length >= row && rows[row - 1].length >= column
      ? rows[row - 1][column - 1].trim() : '';
  final seen = <String>{};
  final result = <EmailContact>[];
  for (final entry in [
    (44, 'Coordenador da Implantação'), (43, 'Gestor de Implantação'),
    (39, 'Executivo de Relacionamento'), (38, 'Executivo de Vendas'),
    (41, 'Gestor Regional'), (42, 'Coordenador Regional'),
    (46, 'Gestor de Serviços'), (47, 'Coordenador de Suporte'),
    (48, 'Líder de Projetos (Serviços)'),
  ]) {
    final row = _recipientRow(rows, entry.$1, _recipientRoleAliases(entry.$2));
    if (row == null) continue;
    final email = cell(row, 7);
    if (!validEmail(email) || !seen.add(email.toLowerCase())) continue;
    result.add(EmailContact(role: entry.$2, name: cell(row, 6),
        email: email, group: 'Cyncly', destination: 'Para'));
  }
  return result;
}

List<EmailContact> externalRecipientsFromRows(List<List<String>> rows) {
  String cell(int row, int column) => rows.length >= row && rows[row - 1].length >= column
      ? rows[row - 1][column - 1].trim() : '';
  final seen = <String>{};
  final result = <EmailContact>[];
  for (final entry in [
    (17, 'Proprietário', 'Para'), (18, 'Responsável Técnico', 'Para'),
    (19, 'Participante 1', 'Para'), (20, 'Participante 2', 'Para'),
    (39, 'Executivo de Relacionamento', 'Cc'),
    (38, 'Executivo de Vendas', 'Cc'), (45, 'Líder do Projeto', 'Cc'),
  ]) {
    final row = _recipientRow(rows, entry.$1, _recipientRoleAliases(entry.$2));
    if (row == null) continue;
    final email = cell(row, 7);
    if (!validEmail(email) || !seen.add(email.toLowerCase())) continue;
    result.add(EmailContact(role: entry.$2, name: cell(row, 6), email: email,
        group: entry.$3 == 'Para' ? 'Cliente' : 'Cyncly', destination: entry.$3));
  }
  return result;
}

bool _placeholder(String value) => RegExp(r'#[^#]+#').hasMatch(value);

EmailWorkbookData readEmailWorkbook(List<int> bytes, {bool professionalInternal = false, bool enterpriseInternal = false}) {
  if (bytes.length > 30 * 1024 * 1024) {
    throw const FormatException('A planilha deve ter até 30 MB.');
  }
  return parseEmailWorkbookRows(readEmailEntryRows(bytes),
      professionalInternal: professionalInternal, enterpriseInternal: enterpriseInternal);
}

bool _contactRole(String role) =>
    const {
      'proprietario',
      'responsaveltecnico',
      'consultordeimplantacao',
      'execderelacionamento',
      'executivoderelacionamento',
      'executivodevendas',
      'execdevendas',
      'gestorregional',
      'coordenadorregional',
      'gestordeimplantacao',
      'coordenadoraimplantacao',
      'coordenadordeimplantacao',
      'liderdeprojetos',
      'gestoraservicos',
      'gestordeservicos',
      'coordenadorsuporte',
      'liderdeprojetosservicos',
    }.contains(_key(role)) ||
    RegExp(r'^participanteadicional\d*(?:promob)?$').hasMatch(_key(role));

EmailWorkbookData parseEmailWorkbookRows(List<List<String>> rows, {bool professionalInternal = false, bool enterpriseInternal = false}) {
  if (professionalInternal && enterpriseInternal) {
    throw const FormatException('Selecione somente um modelo de planilha para importar.');
  }
  String labeledCell(int preferred, List<String> labels, int column, {int labelColumn = 4}) {
    final row = _recipientRow(rows, preferred, labels, labelColumn:labelColumn);
    if (row == null || rows.length < row || rows[row-1].length < column) return '';
    final value=rows[row-1][column-1].trim();
    return _placeholder(value) ? '' : value;
  }
  final fields = <String, String>{};
  final contacts = <EmailContact>[];
  const labels = {
    'nomedosistema': 'sistema',
    'nomeresumidodosistema': 'nome_resumido_sistema',
    'id': 'id_sistema',
    'nsparainstalacao': 'ns',
    'versaorevisao': 'versao',
    'assinaturadaproposta': 'assinatura_proposta',
    'iddabiblioteca': 'biblioteca',
    'cnpj': 'cnpj',
    'razaosocial': 'razao_social',
    'nomefantasia': 'nome_fantasia',
    'telefone01': 'telefone_cliente',
    'telefone02': 'telefone_cliente_secundario',
    'emaildeacessoaoportal': 'email_portal',
    'ie': 'ie',
    'cep': 'cep',
    'estado': 'estado',
    'cidade': 'cidade',
    'bairro': 'bairro',
    'rua': 'rua',
    'endereco': 'rua',
    'complemento': 'complemento',
    'numero': 'numero',
    'sitedeacesso': 'site_prices',
    'prices': 'id_prices',
    'usuarioprices': 'usuario_prices',
    'proprietario': 'proprietario',
    'responsaveltecnico': 'responsavel_tecnico',
    'emailresponsaveltecnico': 'email_tecnico',
    'consultordeimplantacao': 'consultor',
    'execderelacionamento': 'er',
    'executivoderelacionamento': 'er',
    'emaildoconsultor': 'email_consultor',
    'telefonedoconsultor': 'telefone_consultor',
    'materiaisdaimplantacao': 'materiais',
    'sistemadocliente': 'liberacao',
    'iniciodoprojetopelaconsultoria': 'data_recebimento',
    'encerramentodoprojeto': 'data_finalizacao',
    'dataderecebimento': 'data_recebimento',
    'datadefinalizacao': 'data_finalizacao',
    'datadaprimeirareuniao': 'data_reuniao',
    'horariodareuniao': 'hora_reuniao',
    'resumodaimplantacao': 'resumo',
    'senhadoconfiguradordedimensoes': 'senha_dimensoes',
    'senhadosorcamentos': 'senha_orcamentos',
    'senhadasmargens': 'senha_margens',
  };
  String? section;
  bool prices = false;
  String valueAfter(List<String> row, int index) {
    final end = index < 4 ? 4 : index + 4;
    for (var next = index + 1; next < row.length && next < end; next++) {
      final value = row[next].trim();
      if (value.isEmpty) continue;
      if (next > index + 1 &&
          (labels.containsKey(_key(value)) ||
              _contactRole(value) ||
              const {
                'cliente',
                'cyncly',
                'datas',
                'biblioteca',
                'senhas',
                'diretorios',
                'informacoescomerciais',
                'acessoaoprices'
              }.contains(_key(value)))) {
        return '';
      }
      return value;
    }
    return '';
  }

  for (final row in rows) {
    if (row.any((v) => _key(v) == 'acessoaoprices')) prices = true;
    if (row.any((v) =>
        ['cliente', 'cyncly', 'informacoescomerciais'].contains(_key(v)))) {
      prices = false;
    }
    if (row.any((v) => _key(v) == 'cliente') && !row.any(validEmail)) {
      section = 'Cliente';
    }
    if (row.any((v) => _key(v) == 'cyncly')) section = 'Cyncly';
    if (row.any(
        (v) => ['informacoescomerciais', 'acessoaoprices'].contains(_key(v)))) {
      section = null;
    }
    if (section != null) {
      for (var i = 0; i + 1 < row.length; i++) {
        final role = row[i].trim(), name = row[i + 1].trim();
        if (!_contactRole(role) || name.isEmpty || _placeholder(name)) continue;
        final address = i + 2 < row.length ? row[i + 2].trim() : '';
        // Names without an email still belong to the team, but start excluded
        // from recipients. Selecting them requires a valid email before export.
        if (validEmail(address)) continue;
        if (!contacts.any(
            (c) => c.group == section && c.role == role && c.name == name)) {
          contacts.add(EmailContact(role: role, name: name, group: section));
        }
        if (_key(role) == 'consultordeimplantacao' && i + 3 < row.length) {
          final phone = row[i + 3].trim();
          if (phone.isNotEmpty && !_placeholder(phone)) {
            fields['telefone_consultor'] = phone;
          }
        }
      }
    }
    for (var i = 0; i < row.length; i++) {
      final field = prices && _key(row[i]) == 'senha'
          ? 'senha_prices'
          : labels[_key(row[i])];
      if (field != null && i + 1 < row.length) {
        final value = valueAfter(row, i);
        if (value.isNotEmpty && !_placeholder(value)) fields[field] = value;
      }
      if (section != null && i >= 2 && validEmail(row[i])) {
        final role = row[i - 2].trim(),
            name = row[i - 1].trim(),
            email = row[i].trim();
        if (role.isEmpty ||
            name.isEmpty ||
            name.contains('#') ||
            role.contains('#')) {
          continue;
        }
        if (contacts.any((c) =>
            _key(c.role) == _key(role) &&
            c.group == section &&
            c.email.toLowerCase() == email.toLowerCase())) {
          continue;
        }
        contacts.add(
            EmailContact(role: role, name: name, email: email, group: section));
        if (section == 'Cliente' && _key(role) == 'proprietario') {
          fields['proprietario'] = name;
          fields['email_cliente'] = email;
          if (i + 1 < row.length &&
              row[i + 1].trim().isNotEmpty &&
              !row[i + 1].contains('#')) {
            fields['telefone_cliente'] = row[i + 1].trim();
          }
          if (i + 2 < row.length &&
              row[i + 2].trim().isNotEmpty &&
              !_placeholder(row[i + 2])) {
            fields['cpf_proprietario'] = row[i + 2].trim();
          }
        }
        if (section == 'Cliente' && _key(role) == 'responsaveltecnico') {
          fields['responsavel_tecnico'] = name;
          fields['email_tecnico'] = email;
          if (i + 1 < row.length &&
              row[i + 1].trim().isNotEmpty &&
              !_placeholder(row[i + 1])) {
            fields['telefone_tecnico'] = row[i + 1].trim();
          }
          if (i + 2 < row.length &&
              row[i + 2].trim().isNotEmpty &&
              !_placeholder(row[i + 2])) {
            fields['cpf_tecnico'] = row[i + 2].trim();
          }
        }
        if (section == 'Cyncly' && _key(role) == 'consultordeimplantacao') {
          fields['consultor'] = name;
          fields['email_consultor'] = email;
          if (i + 1 < row.length &&
              row[i + 1].trim().isNotEmpty &&
              !_placeholder(row[i + 1])) {
            fields['telefone_consultor'] = row[i + 1].trim();
          }
        }
        if (section == 'Cyncly' &&
            ['execderelacionamento', 'executivoderelacionamento']
                .contains(_key(role))) {
          fields['er'] = name;
          fields['email_er'] = email;
        }
      }
    }
  }
  if (professionalInternal) {
    String cell(int row, int column) {
      if (rows.length < row || rows[row - 1].length < column) return '';
      final value = rows[row - 1][column - 1].trim();
      return _placeholder(value) ? '' : value;
    }
    // This model has an explicit cell contract; never substitute a nearby label.
    fields.addAll({
      'sistema': labeledCell(27, ['Nome do sistema'], 3, labelColumn:1),
      'data_recebimento': labeledCell(23, ['Início do projeto pela Consultoria','Data de recebimento'], 3, labelColumn:1),
      'data_finalizacao': labeledCell(24, ['Encerramento do projeto','Data de finalização'], 3, labelColumn:1),
      'razao_social': labeledCell(24, ['Razão Social'], 6),
      'proprietario': labeledCell(18, ['Proprietário'], 6),
      'email_cliente': labeledCell(18, ['Proprietário'], 7),
      'telefone_cliente': labeledCell(18, ['Proprietário'], 8),
      'responsavel_tecnico': labeledCell(19, ['Responsável Técnico'], 6),
      'email_tecnico': labeledCell(19, ['Responsável Técnico'], 7),
      'er': labeledCell(38, _recipientRoleAliases('Executivo de Relacionamento'), 6),
      'email_er': labeledCell(38, _recipientRoleAliases('Executivo de Relacionamento'), 7),
    });
    for (final contact in [
      EmailContact(role: 'Proprietário', name: fields['proprietario']!,
          email: fields['email_cliente']!, group: 'Cliente'),
      EmailContact(role: 'Exec. de Relacionamento', name: fields['er']!,
          email: fields['email_er']!, group: 'Cyncly'),
    ]) {
      if (validEmail(contact.email) && !contacts.any((c) =>
          c.email.trim().toLowerCase() == contact.email.trim().toLowerCase())) {
        contacts.add(contact);
      }
    }
  }
  if (enterpriseInternal) {
    String cell(int row, int column) {
      if (rows.length < row || rows[row - 1].length < column) return '';
      final value = rows[row - 1][column - 1].trim();
      return _placeholder(value) ? '' : value;
    }
    fields.addAll({
      'sistema': labeledCell(27, ['Nome do sistema'], 3, labelColumn:1),
      'data_recebimento': labeledCell(23, ['Início do projeto pela Consultoria','Data de recebimento'], 3, labelColumn:1),
      'data_finalizacao': labeledCell(24, ['Encerramento do projeto','Data de finalização'], 3, labelColumn:1), 'materiais': cell(39, 3),
      'liberacao': cell(40, 3), 'biblioteca': cell(29, 3),
      'senha_dimensoes': cell(35, 3), 'senha_orcamentos': cell(36, 3),
      'senha_margens': cell(37, 3), 'cnpj': labeledCell(24, ['CNPJ'], 6),
      'razao_social': labeledCell(23, ['Razão Social'], 6), 'nome_fantasia': labeledCell(26, ['Nome Fantasia'], 6),
      'proprietario': labeledCell(18, ['Proprietário'], 6), 'email_cliente': labeledCell(18, ['Proprietário'], 7),
      'telefone_cliente': labeledCell(18, ['Proprietário'], 8), 'responsavel_tecnico': labeledCell(19, ['Responsável Técnico'], 6),
      'email_tecnico': labeledCell(19, ['Responsável Técnico'], 7), 'email_consultor': cell(37, 7),
      'email_er': cell(39, 7),
    });
    const team = [
      ('consultor', 'Consultor de Implantação', 37),
      ('executivo_vendas', 'Executivo de Vendas', 38),
      ('er', 'Exec. de Relacionamento', 39),
      ('gestor_regional', 'Gestor Regional', 41),
      ('coordenador_regional', 'Coordenador Regional', 42),
      ('gestor_implantacao', 'Gestor de Implantação', 43),
      ('coordenadora_implantacao', 'Coordenadora Implantação', 44),
      ('lider_projetos', 'Líder de Projetos', 45),
      ('gestora_servicos', 'Gestora Serviços', 46),
      ('coordenador_suporte', 'Coordenador Suporte', 47),
      ('lider_projetos_servicos', 'Líder de Projetos (serviços)', 48),
    ];
    final entries = <EmailContact>[
      EmailContact(role: 'Proprietário', name: fields['proprietario']!,
          email: fields['email_cliente']!, group: 'Cliente'),
      EmailContact(role: 'Responsável Técnico', name: fields['responsavel_tecnico']!,
          email: fields['email_tecnico']!, group: 'Cliente'),
    ];
    for (final member in team) {
      final row = _recipientRow(rows, member.$3, _recipientRoleAliases(member.$2));
      fields[member.$1] = row == null ? '' : cell(row, 6);
      final email = row == null ? '' : cell(row, 7);
      if (member.$1 == 'consultor') {
        fields['email_consultor'] = email;
        fields['telefone_consultor'] = emailConsultantPhone(email, row == null ? '' : cell(row, 8));
      }
      if (member.$1 == 'er') fields['email_er'] = email;
      entries.add(EmailContact(role: member.$2, name: fields[member.$1]!,
          email: email, group: 'Cyncly'));
    }
    for (final contact in entries) {
      if (validEmail(contact.email) && !contacts.any((c) =>
          c.email.trim().toLowerCase() == contact.email.trim().toLowerCase())) {
        contacts.add(contact);
      }
    }
  }
  if (contacts.isEmpty && fields.isEmpty) {
    throw const FormatException(
        'Não foram encontrados contatos válidos nas seções CLIENTE ou CYNCLY. Você pode cadastrá-los manualmente.');
  }
  return EmailWorkbookData(fields, contacts, externalRecipients: externalRecipientsFromRows(rows),
      internalRecipients: internalRecipientsFromRows(rows));
}
