import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/interceptors.dart';
import '../domain/privacy.dart';

part 'privacy_api.g.dart';

/// Profile privacy operations used by the application layer.
///
/// Every mutating call takes an explicit idempotency key: the caller keeps
/// it while retrying the same operation, so a repeat after a dropped
/// connection is applied once.
abstract interface class PrivacyApi {
  Future<MessagePolicy> getMessagePolicy();

  Future<MessagePolicy> updateMessagePolicy(
    MessagePolicy policy, {
    required String idempotencyKey,
  });

  Future<PageBlockedUserOutput> listBlocks({String? cursor});

  Future<BlockedUserOutput> blockUser(
    String userId, {
    required String idempotencyKey,
  });

  Future<void> unblockUser(String userId, {required String idempotencyKey});
}

/// [PrivacyApi] over the generated OpenAPI client of the server.
class GeneratedPrivacyApi implements PrivacyApi {
  GeneratedPrivacyApi(this._api);

  final CampusApi _api;

  ProfileClient get _profile => _api.profile;

  @override
  Future<MessagePolicy> getMessagePolicy() async =>
      messagePolicyOf((await _profile.getMessagePolicy()).policy);

  @override
  Future<MessagePolicy> updateMessagePolicy(
    MessagePolicy policy, {
    required String idempotencyKey,
  }) async => messagePolicyOf(
    (await _profile.updateMessagePolicy(
      body: MessagePolicyInput(policy: messagePolicyInput(policy)),
      options: Options(headers: {idempotencyKeyHeader: idempotencyKey}),
    )).policy,
  );

  @override
  Future<PageBlockedUserOutput> listBlocks({String? cursor}) =>
      _profile.listBlocks(cursor: cursor, size: 100);

  @override
  Future<BlockedUserOutput> blockUser(
    String userId, {
    required String idempotencyKey,
  }) => _profile.blockUser(
    body: BlockInput(userId: userId),
    options: Options(headers: {idempotencyKeyHeader: idempotencyKey}),
  );

  @override
  Future<void> unblockUser(String userId, {required String idempotencyKey}) =>
      _profile.unblockUser(
        blockedId: userId,
        options: Options(headers: {idempotencyKeyHeader: idempotencyKey}),
      );
}

@Riverpod(keepAlive: true)
PrivacyApi privacyApi(Ref ref) =>
    GeneratedPrivacyApi(ref.watch(campusApiProvider));
