import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Layout of the sign-in steps: a narrow column, scrollable when the
/// keyboard is open.
///
/// The column is built eagerly: a lazy list would dispose a form once it
/// scrolls out of the cache extent, and submitting it would then lose the
/// form state and the entered values.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    required this.title,
    required this.children,
    this.leading,
    this.actions = const [],
    super.key,
  });

  final String title;
  final List<Widget> children;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), leading: leading, actions: actions),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          key: const Key('auth-scroll'),
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 480,
                minHeight: math.max(0.0, constraints.maxHeight - 48),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Why the last action failed; announced by screen readers.
class AuthError extends StatelessWidget {
  const AuthError(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    if (message == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Semantics(
        liveRegion: true,
        child: Text(
          message,
          key: const Key('auth-error'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
    );
  }
}

/// Space between the parts of a sign-in step.
const authGap = SizedBox(height: 16);
