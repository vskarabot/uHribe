import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../theme.dart';

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.autofillHints,
    this.validator,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final Iterable<String>? autofillHints;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return ShadowedField(
      child: TextFormField(
        controller: widget.controller,
        obscureText: !_visible,
        autofillHints: widget.autofillHints,
        decoration: InputDecoration(
          labelText: widget.label,
          suffixIcon: IconButton(
            tooltip: _visible ? Strings.hidePassword : Strings.showPassword,
            icon: Icon(_visible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _visible = !_visible),
          ),
        ),
        validator: widget.validator,
        onFieldSubmitted: widget.onSubmitted,
      ),
    );
  }
}
