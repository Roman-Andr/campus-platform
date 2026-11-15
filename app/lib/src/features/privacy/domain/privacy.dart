import '../../../core/api/generated/campus_api.dart';

/// Who may start a personal dialog with the signed-in user.
enum MessagePolicy {
  /// Any student or employee may write.
  all,

  /// Only users who share a listing or a started interaction may write.
  related,
}

/// Reads a policy returned by the profile or privacy endpoint.
MessagePolicy messagePolicyOf(MessagePolicyOutputPolicy policy) =>
    policy.toJson() == MessagePolicy.related.name
    ? MessagePolicy.related
    : MessagePolicy.all;

/// Reads the policy embedded in the signed-in user's profile.
MessagePolicy userMessagePolicyOf(UserOutputMessagePolicy policy) =>
    policy.toJson() == MessagePolicy.related.name
    ? MessagePolicy.related
    : MessagePolicy.all;

/// The request body value for [policy].
MessagePolicyInputPolicy messagePolicyInput(MessagePolicy policy) =>
    switch (policy) {
      MessagePolicy.all => MessagePolicyInputPolicy.all,
      MessagePolicy.related => MessagePolicyInputPolicy.related,
    };

/// One page of the blacklist and its cursor.
class BlockedUsersState {
  const BlockedUsersState({
    this.items = const [],
    this.nextPage,
    this.loadingMore = false,
    this.moreError,
  });

  final List<BlockedUserOutput> items;

  /// Cursor of the next page; null on the last page.
  final String? nextPage;

  /// A request for the next page is in flight.
  final bool loadingMore;

  /// The last next-page request failed; the loaded items stay and the caller
  /// offers a retry instead of an endless spinner.
  final Object? moreError;

  bool contains(String userId) => items.any((item) => item.id == userId);
}

/// Merges pages or a stored block into one blacklist, newest first.
List<BlockedUserOutput> mergeBlockedUsers(
  Iterable<BlockedUserOutput> first,
  Iterable<BlockedUserOutput> second,
) {
  final byId = <String, BlockedUserOutput>{
    for (final item in [...first, ...second]) item.id: item,
  };
  return byId.values.toList()..sort((a, b) {
    final byTime = b.blockedAt.compareTo(a.blockedAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
}
