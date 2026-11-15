import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../data/chat_api.dart';

part 'chat_message_photos.g.dart';

/// Signed short-lived links of the ready photos of one visible message.
///
/// The links are never stored: the API issues new ones on every read, and
/// an expired link is replaced by watching the provider again. A message
/// that was deleted in the meantime no longer has photos, so the request
/// fails with the same not-found problem as the history.
@riverpod
Future<List<ChatPhotoOutput>> chatMessagePhotos(
  Ref ref,
  String chatId,
  String messageId,
) async {
  final cancel = CancelToken();
  ref.onDispose(cancel.cancel);
  final photos = await ref
      .read(chatApiProvider)
      .listMessagePhotos(chatId, messageId, cancel: cancel);
  return photos.items;
}
