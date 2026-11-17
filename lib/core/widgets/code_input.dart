import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// A one-time code entered into a single field and drawn as separate boxes.
///
/// One field rather than one per digit, so pasting the code from an email,
/// Android's code autofill and fast typing all work.
class CodeInput extends StatefulWidget {
  const CodeInput({
    required this.controller,
    this.length = 6,
    this.onCompleted,
    this.onChanged,
    this.autofocus = true,
    this.hasError = false,
    super.key,
  });

  final TextEditingController controller;
  final int length;

  /// Called once all digits are in.
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool hasError;

  @override
  State<CodeInput> createState() => _CodeInputState();
}

class _CodeInputState extends State<CodeInput> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focus.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final code = widget.controller.text;
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: 'Verification code, ${widget.length} digits',
      child: Stack(
        children: [
          Row(
            children: [
              for (var i = 0; i < widget.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        width: _isCurrent(i, code) ? 2 : 1,
                        color: widget.hasError
                            ? AppColors.danger
                            : _isCurrent(i, code)
                            ? AppColors.primary
                            : AppColors.fieldBorder,
                      ),
                    ),
                    child: Text(
                      i < code.length ? code[i] : '',
                      style: text.titleLarge,
                    ),
                  ),
                ),
              ],
            ],
          ),
          // The real field: invisible, covering the boxes, so taps, the
          // keyboard and paste all go to it.
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                autofocus: widget.autofocus,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(widget.length),
                ],
                showCursor: false,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  counterText: '',
                ),
                onChanged: (value) {
                  widget.onChanged?.call(value);
                  if (value.length == widget.length) {
                    widget.onCompleted?.call(value);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isCurrent(int index, String code) =>
      _focus.hasFocus &&
      index == (code.length < widget.length ? code.length : widget.length - 1);
}
