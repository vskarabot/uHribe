import 'package:flutter/material.dart';

class AuthSwitchLink extends StatelessWidget {
  const AuthSwitchLink({
    super.key,
    required this.prompt,
    required this.action,
    required this.onPressed,
  });

  final String prompt;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: onPressed,
      child: Text.rich(
        TextSpan(
          text: prompt,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
          children: [
            TextSpan(
              text: action,
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                decorationColor: colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
