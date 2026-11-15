import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/features/qr/domain/qr_availability.dart';
import 'package:campus/src/features/qr/presentation/qr_camera.dart';
import 'package:campus/src/features/qr/presentation/qr_presenter_screen.dart';
import 'package:campus/src/features/qr/presentation/qr_scanner_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _listing = '01890a5d-ac96-774b-bcce-b302099a8080';
const _interaction = '01890a5d-ac96-774b-bcce-b302099a8081';

InteractionOutput interaction({
  InteractionStatus status = InteractionStatus.accepted,
  String? stage,
  String? completionMethod,
}) => InteractionOutput.fromJson({
  'id': _interaction,
  'listing_id': _listing,
  'participant_name': 'Boris',
  'participant_id': '01890a5d-ac96-774b-bcce-b302099a8082',
  'status': status.toJson(),
  'stage': stage,
  'response_due_at': null,
  'executor': false,
  'meeting': null,
  'completion_method': completionMethod,
});

void main() {
  group('the generic confirmation', () {
    test('is offered for an accepted interaction without stages', () {
      for (final kind in ['giveaway', 'exchange', 'skill', 'help']) {
        expect(
          qrInteractionState(kind, interaction()),
          QrInteractionState.available,
        );
      }
    });

    test('is refused for a kind with another workflow', () {
      for (final kind in ['loan', 'publication', 'event', 'purchase']) {
        expect(
          qrInteractionState(kind, interaction()),
          QrInteractionState.unavailable,
        );
      }
    });

    test('is refused once the interaction left the plain step', () {
      expect(
        qrInteractionState('giveaway', interaction(stage: 'issued')),
        QrInteractionState.unavailable,
      );
    });

    test('is not accepted while the interaction waits', () {
      expect(
        qrInteractionState(
          'giveaway',
          interaction(status: InteractionStatus.pending),
        ),
        QrInteractionState.notAccepted,
      );
    });

    test('tells a completion of the two outcomes apart', () {
      expect(
        qrInteractionState(
          'giveaway',
          interaction(
            status: InteractionStatus.completed,
            completionMethod: 'qr',
          ),
        ),
        QrInteractionState.completedWithQr,
      );
      expect(
        qrInteractionState(
          'giveaway',
          interaction(
            status: InteractionStatus.completed,
            completionMethod: 'no_meeting',
          ),
        ),
        QrInteractionState.completedOtherwise,
      );
    });
  });

  group('the loan actions', () {
    test('the handover is offered until it is confirmed', () {
      expect(
        qrInteractionState(
          'loan',
          interaction(),
          action: QrAction.loanHandover,
        ),
        QrInteractionState.available,
      );
      expect(
        qrInteractionState(
          'loan',
          interaction(stage: 'issued'),
          action: QrAction.loanHandover,
        ),
        QrInteractionState.unavailable,
      );
    });

    test('the return is offered only after the handover', () {
      expect(
        qrInteractionState('loan', interaction(), action: QrAction.loanReturn),
        QrInteractionState.unavailable,
      );
      expect(
        qrInteractionState(
          'loan',
          interaction(stage: 'issued'),
          action: QrAction.loanReturn,
        ),
        QrInteractionState.available,
      );
    });

    test('a completed loan is completed and never available again', () {
      final completed = interaction(
        status: InteractionStatus.completed,
        stage: 'issued',
        completionMethod: 'qr',
      );
      for (final action in QrAction.values) {
        expect(
          qrInteractionState('loan', completed, action: action),
          QrInteractionState.completedWithQr,
        );
      }
    });

    test('a loan action on another kind is refused', () {
      expect(
        qrInteractionState(
          'giveaway',
          interaction(stage: 'issued'),
          action: QrAction.loanReturn,
        ),
        QrInteractionState.unavailable,
      );
    });

    test('loan actions are marked as such', () {
      expect(qrActionIsLoan(QrAction.completion), isFalse);
      expect(qrActionIsLoan(QrAction.loanHandover), isTrue);
      expect(qrActionIsLoan(QrAction.loanReturn), isTrue);
    });
  });

  group('routes', () {
    test('the plain confirmation keeps its paths', () {
      expect(
        qrShowPath(_listing, _interaction),
        '/listings/$_listing/interactions/$_interaction/qr',
      );
      expect(
        qrScanPath(_listing, _interaction),
        '/listings/$_listing/interactions/$_interaction/qr/scan',
      );
    });

    test('each loan action has its own pair of paths', () {
      expect(
        qrShowPath(_listing, _interaction, action: QrAction.loanHandover),
        '/listings/$_listing/interactions/$_interaction/qr/handover',
      );
      expect(
        qrScanPath(_listing, _interaction, action: QrAction.loanHandover),
        '/listings/$_listing/interactions/$_interaction/qr/handover/scan',
      );
      expect(
        qrShowPath(_listing, _interaction, action: QrAction.loanReturn),
        '/listings/$_listing/interactions/$_interaction/qr/return',
      );
      expect(
        qrScanPath(_listing, _interaction, action: QrAction.loanReturn),
        '/listings/$_listing/interactions/$_interaction/qr/return/scan',
      );
    });
  });

  group('camera support', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('mobile platforms scan codes', () {
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ]) {
        expect(qrCameraSupported(platform), isTrue, reason: '$platform');
      }
    });

    test('desktop platforms have no scanner and explain it', () {
      for (final platform in [
        TargetPlatform.linux,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        expect(qrCameraSupported(platform), isFalse, reason: '$platform');
      }
    });
  });
}
