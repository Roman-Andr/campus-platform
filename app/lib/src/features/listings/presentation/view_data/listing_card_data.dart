import 'package:material_ui/material_ui.dart';

import '../../../../core/design_system/patterns/metadata.dart';

/// This feature owns mapping API/domain data into display-only fields.
@immutable
class ListingCardData {
  const ListingCardData({
    required this.title,
    required this.author,
    required this.status,
    this.summary,
    this.scope,
    this.photo,
  });
  final String title;
  final String? summary;
  final AuthorViewData author;
  final StatusViewData status;
  final String? scope;

  /// The caller chooses a local/cache/network image adapter; UI does no I/O.
  final Widget? photo;
}
