import 'package:flutter/material.dart';
import 'timeline_schedule.dart';

class TimelineBatchDialog extends StatefulWidget {
  const TimelineBatchDialog({super.key, required this.batch, required this.client,
    required this.canPrepare, required this.onPrepare});
  final TimelineCalendarBatch batch;
  final String client;
  final bool Function() canPrepare;
  final VoidCallback onPrepare;
  @override
  State<TimelineBatchDialog> createState() => _TimelineBatchDialogState();
}

class _TimelineBatchDialogState extends State<TimelineBatchDialog> {
  bool acknowledge = false;
  String? error;
  String stamp(DateTime date) => '${timelineDayText(date)} ${timelineClock(date.hour*3600+date.minute*60+date.second)}';
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Agendar todas as etapas'),
    content: SizedBox(width:760, child:SingleChildScrollView(child:Column(
      mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(widget.client,style:const TextStyle(fontWeight:FontWeight.bold)),
        const SizedBox(height:8),
        Text('${widget.batch.valid.length} etapas válidas · ${widget.batch.invalid.length} precisam de ajuste'),
        const SizedBox(height:8),
        const Text('Um único arquivo será preparado com os compromissos abaixo. No Outlook: Calendário → Adicionar calendário → Carregar do arquivo; escolha a agenda e importe. Confira o fuso horário. Esta importação não acompanha alterações posteriores na planilha.'),
        const SizedBox(height:12),
        for (final entry in widget.batch.entries) ListTile(
          contentPadding:EdgeInsets.zero, dense:true,
          leading:Icon(entry.appointment == null ? Icons.warning_amber_outlined : Icons.event_available_outlined),
          title:Text(entry.label),
          subtitle:Text(entry.appointment == null ? 'Não será incluída: confira data, início e duração.'
            : '${stamp(entry.appointment!.start)} → ${stamp(entry.appointment!.end)}\nDuração: ${timelineClock(entry.appointment!.end.difference(entry.appointment!.start).inSeconds)}'),
        ),
        if (widget.batch.invalid.isNotEmpty) CheckboxListTile(
          contentPadding:EdgeInsets.zero, value:acknowledge,
          onChanged:(value)=>setState(()=>acknowledge=value==true),
          title:const Text('Entendi que as etapas com dados inválidos ficarão de fora.')),
        if (error != null) Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      ]))),
    actions:[
      TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancelar')),
      FilledButton(onPressed:widget.batch.valid.isEmpty || widget.batch.invalid.isNotEmpty && !acknowledge ? null : () {
        if (!widget.canPrepare()) { setState(()=>error='Os dados ou a conta mudaram. Feche e confira o cronograma novamente.'); return; }
        try { widget.onPrepare(); Navigator.pop(context); }
        catch (_) { setState(()=>error='Não foi possível preparar o arquivo. Tente novamente e confira as permissões de download.'); }
      }, child:Text('Preparar ${widget.batch.valid.length} etapas')),
    ],
  );
}
