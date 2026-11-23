import 'package:flutter/material.dart';

/// Keeps the quick choices while allowing an exact percentage in Excel units.
Widget checklistPercentageField({
  required BuildContext context,
  Key? key,
  double? initialValue,
  bool isExpanded = false,
  required InputDecoration decoration,
  Widget? hint,
  required List<DropdownMenuItem<double>> items,
  required ValueChanged<double?>? onChanged,
  required bool Function() canApply,
}) {
  return ChecklistPercentageInput(
    key: key,
    initialValue: initialValue,
    decoration: decoration,
    hint: hint,
    items: items,
    onChanged: onChanged,
    canApply: canApply,
  );
}

class ChecklistPercentageInput extends StatefulWidget {
  const ChecklistPercentageInput(
      {super.key,
      this.initialValue,
      required this.decoration,
      this.hint,
      required this.items,
      required this.onChanged,
      required this.canApply});
  final double? initialValue;
  final InputDecoration decoration;
  final Widget? hint;
  final List<DropdownMenuItem<double>> items;
  final ValueChanged<double?>? onChanged;
  final bool Function() canApply;
  @override
  State<ChecklistPercentageInput> createState() =>
      _ChecklistPercentageInputState();
}

class _ChecklistPercentageInputState extends State<ChecklistPercentageInput> {
  late final TextEditingController controller;
  final focus = FocusNode();
  String? error;
  String format(double? value) => value == null
      ? ''
      : '${(value * 100).toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '').replaceAll('.', ',')}%';
  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: format(widget.initialValue));
    focus.addListener(onFocus);
  }

  @override
  void didUpdateWidget(covariant ChecklistPercentageInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue && !focus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || focus.hasFocus) return;
        controller.text = format(widget.initialValue);
        if (error != null) setState(() => error = null);
      });
    }
  }

  void onFocus() {
    if (!focus.hasFocus) commit();
  }

  double? parse(String text) =>
      double.tryParse(text.trim().replaceAll('%', '').replaceAll(',', '.'));
  String? validate(String? text) {
    if ((text ?? '').isEmpty && widget.initialValue == null) return null;
    final value = parse(text ?? '');
    return value == null || !value.isFinite || value < 0 || value > 100
        ? 'Use 0 a 100'
        : null;
  }

  void edit(String text) {
    final value = parse(text);
    setState(() => error = validate(text));
    if (error == null &&
        value != null &&
        widget.canApply() &&
        value / 100 != widget.initialValue) {
      widget.onChanged?.call(value / 100);
    }
  }

  void commit() {
    if (widget.onChanged == null || !widget.canApply()) return;
    final value = double.tryParse(
        controller.text.trim().replaceAll('%', '').replaceAll(',', '.'));
    if (value == null || !value.isFinite || value < 0 || value > 100) {
      setState(() => error = 'Use 0 a 100');
      return;
    }
    setState(() => error = null);
    controller.text = format(value / 100);
    if (value / 100 != widget.initialValue) widget.onChanged!(value / 100);
  }

  void choose(double value) {
    controller.text = format(value);
    setState(() => error = null);
    widget.onChanged?.call(value);
  }

  @override
  void dispose() {
    focus.removeListener(onFocus);
    focus.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        focusNode: focus,
        enabled: widget.onChanged != null,
        validator: validate,
        onChanged: edit,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        onTap: () => controller.selection =
            TextSelection(baseOffset: 0, extentOffset: controller.text.length),
        onFieldSubmitted: (_) => commit(),
        onTapOutside: (_) => focus.unfocus(),
        decoration: widget.decoration.copyWith(
          hintText: widget.initialValue == null ? 'Variados' : null,
          errorText: error,
          suffixIconConstraints:
              const BoxConstraints(minWidth: 32, minHeight: 40),
          suffixIcon: PopupMenuButton<double>(
            tooltip: 'Percentuais rápidos',
            enabled: widget.onChanged != null,
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.arrow_drop_down, size: 20),
            onSelected: (value) {
              if (widget.canApply()) choose(value);
            },
            itemBuilder: (_) => [
              for (final item in widget.items)
                if (item.value != null &&
                    const [0, .25, .5, .75, 1].contains(item.value))
                  PopupMenuItem(
                      value: item.value,
                      enabled: item.enabled,
                      child: item.child)
            ],
          ),
        ),
      );
}
