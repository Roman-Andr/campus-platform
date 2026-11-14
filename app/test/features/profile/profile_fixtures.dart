import 'dart:typed_data';

import 'package:campus/src/core/photos/photo_upload.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../../helpers/fake_api.dart';

const storageUrl = 'https://storage.test/campus-private';

Map<String, Object?> tagJson(String code, String name) => {
  'id': 'tag-$code',
  'code': code,
  'name': name,
};

Map<String, Object?> photoJson(String id) => {
  'id': id,
  'url': 'https://storage.test/photos/$id/photo?sig=1',
  'preview_url': 'https://storage.test/photos/$id/preview?sig=1',
  'expires_at': '2030-01-01T00:00:00Z',
};

Map<String, Object?> fileJson(String id, String status, {String? reason}) => {
  'id': id,
  'purpose': 'listing_photo',
  'status': status,
  'size': 3,
  'rejection_reason': reason,
  'expires_at': '2030-01-01T00:00:00Z',
};

/// The server side of the photo upload flow (#45) and of the profile photo;
/// the uploaded file ends with [status].
ResponseBody? photoFlow(
  RequestOptions options,
  FakeHttpAdapter server, {
  String status = 'ready',
  String fileId = 'file-new',
}) => switch ((options.method, options.path)) {
  ('POST', '/api/v1/files/photo-uploads') => jsonBody(201, {
    'file': fileJson(fileId, 'pending'),
    'url': storageUrl,
    'fields': {'key': 'photos/$fileId/source', 'policy': 'p'},
    'expires_at': '2030-01-01T00:00:00Z',
  }),
  ('POST', storageUrl) => jsonBody(204, null),
  ('POST', final path) when path == '/api/v1/files/$fileId/complete' =>
    jsonBody(202, fileJson(fileId, 'processing')),
  ('GET', final path) when path == '/api/v1/files/$fileId' => jsonBody(
    200,
    fileJson(
      fileId,
      status,
      reason: status == 'rejected' ? 'invalid_image' : null,
    ),
  ),
  ('PUT', '/api/v1/me/photo') => () {
    final id = SentRequest(options).json['file_id']! as String;
    server.photo = photoJson(id);
    return jsonBody(200, server.photo);
  }(),
  ('DELETE', '/api/v1/me/photo') => () {
    server.photo = null;
    return jsonBody(204, null);
  }(),
  _ => null,
};

/// Picks prepared files instead of showing the platform UI.
class FakePhotoPicker implements PhotoPicker {
  FakePhotoPicker([Uint8List? bytes, this.hasCamera = false])
    : bytes = bytes ?? Uint8List.fromList([1, 2, 3]);

  Uint8List bytes;

  @override
  final bool hasCamera;

  var picks = 0;

  XFile _file() => XFile.fromData(bytes, name: 'me.jpg');

  @override
  Future<List<XFile>> gallery({required int limit}) async {
    picks++;
    return [_file()];
  }

  @override
  Future<XFile?> camera() async {
    picks++;
    return _file();
  }
}

/// Photo parameters for tests: no waiting between status checks.
const testPhotoConfig = PhotoConfig(
  maxBytes: 1024 * 1024,
  listingLimit: 10,
  pollInterval: Duration.zero,
  processingTimeout: Duration(seconds: 5),
);
