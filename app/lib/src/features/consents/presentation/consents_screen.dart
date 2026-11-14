import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/api/client_update.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/auth/auth_session.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/api_error_view.dart';
import '../../profile/application/my_profile.dart';
import '../application/consents.dart';
import 'consent_documents.dart';

class ConsentsScreen extends ConsumerStatefulWidget {
  const ConsentsScreen({this.requiredAcceptance = false, super.key});

  final bool requiredAcceptance;

  @override
  ConsumerState<ConsentsScreen> createState() => _ConsentsScreenState();
}

class _ConsentsScreenState extends ConsumerState<ConsentsScreen> {
  bool _accepted = false;
  bool _crossBorder = false;
  bool _busy = false;
  Object? _error;

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error);
        // A newer version may have appeared while this screen was open.
        ref.invalidate(documentsProvider);
        setState(() {
          _accepted = false;
          _crossBorder = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept(List<DocumentOutput> documents) => _perform(() async {
    final api = ref.read(campusApiProvider).consents;
    await api.acceptDocuments(
      body: AcceptanceInput(documentIds: requiredDocumentIds(documents)),
    );
    if (!mounted) return;
    final crossBorder = crossBorderDocument(documents);
    if (_crossBorder && crossBorder != null) {
      await api.changeCrossBorderConsent(
        body: CrossBorderInput(documentId: crossBorder.id, accepted: true),
      );
    }
    if (!mounted) return;
    ref.invalidate(myProfileProvider);
    ref.read(consentGateProvider.notifier).finish(accepted: true);
  });

  Future<void> _change(DocumentOutput document, bool accepted) async {
    if (!accepted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.consentRevokeTitle),
          content: Text(context.l10n.consentRevokeEffects),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.consentCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.consentRevoke),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _perform(() async {
      await ref
          .read(campusApiProvider)
          .consents
          .changeCrossBorderConsent(
            body: CrossBorderInput(documentId: document.id, accepted: accepted),
          );
      if (!mounted) return;
      ref.invalidate(myProfileProvider);
      ref.invalidate(consentStatusProvider);
      await ref.read(consentStatusProvider.future);
    });
  }

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(documentsProvider).asData?.value;
    final crossBorder = documents == null
        ? null
        : crossBorderDocument(documents);
    final status = widget.requiredAcceptance
        ? const AsyncData(false)
        : ref.watch(consentStatusProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.requiredAcceptance,
        title: Text(
          widget.requiredAcceptance
              ? context.l10n.consentUpdateTitle
              : context.l10n.consentDocuments,
        ),
        actions: widget.requiredAcceptance
            ? [
                TextButton(
                  onPressed: () async {
                    final gate = ref.read(consentGateProvider.notifier);
                    await ref.read(authServiceProvider).signOut();
                    gate.finish(accepted: false);
                  },
                  child: Text(context.l10n.signOut),
                ),
              ]
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.requiredAcceptance) Text(context.l10n.consentUpdateIntro),
          const ConsentDocuments(),
          if (widget.requiredAcceptance) ...[
            ConsentCheckboxes(
              requiredAccepted: _accepted,
              crossBorderAccepted: _crossBorder,
              onRequiredChanged: _busy || documents == null
                  ? null
                  : (value) => setState(() => _accepted = value),
              onCrossBorderChanged: _busy || documents == null
                  ? null
                  : (value) => setState(() => _crossBorder = value),
            ),
            FilledButton(
              key: const Key('consent-accept'),
              onPressed:
                  !_busy &&
                      _accepted &&
                      documents != null &&
                      requiredDocumentIds(documents).isNotEmpty
                  ? () => _accept(documents)
                  : null,
              child: Text(context.l10n.consentContinue),
            ),
          ] else if (crossBorder != null) ...[
            if (status.hasError)
              ApiErrorView(
                error: status.error!,
                onRetry: () => ref.invalidate(consentStatusProvider),
              ),
            SwitchListTile(
              key: const Key('consent-transfer-switch'),
              title: Text(context.l10n.consentCrossBorder),
              subtitle: Text(context.l10n.consentCrossBorderEffects),
              value: status.asData?.value ?? false,
              onChanged: _busy || status.asData == null
                  ? null
                  : (value) => _change(crossBorder, value),
            ),
          ],
          if (_error != null) Text(apiFailureMessage(context.l10n, _error!)),
          if (_busy) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

/// Keeps the underlying screen and pending operation alive, hiding all its
/// controls until acceptance. A separate navigator contains document dialogs.
class ConsentGuard extends ConsumerWidget {
  const ConsentGuard({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authStatusProvider, (_, next) {
      if (next.value == AuthenticationStatus.unauthenticated) {
        ref.read(consentGateProvider.notifier).finish(accepted: false);
      }
    });
    final required =
        ref.watch(consentGateProvider) &&
        ref.watch(clientUpdateRequiredProvider) == null;
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: required,
          child: ExcludeFocus(excluding: required, child: child),
        ),
        if (required) const Positioned.fill(child: _ConsentOverlay()),
      ],
    );
  }
}

class _ConsentOverlay extends ConsumerStatefulWidget {
  const _ConsentOverlay();

  @override
  ConsumerState<_ConsentOverlay> createState() => _ConsentOverlayState();
}

class _ConsentOverlayState extends ConsumerState<_ConsentOverlay> {
  final _navigator = GlobalKey<NavigatorState>();
  late final ChildBackButtonDispatcher _back;

  @override
  void initState() {
    super.initState();
    _back = ref
        .read(appRouterProvider)
        .backButtonDispatcher
        .createChildBackButtonDispatcher();
    _back.addCallback(_pop);
    _back.takePriority();
  }

  Future<bool> _pop() async {
    await _navigator.currentState?.maybePop();
    return true;
  }

  @override
  void dispose() {
    _back.removeCallback(_pop);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Navigator(
    key: _navigator,
    onGenerateRoute: (_) => MaterialPageRoute<void>(
      builder: (_) => const PopScope(
        canPop: false,
        child: ConsentsScreen(requiredAcceptance: true),
      ),
    ),
  );
}
