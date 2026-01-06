import 'package:http/http.dart' as http;

class HealthService {
  final String baseUrl;
  HealthService({String? baseUrl})
      : baseUrl = baseUrl ?? 'http://localhost:8000';

  Future<String> ping() async {
    final resp = await http
        .get(Uri.parse('$baseUrl/healthz'))
        .timeout(const Duration(seconds: 8));
    return 'status=${resp.statusCode}, body=${resp.body}';
  }
}
