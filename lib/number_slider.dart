import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps the numeric editor focused while the live canvas updates.
class NumberSlider extends StatefulWidget {
  final String label, suffix;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  const NumberSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.suffix = '',
  });
  @override
  State<NumberSlider> createState() => _NumberSliderState();
}

class _NumberSliderState extends State<NumberSlider> {
  late final controller = TextEditingController(
    text: widget.value.round().toString(),
  );
  final focus = FocusNode();
  @override
  void didUpdateWidget(covariant NumberSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!focus.hasFocus) controller.text = widget.value.round().toString();
  }

  void commit(String text) {
    final value = double.tryParse(text);
    if (value != null && value.isFinite) {
      final clamped = value.clamp(widget.min, widget.max);
      widget.onChanged(clamped);
      controller.text = clamped.round().toString();
    } else {
      controller.text = widget.value.round().toString();
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.label, style: const TextStyle(fontSize: 13)),
            ),
            SizedBox(
              width: 85,
              height: 36,
              child: Semantics(
                label: widget.label,
                child: TextField(
                  key: ValueKey('number-${widget.label}'),
                  controller: controller,
                  focusNode: focus,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]')),
                  ],
                  decoration: InputDecoration(
                    suffixText: widget.suffix,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (text) {
                    final value = double.tryParse(text);
                    if (value != null &&
                        value.isFinite &&
                        value >= widget.min &&
                        value <= widget.max) {
                      widget.onChanged(value);
                    }
                  },
                  onSubmitted: commit,
                  onTapOutside: (_) {
                    commit(controller.text);
                    focus.unfocus();
                  },
                ),
              ),
            ),
          ],
        ),
        SizedBox(
          height: 28,
          child: Slider(
            semanticFormatterCallback: (value) =>
                '${value.round()} ${widget.suffix}',
            value: widget.value.clamp(widget.min, widget.max),
            min: widget.min,
            max: widget.max,
            onChanged: (value) {
              focus.unfocus();
              controller.text = value.round().toString();
              widget.onChanged(value);
            },
          ),
        ),
      ],
    ),
  );
  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }
}
