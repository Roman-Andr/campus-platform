import 'package:material_ui/material_ui.dart' hide Visibility;

import '../../../core/api/api_client.dart';

/// Kinds of entries the feed can be filtered by (ТЗ п. 5.1.5).
enum FeedKind {
  giveaway('giveaway'),
  skill('skill'),
  publication('publication'),
  event('event'),
  help('help');

  const FeedKind(this.apiValue);

  /// Value of the `kind` query parameter.
  final String apiValue;

  /// The kind behind an API value; unknown kinds are not filtered.
  static FeedKind? fromApi(String? value) {
    for (final kind in values) {
      if (kind.apiValue == value) return kind;
    }
    return null;
  }
}

/// Feed filters chosen by the user; kept on this device between runs.
@immutable
class FeedFilters {
  const FeedFilters({this.kind, this.categoryId, this.dormitoryId});

  /// No filters: every visible entry.
  static const none = FeedFilters();

  final FeedKind? kind;
  final String? categoryId;
  final String? dormitoryId;

  bool get isEmpty => kind == null && categoryId == null && dormitoryId == null;

  FeedFilters withKind(FeedKind? value) => FeedFilters(
    kind: value,
    categoryId: categoryId,
    dormitoryId: dormitoryId,
  );

  FeedFilters withCategory(String? value) =>
      FeedFilters(kind: kind, categoryId: value, dormitoryId: dormitoryId);

  FeedFilters withDormitory(String? value) =>
      FeedFilters(kind: kind, categoryId: categoryId, dormitoryId: value);

  /// Suffix of the local cache key; every filter set has its own snapshot.
  String get cacheKey => [
    if (kind != null) 'kind=${kind!.apiValue}',
    if (categoryId != null) 'category=$categoryId',
    if (dormitoryId != null) 'dormitory=$dormitoryId',
  ].join('&');

  Map<String, Object?> toJson() => {
    if (kind != null) 'kind': kind!.apiValue,
    if (categoryId != null) 'category_id': categoryId,
    if (dormitoryId != null) 'dormitory_id': dormitoryId,
  };

  /// Reads stored filters; unknown or malformed values are ignored.
  factory FeedFilters.fromJson(Object? json) {
    if (json is! Map) return none;
    final kind = json['kind'];
    final categoryId = json['category_id'];
    final dormitoryId = json['dormitory_id'];
    return FeedFilters(
      kind: kind is String ? FeedKind.fromApi(kind) : null,
      categoryId: categoryId is String && categoryId.isNotEmpty
          ? categoryId
          : null,
      dormitoryId: dormitoryId is String && dormitoryId.isNotEmpty
          ? dormitoryId
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FeedFilters &&
      other.kind == kind &&
      other.categoryId == categoryId &&
      other.dormitoryId == dormitoryId;

  @override
  int get hashCode => Object.hash(kind, categoryId, dormitoryId);
}

/// Local cache key of a feed. The plain area keeps snapshots written by
/// versions without filters.
String feedCacheKey(Visibility area, FeedFilters filters) =>
    filters.isEmpty ? area.toJson() : '${area.toJson()}|${filters.cacheKey}';

/// Whether the pin of [item] is still active at [now].
bool isPinnedAt(ListingOutput item, DateTime now) =>
    item.pinnedUntil?.isAfter(now) ?? false;

/// Pinned entries first, in server order, then the ordinary chronology.
({List<ListingOutput> pinned, List<ListingOutput> ordinary}) splitPinned(
  Iterable<ListingOutput> items,
  DateTime now,
) {
  final pinned = <ListingOutput>[];
  final ordinary = <ListingOutput>[];
  for (final item in items) {
    (isPinnedAt(item, now) ? pinned : ordinary).add(item);
  }
  return (pinned: pinned, ordinary: ordinary);
}

/// Isolates search snapshots from the ordinary feed and other queries.
String searchCacheKey(Visibility area, FeedFilters filters, String query) =>
    query.isEmpty
    ? feedCacheKey(area, filters)
    : '${feedCacheKey(area, filters)}|q=${Uri.encodeComponent(query)}';
