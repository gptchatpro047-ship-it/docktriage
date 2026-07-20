import 'dart:convert';
import 'dart:io';

import 'models.dart';

class OpenAiDiagnostics {
  OpenAiDiagnostics({String? apiKey})
      : apiKey = apiKey ?? Platform.environment['OPENAI_API_KEY'];

  final String? apiKey;

  Future<String> diagnose(ContainerInfo container, String logs) async {
    if (apiKey == null || apiKey!.isEmpty) {
      throw const DiagnosticException(
        'OPENAI_API_KEY is missing. Export it before launching DockTriage.',
      );
    }

    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('https://api.openai.com/v1/responses'));
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.write(jsonEncode({
        'model': 'gpt-5.6',
        'instructions':
            'You are a careful Docker incident assistant. Use only the supplied evidence. '
                'Return four short sections: Summary, Likely cause, Evidence, Safe next steps. '
                'Never claim certainty when logs are insufficient. Never recommend destructive '
                'commands without a warning and explicit human approval.',
        'input': 'Container: ${container.name}\nImage: ${container.image}\n'
            'State: ${container.state}\nStatus: ${container.status}\n\n'
            'Recent logs:\n${_redact(logs)}',
        'max_output_tokens': 700,
      }));
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = decoded['error'];
        throw DiagnosticException(
          error is Map ? '${error['message']}' : 'OpenAI request failed (${response.statusCode})',
        );
      }
      final text = _extractOutputText(decoded);
      if (text.isEmpty) throw const DiagnosticException('GPT-5.6 returned no text.');
      return text;
    } finally {
      client.close(force: true);
    }
  }

  String _extractOutputText(Map<String, dynamic> response) {
    final direct = response['output_text'];
    if (direct is String && direct.isNotEmpty) return direct;
    final output = response['output'];
    if (output is! List) return '';
    final texts = <String>[];
    for (final item in output.whereType<Map>()) {
      final content = item['content'];
      if (content is List) {
        for (final part in content.whereType<Map>()) {
          if (part['type'] == 'output_text' && part['text'] is String) {
            texts.add(part['text'] as String);
          }
        }
      }
    }
    return texts.join('\n');
  }

  String _redact(String value) {
    final redacted = value.replaceAll(
      RegExp(r'(?i)(api[_-]?key|token|password|secret)\s*[:=]\s*\S+'),
      r'$1=[REDACTED]',
    );
    return redacted.substring(0, redacted.length > 12000 ? 12000 : redacted.length);
  }
}

class DiagnosticException implements Exception {
  const DiagnosticException(this.message);
  final String message;
  @override
  String toString() => message;
}
