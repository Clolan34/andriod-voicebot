import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:studyforge/data/online.dart';

void main() {
  test(
    'Online search encodes topic and returns attributed HTTPS sources only',
    () async {
      final api = OnlineLibrary(
        client: MockClient((r) async {
          expect(r.url.scheme, 'https');
          expect(r.url.queryParameters['gsrsearch'], 'algebra & sets');
          return http.Response(
            jsonEncode({
              'query': {
                'pages': [
                  {
                    'title': 'Algebra',
                    'extract': 'A branch of mathematics',
                    'fullurl': 'https://en.wikipedia.org/wiki/Algebra',
                  },
                  {
                    'title': 'Unsafe',
                    'extract': 'text',
                    'fullurl': 'http://example.org',
                  },
                ],
              },
            }),
            200,
          );
        }),
      );
      final results = await api.search('algebra & sets');
      expect(results.length, 1);
      expect(results.single.title, 'Algebra');
      api.close();
    },
  );
  test('Service errors do not masquerade as empty results', () async {
    final api = OnlineLibrary(
      client: MockClient((_) async => http.Response('unavailable', 503)),
    );
    await expectLater(api.search('calculus'), throwsException);
    api.close();
  });
  test(
    'Empty search makes no network request and empty result is valid',
    () async {
      var calls = 0;
      final api = OnlineLibrary(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      expect(await api.search('  '), isEmpty);
      expect(calls, 0);
      expect(await api.search('unusual topic'), isEmpty);
      expect(calls, 1);
      api.close();
    },
  );
}
