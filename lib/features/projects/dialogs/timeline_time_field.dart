import 'package:flutter/material.dart';
import 'timeline_schedule.dart';

class TimelineTimeField extends StatefulWidget {
  const TimelineTimeField({super.key, required this.text, required this.duration,
    required this.enabled, required this.onChanged, this.errorText});
  final String text;
  final bool duration, enabled;
  final String? errorText;
  final ValueChanged<String> onChanged;
  @override
  State<TimelineTimeField> createState() => _TimelineTimeFieldState();
}

class _TimelineTimeFieldState extends State<TimelineTimeField> {
  late final controller = TextEditingController(text: widget.text);
  final focus = FocusNode();
  @override
  void initState() { super.initState(); focus.addListener(onFocus); }
  void normalize() {
    final value = timelineTimeInput(controller.text, duration: widget.duration);
    if (value != null) controller.text = timelineClock((value*86400).round());
  }
  void onFocus() { if (!focus.hasFocus) normalize(); }
  @override
  void didUpdateWidget(covariant TimelineTimeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!focus.hasFocus && oldWidget.text != widget.text) controller.text = widget.text;
  }
  @override
  void dispose() { focus.removeListener(onFocus); focus.dispose(); controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => TextFormField(controller:controller, focusNode:focus,
    enabled:widget.enabled, keyboardType:TextInputType.datetime,
    style:const TextStyle(fontSize:12),
    decoration:InputDecoration(isDense:true,contentPadding:const EdgeInsets.all(8),hintText:'HH:MM:SS',errorText:widget.errorText),
    onChanged:widget.onChanged, onEditingComplete:() { normalize(); focus.unfocus(); },
    onTapOutside:(_) => focus.unfocus());
}
