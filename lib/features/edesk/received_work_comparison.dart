import '../../domain/models/project_model.dart';

class ReceivedInventory {
  const ReceivedInventory({this.active = const [], this.completed = const []});
  final List<ProjectModel> active, completed;
}

class ReceivedComparison {
  const ReceivedComparison(this.state, this.message);
  final String state, message;
  bool get missing => state == 'missingProject' || state == 'missingWork';
  String get label => switch (state) {
        'missingProject' || 'missingWork' => 'Falta no sistema',
        'requestRegistered' => 'Solicitação cadastrada',
        'requestCompleted' => 'Solicitação finalizada',
        'registered' => 'Já cadastrado',
        'completed' => 'Finalizado no sistema',
        _ => 'Precisa conferir',
      };
}

ReceivedComparison compareReceivedWork(
    Map<String, dynamic> row, ReceivedInventory inventory) {
  final request = row['solicitacao']?.toString().trim() ?? '';
  final work = row['idTrabalho']?.toString().trim() ?? '';
  bool numeric(String value) =>
      RegExp(r'^\d+$').hasMatch(value) && int.tryParse(value) != 0;
  Map<String, Set<String>> index(List<ProjectModel> projects) {
    final result = <String, Set<String>>{};
    for (final project in projects) {
      final numbers = result.putIfAbsent(project.id.trim(), () => <String>{});
      if (numeric(project.id2.trim())) numbers.add(project.id2.trim());
      for (final task in project.subTasks ?? <TaskModel>[]) {
        final taskRequest = task.edeskSolicitacao?.trim();
        final target =
            taskRequest?.isNotEmpty == true ? taskRequest! : project.id.trim();
        final ids = result.putIfAbsent(target, () => <String>{});
        if (numeric(task.edeskWorkNumber)) ids.add(task.edeskWorkNumber);
      }
    }
    return result;
  }

  final active = index(inventory.active),
      completed = index(inventory.completed);
  if (numeric(work) &&
      active[request]?.contains(work) == true &&
      completed[request]?.contains(work) == true) {
    return const ReceivedComparison('review',
        'O vínculo aparece em projetos ativos e finalizados. Confira os cadastros.');
  }
  if (numeric(work) && active[request]?.contains(work) == true) {
    return const ReceivedComparison('registered',
        'Solicitação e número do trabalho encontrados no sistema.');
  }
  if (numeric(work) && completed[request]?.contains(work) == true) {
    return const ReceivedComparison(
        'completed', 'Este trabalho já está em um projeto finalizado.');
  }
  if (!numeric(work) &&
      completed.containsKey(request) &&
      !active.containsKey(request)) {
    return const ReceivedComparison('requestCompleted',
        'A solicitação já tem um projeto finalizado no sistema.');
  }
  if (completed.containsKey(request)) {
    return const ReceivedComparison('review',
        'A solicitação tem projeto finalizado. Confira o vínculo antes de importar.');
  }
  if (!active.containsKey(request)) {
    return const ReceivedComparison(
        'missingProject', 'Solicitação ainda não cadastrada no sistema.');
  }
  if (!numeric(work)) {
    return const ReceivedComparison('requestRegistered',
        'A solicitação já está cadastrada. A grid não exibe os números dos trabalhos; confira as etapas se necessário.');
  }
  if (active[request]!.isEmpty) {
    return const ReceivedComparison('review',
        'O projeto existe, mas suas etapas não têm números vinculados ao E-Desk.');
  }
  return const ReceivedComparison('missingWork',
      'O projeto já existe, mas este número de trabalho ainda não está cadastrado.');
}
