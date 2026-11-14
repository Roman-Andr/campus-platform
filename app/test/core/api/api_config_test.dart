import 'package:campus/src/core/api/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults target the local server', () {
    final config = ApiConfig.fromEnvironment();

    expect(config.baseUrl, Uri.parse('http://localhost:8000'));
    expect(config.downloadUrl.host, 'github.com');
    expect(config.connectTimeout, const Duration(seconds: 10));
    expect(config.receiveTimeout, const Duration(seconds: 30));
    expect(config.retryDelays, const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
    ]);
  });
}
