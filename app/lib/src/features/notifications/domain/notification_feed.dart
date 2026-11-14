import '../../../core/api/generated/campus_api.dart';

/// The loaded pages of the inbox and the cursor of the next one.
class NotificationFeedState {
  const NotificationFeedState({
    this.items = const <NotificationOutput>[],
    this.nextPage,
    this.unreadCount = 0,
  });

  /// Notifications, newest first: by `sequence`, not by event time.
  final List<NotificationOutput> items;

  /// Cursor of the next page; null on the last one.
  final String? nextPage;

  /// Unread notifications of the user, counted by the server over the whole
  /// inbox.
  ///
  /// The server flags every notification against its monotone read cursor,
  /// so the count comes from the server after every reload and matches
  /// other devices of the user even when the inbox has more pages than the
  /// loaded ones.
  final int unreadCount;
}

/// Combines [loaded] and [next] without repeats, newest first.
///
/// Read is monotone on the server: a notification reported as read by
/// either copy stays read, so a page fetched before marking it read cannot
/// make it unread again.
List<NotificationOutput> mergeNotifications(
  Iterable<NotificationOutput> loaded,
  Iterable<NotificationOutput> next,
) {
  final byId = <String, NotificationOutput>{};
  for (final row in [...loaded, ...next]) {
    final existing = byId[row.id];
    byId[row.id] = existing == null
        ? row
        : (existing.read ? withRead(row, read: true) : row);
  }
  return byId.values.toList()..sort((a, b) => b.sequence.compareTo(a.sequence));
}

/// Marks the notifications up to [sequence] read, as the read cursor of the
/// server does: this notification and earlier ones.
List<NotificationOutput> applyReadCursor(
  Iterable<NotificationOutput> items,
  int sequence,
) => [
  for (final row in items)
    row.sequence <= sequence && !row.read ? withRead(row, read: true) : row,
];

/// A copy of [row] with another read flag.
NotificationOutput withRead(NotificationOutput row, {required bool read}) =>
    NotificationOutput(
      id: row.id,
      sequence: row.sequence,
      type: row.type,
      objectId: row.objectId,
      occurredAt: row.occurredAt,
      createdAt: row.createdAt,
      text: row.text,
      params: row.params,
      read: read,
      additionalProperties: row.additionalProperties,
    );

/// The text of [notification] for [languageCode].
///
/// The delivery stage stores the message in every supported locale, so the
/// client picks its language instead of translating the notification type.
/// A missing translation falls back to English and then to any stored one.
String notificationText(NotificationOutput notification, String languageCode) {
  final language = languageCode.split('-').first;
  final text = notification.text;
  return text[language] ??
      text['en'] ??
      (text.isEmpty ? '' : text.values.first);
}
