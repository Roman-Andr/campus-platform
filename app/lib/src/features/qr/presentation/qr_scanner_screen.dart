import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/interceptors.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/time/city_time.dart';
import '../../listings/application/listings.dart';
import '../../listings/application/meeting.dart';
import '../../profile/application/my_profile.dart';
import '../application/qr_messages.dart';
import '../domain/qr_availability.dart';
import '../domain/qr_document.dart';
import 'qr_camera.dart';
import 'qr_presenter_screen.dart' show qrShowPath;

/// Route of the scanning side of the online QR confirmation of [action] for
/// [interactionId] of [listingId].
String qrScanPath(
  String listingId,
  String interactionId, {
  QrAction action = QrAction.completion,
}) => '${qrShowPath(listingId, interactionId, action: action)}/scan';

/// The steps of one scan.
enum _ScanPhase { loading, scanning, sending, success, failure }

/// The scanning side of the online QR confirmation.
///
/// A scanned code is sent to the server with an `Idempotency-Key` that is
/// kept while the same code is retried, so a lost response is confirmed once,
/// never twice. The result is always the server answer; a network failure
/// shows an error and retries the same request (ТЗ п. 5.1.1, модуль 5,
/// пункт 1).
class QrScannerScreen extends ConsumerStatefulWidget {
  const QrScannerScreen({
    required this.listingId,
    required this.interactionId,
    this.action = QrAction.completion,
    super.key,
  });

  final String listingId;
  final String interactionId;

  /// The step the scanned code confirms; a loan has two of them.
  final QrAction action;

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen>
    with WidgetsBindingObserver {
  _ScanPhase _phase = _ScanPhase.loading;
  QrScanDocument? _document;
  String? _idempotencyKey;
  QrScanOutput? _result;
  QrScanProblem? _problem;
  String? _error;
  bool _retryable = false;

  (String, String) get _ids => (widget.listingId, widget.interactionId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The other participant may have scanned while this screen was in the
    // background; on return the authoritative interaction state is read.
    if (state == AppLifecycleState.resumed &&
        (_phase == _ScanPhase.scanning || _phase == _ScanPhase.loading)) {
      ref.invalidate(meetingInteractionProvider(_ids));
      ref.invalidate(listingProvider(widget.listingId));
    }
  }

  Future<void> _reload() async {
    final interaction = meetingInteractionProvider(_ids);
    final listing = listingProvider(widget.listingId);
    ref
      ..invalidate(interaction)
      ..invalidate(listing);
    try {
      await Future.wait([
        ref.read(interaction.future),
        ref.read(listing.future),
      ]);
    } on Object {
      // The provider states carry the failure; the screen shows it.
    }
  }

  void _onScanned(String raw) {
    if (_phase != _ScanPhase.scanning) return;
    final me = ref.read(myProfileProvider).value?.id;
    final scanned = readScannedQr(
      raw,
      listingId: widget.listingId,
      interactionId: widget.interactionId,
      viewerId: me,
    );
    switch (scanned) {
      case RejectedQr(:final problem):
        setState(() {
          _phase = _ScanPhase.failure;
          _problem = problem;
          _retryable = false;
          _error = qrScanProblemMessage(context.l10n, problem);
        });
      case UsableQr(:final document):
        setState(() {
          _phase = _ScanPhase.sending;
          _document = document;
          _idempotencyKey = const Uuid().v7();
          _problem = null;
          _error = null;
          _retryable = false;
        });
        unawaited(_send());
    }
  }

  Future<void> _send() async {
    final document = _document;
    final idempotencyKey = _idempotencyKey;
    if (document == null || idempotencyKey == null) return;
    try {
      final api = ref.read(campusApiProvider).qr;
      final body = QrScanInput(
        payload: document.payload,
        signature: document.signature,
      );
      final options = Options(headers: {idempotencyKeyHeader: idempotencyKey});
      final result = switch (widget.action) {
        QrAction.completion => await api.scanQr(
          listingId: widget.listingId,
          interactionId: widget.interactionId,
          body: body,
          options: options,
        ),
        QrAction.loanHandover => await api.handOverLoan(
          listingId: widget.listingId,
          interactionId: widget.interactionId,
          body: body,
          options: options,
        ),
        QrAction.loanReturn => await api.returnLoan(
          listingId: widget.listingId,
          interactionId: widget.interactionId,
          body: body,
          options: options,
        ),
      };
      if (!mounted) return;
      setState(() {
        _phase = _ScanPhase.success;
        _result = result;
        _error = null;
      });
      refreshInteractionLists(ref);
      ref.invalidate(meetingInteractionProvider(_ids));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _ScanPhase.failure;
        _problem = null;
        _retryable = ApiFailure.from(error) is NetworkFailure;
        _error = qrScanFailureMessage(context.l10n, error);
      });
    }
  }

  void _retry() {
    setState(() {
      _phase = _ScanPhase.sending;
      _error = null;
    });
    unawaited(_send());
  }

  void _scanAgain() {
    setState(() {
      _phase = _ScanPhase.scanning;
      _document = null;
      _idempotencyKey = null;
      _result = null;
      _problem = null;
      _error = null;
      _retryable = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final interaction = ref.watch(meetingInteractionProvider(_ids));
    final listing = ref.watch(listingProvider(widget.listingId));
    final cities = ref.watch(citiesProvider).value;
    final Widget body;
    if (_phase == _ScanPhase.success && _result != null) {
      body = _success(l, _result!, listing.value, cities);
    } else if (_phase == _ScanPhase.failure) {
      body = _failure(l);
    } else {
      body = switch ((interaction, listing)) {
        (AsyncData(value: final item), AsyncData(value: final listing)) =>
          _content(l, item, listing, cities),
        (AsyncError(:final error), _) ||
        (_, AsyncError(:final error)) => _loadFailure(l, error),
        _ => const Center(child: CircularProgressIndicator()),
      };
    }
    return Scaffold(
      appBar: AppBar(title: Text(_title(l))),
      body: body,
    );
  }

  Widget _content(
    AppLocalizations l,
    InteractionOutput item,
    ListingOutput listing,
    List<CityOut>? cities,
  ) {
    switch (qrInteractionState(listing.kind, item, action: widget.action)) {
      case QrInteractionState.available:
        return _available(l);
      case QrInteractionState.completedWithQr:
        return _completed(l, item, listing, cities);
      case QrInteractionState.completedOtherwise:
        return _message(l.qrScannerAlreadyCompleted);
      case QrInteractionState.notAccepted:
        return _message(l.qrScannerNotAccepted);
      case QrInteractionState.unavailable:
        return _message(switch (widget.action) {
          QrAction.loanHandover => l.loanQrHandoverUnavailable,
          QrAction.loanReturn => l.loanQrReturnUnavailable,
          QrAction.completion => l.qrScannerUnavailable,
        });
    }
  }

  Widget _available(AppLocalizations l) {
    if (_phase == _ScanPhase.sending) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              l.qrScannerSending,
              key: const Key('qr-scanner-sending'),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    if (_phase == _ScanPhase.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _phase == _ScanPhase.loading) {
          setState(() => _phase = _ScanPhase.scanning);
        }
      });
      return const Center(child: CircularProgressIndicator());
    }
    final camera = ref.watch(qrCameraBuilderProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_intro(l), textAlign: TextAlign.center),
        ),
        Expanded(
          child: KeyedSubtree(
            key: const Key('qr-scanner-camera'),
            child: camera(context, _onScanned),
          ),
        ),
      ],
    );
  }

  Widget _completed(
    AppLocalizations l,
    InteractionOutput item,
    ListingOutput listing,
    List<CityOut>? cities,
  ) {
    final completedAt = item.completedAt;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              qrActionIsLoan(widget.action)
                  ? l.loanQrAlreadyReturned
                  : l.qrScannerAlreadyConfirmed,
              key: const Key('qr-scanner-completed'),
              textAlign: TextAlign.center,
            ),
            if (completedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                l.qrCompletedAt(_cityTime(l, completedAt, listing, cities)),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _success(
    AppLocalizations l,
    QrScanOutput result,
    ListingOutput? listing,
    List<CityOut>? cities,
  ) {
    final completedAt = result.completedAt;
    final returnDueAt = result.returnDueAt;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              switch (widget.action) {
                QrAction.completion => l.qrScannerSuccess,
                QrAction.loanHandover => l.loanQrHandoverDone,
                QrAction.loanReturn => l.loanQrReturnDone,
              },
              key: const Key('qr-scanner-success'),
              textAlign: TextAlign.center,
            ),
            if (returnDueAt != null && listing != null) ...[
              const SizedBox(height: 8),
              Text(
                l.loanReturnDue(_cityTime(l, returnDueAt, listing, cities)),
                key: const Key('qr-scanner-return-due'),
                textAlign: TextAlign.center,
              ),
            ],
            if (completedAt != null && listing != null) ...[
              const SizedBox(height: 8),
              Text(
                l.qrCompletedAt(_cityTime(l, completedAt, listing, cities)),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('qr-scanner-done'),
              onPressed: () => context.pop(),
              child: Text(l.qrDone),
            ),
          ],
        ),
      ),
    );
  }

  String _title(AppLocalizations l) => switch (widget.action) {
    QrAction.completion => l.qrScannerTitle,
    QrAction.loanHandover => l.loanQrHandoverScanTitle,
    QrAction.loanReturn => l.loanQrReturnScanTitle,
  };

  String _intro(AppLocalizations l) => switch (widget.action) {
    QrAction.completion => l.qrScannerIntro,
    QrAction.loanHandover => l.loanQrHandoverScanIntro,
    QrAction.loanReturn => l.loanQrReturnScanIntro,
  };

  Widget _failure(AppLocalizations l) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 40,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            _error ?? l.errorUnexpected,
            key: const Key('qr-scanner-error'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (_problem == null && _retryable)
            FilledButton(
              key: const Key('qr-scanner-retry'),
              onPressed: _retry,
              child: Text(l.errorRetry),
            ),
          TextButton(
            key: const Key('qr-scanner-again'),
            onPressed: _scanAgain,
            child: Text(l.qrScannerScanAgain),
          ),
        ],
      ),
    ),
  );

  Widget _message(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, size: 40),
          const SizedBox(height: 12),
          Text(
            message,
            key: const Key('qr-scanner-state'),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  Widget _loadFailure(AppLocalizations l, Object error) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            qrScanFailureMessage(l, error),
            key: const Key('qr-scanner-load-error'),
            textAlign: TextAlign.center,
          ),
        ),
        TextButton(
          onPressed: () => unawaited(_reload()),
          child: Text(l.errorRetry),
        ),
      ],
    ),
  );

  String _cityTime(
    AppLocalizations l,
    DateTime instant,
    ListingOutput listing,
    List<CityOut>? cities,
  ) {
    final city =
        cities?.where((city) => city.id == listing.cityId).firstOrNull?.name ??
        listing.cityTimezone;
    return formatCityTime(
      instant,
      timezone: listing.cityTimezone,
      city: city,
      l10n: l,
      includeDate: true,
    );
  }
}
