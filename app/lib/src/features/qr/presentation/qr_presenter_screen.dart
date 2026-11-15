import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/time/city_time.dart';
import '../../../core/time/server_clock.dart';
import '../../listings/application/listings.dart';
import '../../listings/application/meeting.dart';
import '../../profile/application/my_profile.dart';
import '../application/qr_messages.dart';
import '../application/qr_providers.dart';
import '../domain/qr_availability.dart';
import '../domain/qr_document.dart';
import '../domain/qr_signing.dart';
import 'meeting_qr_code.dart';

/// Route of the showing side of the online QR confirmation of [action] for
/// [interactionId] of [listingId].
String qrShowPath(
  String listingId,
  String interactionId, {
  QrAction action = QrAction.completion,
}) {
  final base = '/listings/$listingId/interactions/$interactionId/qr';
  return switch (action) {
    QrAction.completion => base,
    QrAction.loanHandover => '$base/handover',
    QrAction.loanReturn => '$base/return',
  };
}

/// The showing side of the online QR confirmation.
///
/// The device signs a version 1 payload with its Ed25519 key and shows it as
/// a QR code. The issue time is the server time, so a wrong device clock does
/// not make the code unusable, and the code is replaced shortly before the
/// server stops accepting it (ТЗ п. 5.1.1, модуль 5, пункт 1). The state of
/// the interaction is always read from the server.
class QrPresenterScreen extends ConsumerStatefulWidget {
  const QrPresenterScreen({
    required this.listingId,
    required this.interactionId,
    this.action = QrAction.completion,
    super.key,
  });

  final String listingId;
  final String interactionId;

  /// The step the shown code confirms; a loan has two of them.
  final QrAction action;

  @override
  ConsumerState<QrPresenterScreen> createState() => _QrPresenterScreenState();
}

class _QrPresenterScreenState extends ConsumerState<QrPresenterScreen>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;
  Timer? _retryTimer;
  bool _started = false;
  bool _busy = false;
  String? _error;
  String? _warning;
  QrSigningKey? _signingKey;
  String? _presenterId;
  QrScanDocument? _document;
  DateTime? _validUntil;

  (String, String) get _ids => (widget.listingId, widget.interactionId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTimers();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A background app misses refresh timers; on return the server clock,
    // the key and the interaction state are read again.
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  void _stopTimers() {
    _refreshTimer?.cancel();
    _retryTimer?.cancel();
  }

  Future<InteractionOutput> _fetchInteraction() {
    final provider = meetingInteractionProvider(_ids);
    ref.invalidate(provider);
    return ref.read(provider.future);
  }

  Future<ListingOutput> _fetchListing() {
    final provider = listingProvider(widget.listingId);
    ref.invalidate(provider);
    return ref.read(provider.future);
  }

  /// Reads the interaction, the server clock and the device key, then signs a
  /// new code. [item] and [listing] are the already loaded screen data; when
  /// omitted both are fetched again.
  Future<void> _load({InteractionOutput? item, ListingOutput? listing}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final currentItem = item ?? await _fetchInteraction();
      final currentListing = listing ?? await _fetchListing();
      if (!mounted) return;
      final state = qrInteractionState(
        currentListing.kind,
        currentItem,
        action: widget.action,
      );
      if (state != QrInteractionState.available) {
        _stopTimers();
        if (mounted) {
          setState(() {
            _document = null;
            _warning = null;
            _error = null;
          });
        }
        return;
      }
      final user = await ref.read(myProfileProvider.future);
      final presenterId = user?.id;
      if (presenterId == null) throw StateError('no signed-in user');
      final sent = clock.now();
      final time = await ref.read(campusApiProvider).serverTime.serverTime();
      final received = clock.now();
      final serverClock = ServerClock.measure(
        deviceSentAt: sent,
        deviceReceivedAt: received,
        serverNow: time.now,
        onlineTtl: Duration(seconds: time.qrOnlineTtl),
      );
      final key = await ref.read(deviceKeyManagerProvider).ensure();
      final issuedAt = serverClock.now();
      final document = await signOnlineQr(
        key: key,
        listingId: currentItem.listingId,
        interactionId: currentItem.id,
        presenterId: presenterId,
        issuedAt: issuedAt,
        nonce: const Uuid().v7(),
      );
      if (!mounted) return;
      _signingKey = key;
      _presenterId = presenterId;
      setState(() {
        _document = document;
        _validUntil = serverClock.validUntilDevice(issuedAt);
        _warning = null;
        _error = null;
      });
      _scheduleRefresh(serverClock, issuedAt);
    } on Object catch (error) {
      if (mounted) _handleFailure(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Replaces the code without reading the interaction again.
  Future<void> _refreshCode() async {
    final key = _signingKey;
    final presenterId = _presenterId;
    if (key == null || presenterId == null) {
      await _load();
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final sent = clock.now();
      final time = await ref.read(campusApiProvider).serverTime.serverTime();
      final received = clock.now();
      final serverClock = ServerClock.measure(
        deviceSentAt: sent,
        deviceReceivedAt: received,
        serverNow: time.now,
        onlineTtl: Duration(seconds: time.qrOnlineTtl),
      );
      final issuedAt = serverClock.now();
      final document = await signOnlineQr(
        key: key,
        listingId: widget.listingId,
        interactionId: widget.interactionId,
        presenterId: presenterId,
        issuedAt: issuedAt,
        nonce: const Uuid().v7(),
      );
      if (!mounted) return;
      setState(() {
        _document = document;
        _validUntil = serverClock.validUntilDevice(issuedAt);
        _warning = null;
        _error = null;
      });
      _scheduleRefresh(serverClock, issuedAt);
    } on Object catch (error) {
      if (mounted) _handleFailure(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _scheduleRefresh(ServerClock serverClock, DateTime issuedAt) {
    _stopTimers();
    final elapsed = serverClock.now().difference(issuedAt);
    final delay = serverClock.onlineTtl - serverClock.refreshLead - elapsed;
    _refreshTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(_refreshCode()),
    );
  }

  /// Keeps the still valid code of a failed refresh and retries a dropped
  /// connection once more; an expired code is removed, never shown as valid.
  void _handleFailure(Object error) {
    _stopTimers();
    final message = qrPresenterFailureMessage(context.l10n, error);
    final validUntil = _validUntil;
    final stillValid =
        _document != null &&
        validUntil != null &&
        clock.now().isBefore(validUntil);
    if (stillValid) {
      setState(() {
        _warning = message;
        _error = null;
      });
      if (ApiFailure.from(error) is NetworkFailure) {
        _retryTimer = Timer(const Duration(seconds: 1), () {
          if (mounted) unawaited(_refreshCode());
        });
      }
    } else {
      setState(() {
        _document = null;
        _warning = null;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final interaction = ref.watch(meetingInteractionProvider(_ids));
    final listing = ref.watch(listingProvider(widget.listingId));
    final cities = ref.watch(citiesProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(_title(l))),
      body: switch ((interaction, listing)) {
        (AsyncData(value: final item), AsyncData(value: final listing)) =>
          _content(l, item, listing, cities),
        (AsyncError(:final error), _) ||
        (_, AsyncError(:final error)) => _loadFailure(l, error),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _content(
    AppLocalizations l,
    InteractionOutput item,
    ListingOutput listing,
    List<CityOut>? cities,
  ) {
    final state = qrInteractionState(listing.kind, item, action: widget.action);
    if (state != QrInteractionState.available) {
      return _terminal(l, state, item, listing, cities);
    }
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_load(item: item, listing: listing));
      });
    }
    final validUntil = _validUntil;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(_intro(l), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        if (_error case final error?)
          Text(
            error,
            key: const Key('qr-presenter-error'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_warning case final warning?)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              warning,
              key: const Key('qr-presenter-warning'),
              textAlign: TextAlign.center,
            ),
          ),
        if (_document case final document?) ...[
          MeetingQrCode(
            key: const Key('qr-presenter-code'),
            document: document,
          ),
          if (validUntil != null) ...[
            const SizedBox(height: 12),
            Text(
              l.qrPresenterValidUntil(
                _cityTime(l, validUntil, listing, cities),
              ),
              key: const Key('qr-presenter-valid-until'),
              textAlign: TextAlign.center,
            ),
          ],
        ] else if (_error == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            key: const Key('qr-presenter-refresh'),
            onPressed: _busy ? null : () => unawaited(_load()),
            icon: const Icon(Icons.refresh),
            label: Text(l.qrPresenterRefresh),
          ),
        ),
      ],
    );
  }

  Widget _terminal(
    AppLocalizations l,
    QrInteractionState state,
    InteractionOutput item,
    ListingOutput listing,
    List<CityOut>? cities,
  ) {
    final completedAt = item.completedAt;
    final loanAction = qrActionIsLoan(widget.action);
    final (title, detail) = switch (state) {
      QrInteractionState.completedWithQr => (
        loanAction ? l.loanQrAlreadyReturned : l.qrPresenterCompleted,
        completedAt == null
            ? null
            : l.qrCompletedAt(_cityTime(l, completedAt, listing, cities)),
      ),
      QrInteractionState.completedOtherwise => (
        l.qrPresenterAlreadyCompleted,
        null,
      ),
      QrInteractionState.notAccepted => (l.qrPresenterNotAccepted, null),
      QrInteractionState.unavailable || QrInteractionState.available => (
        switch (widget.action) {
          QrAction.loanHandover => l.loanQrHandoverUnavailable,
          QrAction.loanReturn => l.loanQrReturnUnavailable,
          QrAction.completion => l.qrPresenterUnavailable,
        },
        null,
      ),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              state == QrInteractionState.completedWithQr
                  ? Icons.verified_outlined
                  : Icons.info_outline,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              key: const Key('qr-presenter-state'),
              textAlign: TextAlign.center,
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(detail, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }

  Widget _loadFailure(AppLocalizations l, Object error) {
    final message = error is MeetingUnavailable
        ? l.qrPresenterNotAccepted
        : qrPresenterFailureMessage(l, error);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              message,
              key: const Key('qr-presenter-load-error'),
              textAlign: TextAlign.center,
            ),
          ),
          TextButton(
            onPressed: () => unawaited(_load()),
            child: Text(l.errorRetry),
          ),
        ],
      ),
    );
  }

  String _title(AppLocalizations l) => switch (widget.action) {
    QrAction.completion => l.qrPresenterTitle,
    QrAction.loanHandover => l.loanQrHandoverPresenterTitle,
    QrAction.loanReturn => l.loanQrReturnPresenterTitle,
  };

  String _intro(AppLocalizations l) => switch (widget.action) {
    QrAction.completion => l.qrPresenterIntro,
    QrAction.loanHandover => l.loanQrHandoverPresenterIntro,
    QrAction.loanReturn => l.loanQrReturnPresenterIntro,
  };

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
