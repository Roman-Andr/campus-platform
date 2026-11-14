import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/settings/application/settings_controller.dart';
import '../auth/auth_session.dart';
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
/// after network failures, status reporting of the final outcome, then
/// [auth] — the access token and its refresh.
Dio createApiDio({
  required ApiConfig config,
  required ClientInfo client,
  required String Function() language,
  required ApiStatusInterceptor status,
  HttpClientAdapter? adapter,
  Interceptor? auth,
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
    ?auth,
  ]);
  return dio;
}

/// Transport of requests; tests override it to answer without a server.
@Riverpod(keepAlive: true)
HttpClientAdapter? apiHttpAdapter(Ref ref) => null;

/// Client of all API calls; it signs requests that need authentication.
@Riverpod(keepAlive: true)
Dio apiDio(Ref ref) {
  final dio = createAppDio(ref, auth: ref.watch(authSessionProvider));
  ref.onDispose(dio.close);
  return dio;
}

/// Client without authentication: refreshes tokens and repeats the
/// request that the expired access token failed.
@Riverpod(keepAlive: true)
Dio authRefreshDio(Ref ref) {
  final dio = createAppDio(ref);
  ref.onDispose(dio.close);
  return dio;
}

/// Builds a client of the app's API configuration.
Dio createAppDio(Ref ref, {Interceptor? auth}) {
  final network = ref.read(networkStatusProvider.notifier);
  final update = ref.read(clientUpdateRequiredProvider.notifier);
  return createApiDio(
    config: ref.watch(apiConfigProvider),
    client: ref.watch(clientInfoProvider),
    language: () => _language(ref),
    status: ApiStatusInterceptor(
      onReachable: network.reachable,
      onUnreachable: network.unreachable,
      onUpdateRequired: update.require,
    ),
    adapter: ref.watch(apiHttpAdapterProvider),
    auth: auth,
  );
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
