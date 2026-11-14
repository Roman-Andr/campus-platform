import 'package:campus/src/core/api/api_client.dart';
import 'package:campus/src/core/api/api_failure_message.dart';
import 'package:campus/src/core/l10n/l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _request = RequestOptions(path: '/api/v1/things');

DioException _response(int status, Object? body) => DioException.badResponse(
  statusCode: status,
  requestOptions: _request,
  response: Response(requestOptions: _request, statusCode: status, data: body),
);

Map<String, Object?> _problem(int status, String code) => {
  'type': 'urn:problem:campus:$code',
  'title': 'Internal error',
  'status': status,
  'detail': 'Something went wrong on our side.',
  'code': code,
  'request_id': 'req-123',
};

void main() {
  group('ApiFailure.from', () {
    test('reads Problem Details with field errors', () {
      final failure = ApiFailure.from(
        _response(422, {
          ..._problem(422, 'validation_failed'),
          'errors': [
            {'detail': 'Required.', 'code': 'missing', 'pointer': '#/title'},
          ],
        }),
      );

      expect(failure, isA<ProblemFailure>());
      final problem = failure as ProblemFailure;
      expect(problem.code, ProblemCode.validationFailed);
      expect(problem.status, 422);
      expect(problem.fieldErrors.single.pointer, '#/title');
    });

    test('keeps problem codes unknown to this version', () {
      final failure = ApiFailure.from(
        _response(409, _problem(409, 'sold_out')),
      );

      expect(
        (failure as ProblemFailure).code,
        const ProblemCodeUnknown('sold_out'),
      );
    });

    test('recognizes a required update', () {
      final failure = ApiFailure.from(
        _response(426, {
          ..._problem(426, 'client_update_required'),
          'min_version': '1.2.0',
        }),
      );

      expect(failure, isA<UpdateRequiredFailure>());
      expect((failure as UpdateRequiredFailure).minVersion, '1.2.0');
      expect(
        ApiFailure.from(_response(426, null)),
        isA<UpdateRequiredFailure>(),
      );
    });

    test('treats network errors and timeouts as network failures', () {
      for (final error in [
        DioException.connectionError(requestOptions: _request, reason: ''),
        DioException.connectionTimeout(
          timeout: Duration.zero,
          requestOptions: _request,
        ),
        DioException.receiveTimeout(
          timeout: Duration.zero,
          requestOptions: _request,
        ),
      ]) {
        expect(ApiFailure.from(error), isA<NetworkFailure>());
      }
    });

    test('treats a response without Problem Details as unexpected', () {
      expect(
        ApiFailure.from(_response(502, '<html>Bad gateway</html>')),
        isA<UnexpectedFailure>(),
      );
      expect(
        ApiFailure.from(_response(500, {'code': 42})),
        isA<UnexpectedFailure>(),
      );
      expect(ApiFailure.from(StateError('bug')), isA<UnexpectedFailure>());
    });
  });

  group('apiFailureMessage', () {
    final ru = lookupAppLocalizations(const Locale('ru'));
    final en = lookupAppLocalizations(const Locale('en'));

    String message(AppLocalizations l10n, int status, String code) =>
        apiFailureMessage(l10n, _response(status, _problem(status, code)));

    test('comes from the localization, not from the server', () {
      final text = message(ru, 500, 'internal_error');

      expect(text, ru.errorServer);
      expect(message(en, 500, 'internal_error'), en.errorServer);
      for (final technical in ['internal_error', 'req-123', 'Internal']) {
        expect(text, isNot(contains(technical)));
      }
    });

    test('is specific for known codes', () {
      expect(message(en, 404, 'not_found'), en.errorNotFound);
      expect(message(en, 422, 'validation_failed'), en.errorValidation);
      expect(message(en, 400, 'invalid_cursor'), en.errorListChanged);
      expect(
        message(en, 426, 'client_update_required'),
        en.errorUpdateRequired,
      );
    });

    test('falls back by status for other codes', () {
      expect(message(en, 422, 'idempotency_key_reused'), en.errorRequest);
      expect(message(en, 409, 'sold_out'), en.errorRequest);
      expect(message(en, 503, 'maintenance'), en.errorServer);
    });

    test('explains network and unexpected failures', () {
      expect(apiFailureMessage(en, const NetworkFailure()), en.errorNetwork);
      expect(apiFailureMessage(en, StateError('bug')), en.errorUnexpected);
    });
  });
}
