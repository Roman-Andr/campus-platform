import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/generated/campus_api.dart';
import '../data/chat_api.dart';

part 'chat_search.g.dart';

/// What the search screen should show for the current query.
enum ChatSearchPhase { idle, loading, ready, error }

/// Results of a full-text search across the user's own dialogs.
class ChatSearchState {
  const ChatSearchState({
    this.query = '',
    this.phase = ChatSearchPhase.idle,
    this.results = const <ChatSearchResult>[],
    this.nextPage,
    this.error,
    this.moreError,
  });

  /// Normalized query, without surrounding whitespace.
  final String query;

  final ChatSearchPhase phase;

  /// Hits ordered by server relevance; an empty list on the last page.
  final List<ChatSearchResult> results;

  /// Cursor of the next page; null on the last page.
  final String? nextPage;

  /// Failure of the first page; the query is kept so retry is explicit.
  final Object? error;

  /// Failure of a next page; older results stay visible.
  final Object? moreError;

  bool get hasMore => nextPage != null;
}

/// Search over the dialogs of the signed-in user.
///
/// The server checks membership on every request, so a stale result can
/// exist only in the UI: opening it rechecks access through the normal chat
/// history call. A query is sent only after the screen's debounce, and a
/// response of an older query never replaces a newer one. The provider is
/// disposed with the search screen, so results of one account never leak
/// into the next session.
@Riverpod()
class ChatSearch extends _$ChatSearch {
  int _generation = 0;
  bool _loadingMore = false;

  @override
  ChatSearchState build() => const ChatSearchState();

  Future<void> search(String raw) async {
    final query = raw.trim();
    final generation = ++_generation;
    _loadingMore = false;
    if (query.isEmpty) {
      state = const ChatSearchState();
      return;
    }
    state = ChatSearchState(query: query, phase: ChatSearchPhase.loading);
    try {
      final page = await ref.read(chatApiProvider).searchChats(query: query);
      if (!_isCurrent(generation)) return;
      state = ChatSearchState(
        query: query,
        phase: ChatSearchPhase.ready,
        results: page.items,
        nextPage: page.nextPage,
      );
    } on Object catch (error) {
      if (!_isCurrent(generation)) return;
      state = ChatSearchState(
        query: query,
        phase: ChatSearchPhase.error,
        error: error,
      );
    }
  }

  Future<void> retry() => search(state.query);

  Future<void> more() async {
    final current = state;
    final cursor = current.nextPage;
    final generation = _generation;
    if (_loadingMore ||
        current.phase != ChatSearchPhase.ready ||
        cursor == null) {
      return;
    }
    _loadingMore = true;
    try {
      final page = await ref
          .read(chatApiProvider)
          .searchChats(query: current.query, cursor: cursor);
      if (!_isCurrent(generation)) return;
      final byId = <String, ChatSearchResult>{
        for (final result in [...current.results, ...page.items])
          result.message.id: result,
      };
      state = ChatSearchState(
        query: current.query,
        phase: ChatSearchPhase.ready,
        results: byId.values.toList(),
        nextPage: page.nextPage,
      );
    } on Object catch (error) {
      if (!_isCurrent(generation)) return;
      state = ChatSearchState(
        query: current.query,
        phase: ChatSearchPhase.ready,
        results: current.results,
        nextPage: cursor,
        moreError: error,
      );
    } finally {
      if (_generation == generation) _loadingMore = false;
    }
  }

  void clear() {
    _generation++;
    state = const ChatSearchState();
  }

  bool _isCurrent(int generation) => ref.mounted && _generation == generation;
}
