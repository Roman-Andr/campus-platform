import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/settings/application/settings_controller.dart';
import '../l10n/l10n.dart';
import 'api_config.dart';
import 'client_info.dart';
import 'client_update.dart';
import 'generated/campus_api.dart';
import 'interceptors.dart';
import 'network_status.dart';

export 'api_failure.dart';
export 'generated/campus_api.dart';

part 'api_client.g.dart';

/// Builds the HTTP client shared by all API calls.
///
/// Interceptors run in order: client headers, idempotency key, repeats
/// after network failures, then status reporting of the final outcome.
Dio createApiDio({
  required ApiConfig config,
  required ClientInfo client,
  required String Function() language,
  required ApiStatusInterceptor status,
  HttpClientAdapter? adapter,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: config.baseUrl.toString(),
      connectTimeout: config.connectTimeout,
      receiveTimeout: config.receiveTimeout,
    ),
  );
  if (adapter != null) dio.httpClientAdapter = adapter;
  dio.interceptors.addAll([
    ClientHeadersInterceptor(client, language),
    IdempotencyKeyInterceptor(),
    retryInterceptor(dio, config.retryDelays),
    status,
  ]);
  return dio;
}

/// Transport of requests; tests override it to answer without a server.
@Riverpod(keepAlive: true)
HttpClientAdapter? apiHttpAdapter(Ref ref) => null;

@Riverpod(keepAlive: true)
Dio apiDio(Ref ref) {
  final network = ref.read(networkStatusProvider.notifier);
  final update = ref.read(clientUpdateRequiredProvider.notifier);
  final dio = createApiDio(
    config: ref.watch(apiConfigProvider),
    client: ref.watch(clientInfoProvider),
    language: () => _language(ref),
    status: ApiStatusInterceptor(
      onReachable: network.reachable,
      onUnreachable: network.unreachable,
      onUpdateRequired: update.require,
    ),
    adapter: ref.watch(apiHttpAdapterProvider),
  );
  ref.onDispose(dio.close);
  return dio;
}

/// Generated client of the Campus API.
@Riverpod(keepAlive: true)
CampusApi campusApi(Ref ref) => CampusApi(ref.watch(apiDioProvider));

/// Language of the interface as the app resolves it: the chosen one, or
/// the device language when supported, otherwise English.
String _language(Ref ref) {
  final chosen = ref.read(settingsControllerProvider).value?.language.locale;
  final locale =
      chosen ??
      basicLocaleListResolution(
        WidgetsBinding.instance.platformDispatcher.locales,
        AppLocalizations.supportedLocales,
      );
  return locale.languageCode;
}
