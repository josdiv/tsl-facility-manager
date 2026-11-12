import 'package:flutter/material.dart';

class LinkTextButton extends StatelessWidget {
  const LinkTextButton(this.label, {required this.onPressed, super.key});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      iconAlignment: IconAlignment.end,
      icon: const Icon(Icons.arrow_forward, size: 16),
      label: Text(label),
    );
  }
}
