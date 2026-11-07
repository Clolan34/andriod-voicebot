import 'dart:convert';
import 'package:http/http.dart' as http;

class ReferenceSummary {
  final String title;
  final String text;
  final String url;
  const ReferenceSummary(this.title, this.text, this.url);
}

/// Public, account-free Wikipedia API. This is reference discovery, not an
/// official university source or automatic question generation.
class OnlineLibrary {
  final http.Client client;
  OnlineLibrary({http.Client? client}) : client = client ?? http.Client();
  Future<List<ReferenceSummary>> search(String topic) async {
    if (topic.trim().isEmpty) return [];
    final uri = Uri.https('en.wikipedia.org', '/w/api.php', {
      'action': 'query',
      'format': 'json',
      'formatversion': '2',
      'generator': 'search',
      'gsrsearch': topic.trim(),
      'gsrnamespace': '0',
      'gsrlimit': '6',
      'prop': 'extracts|info',
      'exintro': '1',
      'explaintext': '1',
      'exchars': '1400',
      'inprop': 'url',
    });
    final response = await client
        .get(
          uri,
          headers: {
            'User-Agent':
                'StudyForge/1.0 (Android educational reference reader)',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception(
        'Reference service unavailable (${response.statusCode}). Try again later.',
      );
    }
    final value = jsonDecode(response.body);
    if (value is! Map || value['error'] != null) {
      throw const FormatException('Reference service returned an error.');
    }
    final pages = (value['query'] as Map?)?['pages'] as List? ?? [];
    final result = <ReferenceSummary>[];
    for (final p in pages) {
      if (p is! Map ||
          p['title'] is! String ||
          p['extract'] is! String ||
          p['fullurl'] is! String) {
        continue;
      }
      final url = Uri.tryParse(p['fullurl'] as String);
      if (url?.scheme != 'https' || url?.host != 'en.wikipedia.org') continue;
      result.add(
        ReferenceSummary(
          p['title'] as String,
          p['extract'] as String,
          p['fullurl'] as String,
        ),
      );
    }
    return result;
  }

  void close() => client.close();
}
