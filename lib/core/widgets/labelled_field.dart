import 'package:flutter/material.dart';

class _FieldFrame extends StatelessWidget {
  const _FieldFrame({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class LabelledTextField extends StatelessWidget {
  const LabelledTextField({
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.obscureText = false,
    this.initialValue,
    this.controller,
    this.validator,
    super.key,
  });

  final String label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool obscureText;
  final String? initialValue;
  final TextEditingController? controller;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return _FieldFrame(
      label: label,
      child: TextFormField(
        controller: controller,
        initialValue: initialValue,
        validator: validator,
        autovalidateMode: AutovalidateMode.onUserInteractionIfError,
        maxLines: obscureText ? 1 : maxLines,
        keyboardType: keyboardType,
        obscureText: obscureText,
        decoration: InputDecoration(hintText: hint),
      ),
    );
  }
}

class LabelledDropdown extends StatefulWidget {
  const LabelledDropdown({
    required this.label,
    required this.options,
    this.onChanged,
    super.key,
  });

  final String label;
  final List<String> options;
  final ValueChanged<String>? onChanged;

  @override
  State<LabelledDropdown> createState() => _LabelledDropdownState();
}

class _LabelledDropdownState extends State<LabelledDropdown> {
  late String _value = widget.options.first;

  @override
  Widget build(BuildContext context) {
    return _FieldFrame(
      label: widget.label,
      child: DropdownButtonFormField<String>(
        initialValue: _value,
        isExpanded: true,
        items: [
          for (final option in widget.options)
            DropdownMenuItem(
              value: option,
              child: Text(option, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (value) {
          setState(() => _value = value ?? _value);
          widget.onChanged?.call(_value);
        },
      ),
    );
  }
}

/// Validator for required text fields.
String? requiredText(String? value, String message) =>
    (value == null || value.trim().isEmpty) ? message : null;

/// Validator for email fields.
String? emailText(String? value) {
  final email = value?.trim() ?? '';
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
      ? null
      : 'Enter a valid email address';
}
