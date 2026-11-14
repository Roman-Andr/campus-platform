import 'dart:typed_data';

import 'package:campus/src/core/photos/photo_upload.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/test_app.dart';

const storageUrl = 'https://storage.test/campus-private';

Map<String, Object?> fileJson(
  String id, {
  String status = 'pending',
  String? reason,
}) => {
  'id': id,
  'purpose': 'listing_photo',
  'status': status,
  'size': 0,
  'rejection_reason': reason,
  'expires_at': '2026-11-15T00:00:00Z',
};

Map<String, Object?> photoJson(String id) => {
  'id': id,
  'url': 'https://storage.test/photo/$id?sig=1',
  'preview_url': 'https://storage.test/preview/$id?sig=1',
  'expires_at': '2999-01-01T00:00:00Z',
};

/// A photo server: every upload gets the next id from [ids]; its final
/// status comes from [verdicts] (`ready` by default). A `null` verdict
/// drops the connection to the storage instead.
class PhotoServer {
  PhotoServer({this.verdicts = const {}});
  final Map<String, Object?> verdicts;
  var _uploads = 0;
  final storagePosts = <RequestOptions>[];
  final attached = <List<String>>[];

  ResponseBody? handle(RequestOptions options) {
    final path = options.path;
    if (path.endsWith('/token/refresh')) return jsonBody(200, tokensJson(1));
    if (path == '/api/v1/files/photo-uploads') {
      final id = 'file-${++_uploads}';
      return jsonBody(201, {
        'file': fileJson(id),
        'url': storageUrl,
        'fields': {'key': 'photos/$id/source', 'policy': 'signed'},
        'expires_at': '2026-11-15T00:00:00Z',
      });
    }
    if (path == storageUrl) {
      final key = (options.data! as FormData).fields.first.value;
      final id = key.split('/')[1];
      if (verdicts.containsKey(id) && verdicts[id] == null) {
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'reset',
        );
      }
      storagePosts.add(options);
      return ResponseBody.fromString('', 204);
    }
    final complete = RegExp(r'^/api/v1/files/([^/]+)/complete$');
    if (complete.firstMatch(path) case final match?) {
      return jsonBody(202, fileJson(match[1]!, status: 'processing'));
    }
    final status = RegExp(r'^/api/v1/files/([^/]+)$');
    if (status.firstMatch(path) case final match?) {
      final id = match[1]!;
      final verdict = verdicts[id] ?? 'ready';
      return verdict == 'ready'
          ? jsonBody(200, fileJson(id, status: 'ready'))
          : jsonBody(
              200,
              fileJson(id, status: 'rejected', reason: verdict as String),
            );
    }
    if (options.method == 'PUT' && path.endsWith('/photos')) {
      attached.add([
        for (final id in (SentRequest(options).json['file_ids']! as List))
          id as String,
      ]);
      return ResponseBody.fromString('', 204);
    }
    return null;
  }
}

class FakePhotoPicker implements PhotoPicker {
  FakePhotoPicker({this.files = const [], this.hasCamera = true});
  List<XFile> files;
  int? lastLimit;
  @override
  final bool hasCamera;
  @override
  Future<List<XFile>> gallery({required int limit}) async {
    lastLimit = limit;
    return files;
  }

  @override
  Future<XFile?> camera() async => files.firstOrNull;
}

XFile photoFile(String name, {int? size}) => XFile.fromData(
  size == null ? transparentPng : Uint8List(size),
  name: name,
  path: name,
  length: size ?? transparentPng.length,
);

const testPhotoConfig = PhotoConfig(
  maxBytes: 10 * 1024 * 1024,
  listingLimit: 10,
  pollInterval: Duration.zero,
  processingTimeout: Duration(minutes: 1),
);
