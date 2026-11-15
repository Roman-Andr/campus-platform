import 'package:campus/src/core/api/api_failure.dart';
import 'package:campus/src/core/api/generated/campus_api.dart';
import 'package:campus/src/features/privacy/data/privacy_api.dart';
import 'package:campus/src/features/privacy/domain/privacy.dart';

const blockedUserId = '01890a5d-ac96-774b-bcce-b302099a8059';
const secondBlockedUserId = '01890a5d-ac96-774b-bcce-b302099a8061';

BlockedUserOutput blockedUser({
  String id = blockedUserId,
  String firstName = 'Мария',
  String lastName = 'Петрова',
  String accountType = 'student',
  DateTime? blockedAt,
}) => BlockedUserOutput(
  id: id,
  firstName: firstName,
  lastName: lastName,
  accountType: BlockedUserOutputAccountType.fromJson(accountType),
  blockedAt: blockedAt ?? DateTime.utc(2026, 11, 15, 9),
);

ProblemFailure forbidden() => const ProblemFailure(
  Problem(
    type: 'urn:problem:campus:forbidden',
    title: 'Forbidden',
    status: 403,
    code: ProblemCode.forbidden,
  ),
);

/// An in-memory privacy server with controllable failures and key capture.
class FakePrivacyApi implements PrivacyApi {
  MessagePolicy policy = MessagePolicy.all;
  final blocks = <BlockedUserOutput>[];

  /// Items returned by one `listBlocks` call; the default is the server
  /// maximum.
  int pageSize = 100;

  Object? getPolicyError;
  Object? updatePolicyError;

  /// Fails every blacklist page.
  Object? listError;

  /// Fails only a next-page request, so the first page still loads.
  Object? moreListError;
  Object? blockError;
  Object? unblockError;

  /// When set, the response is held until the future completes: used to
  /// deliver an old session's answer after an account switch or to race a
  /// next-page request with an unblock.
  Future<void>? updateGate;
  Future<void>? blockGate;
  Future<void>? unblockGate;
  Future<void>? listGate;
  Future<void>? moreGate;

  final updateCalls = <({MessagePolicy policy, String key})>[];
  final blockCalls = <({String userId, String key})>[];
  final unblockCalls = <({String userId, String key})>[];
  final listCalls = <String?>[];

  @override
  Future<MessagePolicy> getMessagePolicy() async {
    final error = getPolicyError;
    if (error != null) throw error;
    return policy;
  }

  @override
  Future<MessagePolicy> updateMessagePolicy(
    MessagePolicy policy, {
    required String idempotencyKey,
  }) async {
    updateCalls.add((policy: policy, key: idempotencyKey));
    final gate = updateGate;
    if (gate != null) await gate;
    final error = updatePolicyError;
    if (error != null) throw error;
    this.policy = policy;
    return policy;
  }

  @override
  Future<PageBlockedUserOutput> listBlocks({String? cursor}) async {
    listCalls.add(cursor);
    final error = cursor == null ? listError : (moreListError ?? listError);
    final offset = cursor == null ? 0 : int.parse(cursor);
    final end = (offset + pageSize).clamp(0, blocks.length);
    final result = PageBlockedUserOutput(
      items: blocks.sublist(offset, end),
      nextPage: end < blocks.length ? '$end' : null,
    );
    final gate = cursor == null ? listGate : moreGate;
    if (gate != null) await gate;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<BlockedUserOutput> blockUser(
    String userId, {
    required String idempotencyKey,
  }) async {
    blockCalls.add((userId: userId, key: idempotencyKey));
    final gate = blockGate;
    if (gate != null) await gate;
    final error = blockError;
    if (error != null) throw error;
    for (final item in blocks) {
      if (item.id == userId) return item;
    }
    final entry = blockedUser(id: userId);
    blocks.insert(0, entry);
    return entry;
  }

  @override
  Future<void> unblockUser(
    String userId, {
    required String idempotencyKey,
  }) async {
    unblockCalls.add((userId: userId, key: idempotencyKey));
    final gate = unblockGate;
    if (gate != null) await gate;
    final error = unblockError;
    if (error != null) throw error;
    blocks.removeWhere((item) => item.id == userId);
  }
}
