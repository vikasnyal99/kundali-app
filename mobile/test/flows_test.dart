import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kundli_milan/api.dart';
import 'package:kundli_milan/main.dart';
import 'package:kundli_milan/theme.dart';

Map<String, dynamic> person(String id, String name) => {
  'id': id,
  'display_name': name,
  'birth_date': '1997-09-14',
  'birth_time_local': '09:30:00',
  'birth_timezone': 'Asia/Kolkata',
  'birth_place_name': 'Delhi',
  'latitude': 28.6,
  'longitude': 77.2,
  'time_accuracy': 'exact',
};

Map<String, dynamic> score(double earned, [List<String> warnings = const []]) =>
    {
      'score': {
        'earned': earned,
        'possible': 36,
        'kootas': [
          {'key': 'nadi', 'earned': 8, 'possible': 8},
        ],
      },
      'warnings': warnings,
      'calculation': {'engine': 'test'},
    };

/// In-memory stand-in for the API; records every request for assertions.
class FakeBackend {
  final people = [
    person('a', 'Asha'),
    person('b', 'Bharat'),
    person('c', 'Chetan'),
    person('d', 'Dev'),
  ];
  final requests = <http.Request>[];
  int reportPolls = 0;
  Map<String, dynamic>? lastComparison;
  Map<String, dynamic> report(String status) => {
    'id': 'r1',
    'match_id': 'm-b',
    'locale': 'en',
    'status': status,
  };
  final overrides = <String, http.Response>{};
  late final client = MockClient((r) async {
    requests.add(r);
    final key = '${r.method} ${r.url.path}';
    if (overrides.containsKey(key)) return overrides[key]!;
    final body = r.body.isEmpty ? null : jsonDecode(r.body);
    switch (key) {
      case 'POST /v1/guest-sessions':
        return json({'token': 'new-token'}, 201);
      case 'POST /v1/guest-sessions/refresh':
        return json({'token': 'renewed'});
      case 'GET /v1/people':
        return json(people);
      case 'GET /v1/places':
        return json([
          {
            'name': 'Varanasi',
            'region': 'Uttar Pradesh',
            'country': 'IN',
            'latitude': 25.3167,
            'longitude': 83.0104,
            'timezone': 'Asia/Kolkata',
          },
        ]);
      case 'GET /v1/reports':
        return json([]);
      case 'POST /v1/comparisons':
        lastComparison = comparison(body['person1_id'], body['person2_ids']);
        return json(lastComparison!);
      case 'GET /v1/comparisons/cmp':
        return json(lastComparison!);
      case 'POST /v1/matches':
        return json(
          comparison(body['person1_id'], [body['person2_id']])['results'][0],
          202,
        );
      case 'GET /v1/matches/m-b/summary':
        return json({
          'source': 'ai',
          'headline': 'Good match (Uttam)',
          'overview': 'Asha and Bharat share 24 of 36 gunas.',
          'kootas': [
            {
              'key': 'nadi',
              'earned': 8,
              'possible': 8,
              'area': 'Health and progeny',
              'p1': 'Aadi',
              'p2': 'Antya',
              'note': 'Different nadis are favourable.',
            },
          ],
          'strengths': ['Nadi is fully matched'],
          'considerations': [],
          'guidance': 'Talk openly.',
        });
      case 'POST /v1/matches/m-b/reports':
        return json(report('pending'), 202);
      case 'GET /v1/reports/r1':
        reportPolls++;
        return json(report(reportPolls > 1 ? 'ready' : 'processing'));
      case 'POST /v1/reports/r1/download-url':
        return json({'url': 'https://example.test/r1.pdf'});
    }
    return json({
      'error': {'code': 'not_found', 'message': 'not_found'},
    }, 404);
  });
  Map<String, dynamic> comparison(String p1, List ids) {
    // Server contract: results arrive sorted by score with deterministic ties.
    final scores = {'b': 24.0, 'c': 24.0, 'd': 18.5};
    final rows =
        [
          for (final id in ids)
            {
              'id': 'm-$id',
              'status': 'ready',
              'people': [
                people.firstWhere((p) => p['id'] == p1),
                people.firstWhere((p) => p['id'] == id),
              ],
              'facts': score(
                scores[id]!,
                id == 'd' ? ['approximate_birth_time'] : [],
              ),
            },
        ]..sort(
          (x, y) => (y['facts'] as Map)['score']['earned'].compareTo(
            (x['facts'] as Map)['score']['earned'],
          ),
        );
    return {'id': 'cmp', 'person1_id': p1, 'results': rows};
  }

  List<Map<String, dynamic>> comparisonBodies() => [
    for (final r in requests.where((r) => r.url.path == '/v1/comparisons'))
      jsonDecode(r.body),
  ];
  static http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Future<FakeBackend> launch(
  WidgetTester tester, {
  String locale = 'en',
  Map<String, String> secure = const {'session': 'old-token'},
  void Function(FakeBackend)? setup,
}) async {
  tester.view.physicalSize = const Size(1000, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'onboarded': true, 'locale': locale});
  FlutterSecureStorage.setMockInitialValues(Map.of(secure));
  final backend = FakeBackend();
  setup?.call(backend);
  await tester.pumpWidget(
    KundliApp(
      api: Api(client: backend.client, base: 'http://test'),
    ),
  );
  await tester.pumpAndSettle();
  return backend;
}

/// Taps a person in a Select Person list, then the page's bottom action.
Future<void> pick(WidgetTester tester, String name, String action) async {
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(action).last);
  await tester.pumpAndSettle();
}

Finder candidate(String id) => find.byKey(ValueKey('candidate-$id'));

VoidCallback? actionOf(WidgetTester tester, String label) => tester
    .widget<PrimaryButton>(find.widgetWithText(PrimaryButton, label))
    .onPressed;

void main() {
  // Cached asset futures are bound to the previous test's fake-async zone.
  setUp(() => rootBundle.clear());
  testWidgets(
    'Person 1 stays fixed while candidates are compared, changed and re-compared',
    (tester) async {
      final backend = await launch(tester);
      await tester.tap(find.text('Compare\nCandidates'));
      await tester.pumpAndSettle();
      expect(actionOf(tester, 'Compare Selected (0)'), isNull);

      await tester.tap(find.text('Choose Person 1'));
      await tester.pumpAndSettle();
      await pick(tester, 'Asha', 'Next');
      expect(find.text('Person 1 (Fixed)'), findsOneWidget);
      // Person 1 is never offered as a candidate.
      expect(candidate('a'), findsNothing);
      for (final id in ['b', 'c', 'd']) {
        await tester.tap(candidate(id));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compare Selected (3)'));
      await tester.pumpAndSettle();

      expect(backend.comparisonBodies().single, {
        'person1_id': 'a',
        'person2_ids': ['b', 'c', 'd'],
        'locale': 'en',
      });
      expect(find.text('Compatibility with candidates'), findsOneWidget);
      expect(find.text('24/36'), findsNWidgets(2));
      expect(find.text('Tied score'), findsNWidgets(2));
      expect(find.text('18.5/36'), findsOneWidget);
      expect(find.text('Has warnings — open details'), findsOneWidget);
      expect(find.text('Moderate'), findsNWidgets(3));
      final order = [
        'Bharat',
        'Chetan',
        'Dev',
      ].map((n) => tester.getTopLeft(find.text(n)).dy).toList();
      expect(order, [...order]..sort());

      // Back on the list: dropping a candidate re-compares with Person 1 kept.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(candidate('c'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compare Selected (2)'));
      await tester.pumpAndSettle();
      expect(backend.comparisonBodies().last['person1_id'], 'a');
      expect(backend.comparisonBodies().last['person2_ids'], ['b', 'd']);
      expect(find.text('Tied score'), findsNothing);

      // Changing Person 1 is explicit and drops that person from the candidate set.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await pick(tester, 'Bharat', 'Next');
      expect(candidate('b'), findsNothing);
      expect(actionOf(tester, 'Compare Selected (1)'), isNull);
      await tester.tap(candidate('a'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compare Selected (2)'));
      await tester.pumpAndSettle();
      expect(backend.comparisonBodies().last, {
        'person1_id': 'b',
        'person2_ids': ['d', 'a'],
        'locale': 'en',
      });
    },
  );

  testWidgets(
    'Select Person 1 → Person 2 opens the detailed report; the full PDF is generated from there',
    (tester) async {
      final backend = await launch(tester);
      await tester.tap(find.text('Match Kundlis'));
      await tester.pumpAndSettle();
      expect(find.text('Select Person 1'), findsOneWidget);
      await pick(tester, 'Asha', 'Next');
      expect(find.text('Select Person 2'), findsOneWidget);
      expect(find.text('Asha'), findsNothing); // Person 1 is not offered again
      await pick(tester, 'Bharat', 'Match Kundlis');

      expect(find.text('Detailed Report'), findsOneWidget);
      expect(find.text('Compatibility Score'), findsOneWidget);
      expect(find.text('Moderate'), findsOneWidget); // 24 of 36
      expect(
        find.text('Asha and Bharat share 24 of 36 gunas.'),
        findsOneWidget,
      );
      expect(find.text('Key Strengths'), findsOneWidget);

      await tester.tap(find.text('Guna Details'));
      await tester.pumpAndSettle();
      expect(find.text('Different nadis are favourable.'), findsOneWidget);
      expect(find.text('Asha: Aadi   ·   Bharat: Antya'), findsOneWidget);
      await tester.tap(find.text('Doshas'));
      await tester.pumpAndSettle();
      expect(find.text('Nadi Dosha'), findsOneWidget);
      expect(find.text('Not present'), findsOneWidget);
      await tester.tap(find.text('Remedies'));
      await tester.pumpAndSettle();
      expect(find.text('Talk openly.'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Generate full report'), 300);
      await tester.tap(find.text('Generate full report'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Preparing your PDF'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();
      expect(
        backend.requests.map((r) => '${r.method} ${r.url.path}'),
        contains('POST /v1/reports/r1/download-url'),
      );
      expect(find.text('Download PDF'), findsOneWidget);
    },
  );
  testWidgets('API errors are localised and offer retry', (tester) async {
    await launch(
      tester,
      locale: 'hi',
      setup: (b) => b.overrides['GET /v1/people'] = FakeBackend.json({
        'error': {'code': 'rate_limit', 'message': 'x'},
      }, 429),
    );
    expect(
      find.text('बहुत अधिक अनुरोध। एक मिनट रुककर फिर प्रयास करें।'),
      findsOneWidget,
    );
    expect(find.text('फिर प्रयास करें'), findsWidgets);
  });

  testWidgets('unknown error codes and proxy error pages stay readable', (
    tester,
  ) async {
    await launch(
      tester,
      setup: (b) => b.overrides['GET /v1/reports'] = http.Response(
        '<html>Bad gateway</html>',
        502,
      ),
    );
    expect(
      find.text(
        'Something went wrong. Check your connection and try again. (error)',
      ),
      findsOneWidget,
    );
  });

  testWidgets('expired guest session is replaced and the user is told', (
    tester,
  ) async {
    final backend = await launch(
      tester,
      setup: (b) =>
          b.overrides['POST /v1/guest-sessions/refresh'] = FakeBackend.json({
            'error': {'code': 'session_expired', 'message': 'x'},
          }, 401),
    );
    expect(
      find.textContaining('previous guest session expired'),
      findsOneWidget,
    );
    expect(
      backend.requests.map((r) => r.url.path),
      contains('/v1/guest-sessions'),
    );
    expect(backend.requests.last.headers['Authorization'], 'Bearer new-token');
  });

  testWidgets('active session is renewed on launch', (tester) async {
    final backend = await launch(tester);
    expect(backend.requests.first.url.path, '/v1/guest-sessions/refresh');
    expect(backend.requests.first.headers['Authorization'], 'Bearer old-token');
    expect(await const FlutterSecureStorage().read(key: 'session'), 'renewed');
  });

  testWidgets(
    'switching language in settings relabels the app without leaving the screen',
    (tester) async {
      await launch(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Methodology & privacy'), findsOneWidget);
      await tester.tap(find.text('हिन्दी'));
      await tester.pumpAndSettle();
      expect(find.text('Methodology & privacy'), findsNothing);
      expect(find.text('सेटिंग्स'), findsWidgets);
      expect(find.byType(SegmentedButton<String>), findsOneWidget);
      expect((await SharedPreferences.getInstance()).getString('locale'), 'hi');
    },
  );

  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(find.text('People').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add person'));
    await tester.pumpAndSettle();
  }

  Future<void> confirmAndSave(WidgetTester tester) async {
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save details'));
    await tester.pumpAndSettle();
  }

  Future<void> choosePlace(WidgetTester tester, String query) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'City, town or 6-digit pincode'),
      query,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Varanasi, Uttar Pradesh, IN'));
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> saved(FakeBackend b) => jsonDecode(
    b.requests
        .lastWhere((r) => r.method == 'POST' && r.url.path == '/v1/people')
        .body,
  );

  testWidgets(
    'new person form: one place search, DD/MM/YYYY and 12-hour time',
    (tester) async {
      final backend = await launch(
        tester,
        setup: (b) =>
            b.overrides['POST /v1/people'] = FakeBackend.json({'id': 'n'}, 201),
      );
      await openEditor(tester);
      expect(find.text('Latitude'), findsNothing);
      expect(find.text('Longitude'), findsNothing);
      await tester.enterText(find.byType(TextFormField).first, 'Deepak Saini');
      await choosePlace(tester, '221001');
      expect(backend.requests.last.url.queryParameters['q'], '221001');
      final boxes = find.byWidgetPredicate(
        (w) => w is TextField && w.maxLength != null,
      );
      for (final (i, v) in ['05', '03', '1995', '09', '30'].indexed) {
        await tester.enterText(boxes.at(i), v);
      }
      await tester.tap(find.text('PM'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      // Confirm step shows the entries in words before saving.
      expect(find.text('5 Mar 1995'), findsOneWidget);
      expect(find.text('9:30 PM'), findsOneWidget);
      expect(find.text('Varanasi, Uttar Pradesh, IN'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save details'));
      await tester.pumpAndSettle();
      expect(saved(backend), {
        'display_name': 'Deepak Saini',
        'birth_place_name': 'Varanasi, Uttar Pradesh, IN',
        'latitude': 25.3167,
        'longitude': 83.0104,
        'birth_timezone': 'Asia/Kolkata',
        'birth_date': '1995-03-05',
        'time_accuracy': 'exact',
        'birth_time_local': '21:30:00',
        'fold': null,
        'avatar': null,
      });
    },
  );

  testWidgets(
    'unknown birth time hides the time and sends none; place must be chosen',
    (tester) async {
      final backend = await launch(
        tester,
        setup: (b) =>
            b.overrides['POST /v1/people'] = FakeBackend.json({'id': 'n'}, 201),
      );
      await openEditor(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Kirti');
      await tester.tap(find.byKey(const ValueKey('avatar-female_1')));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'City, town or 6-digit pincode'),
        'Somewhere',
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('Time of birth'), findsNothing);
      final boxes = find.byWidgetPredicate(
        (w) => w is TextField && w.maxLength != null,
      );
      expect(boxes, findsNWidgets(3));
      for (final (i, v) in ['31', '02', '1996'].indexed) {
        await tester.enterText(boxes.at(i), v);
      }
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(
        find.text('Choose the birth place from the suggestions'),
        findsOneWidget,
      );
      expect(
        find.text('Enter a valid date of birth (DD / MM / YYYY)'),
        findsOneWidget,
      ); // 31 February
      expect(
        backend.requests.where(
          (r) => r.url.path == '/v1/people' && r.method == 'POST',
        ),
        isEmpty,
      );

      await choosePlace(tester, 'Vara');
      await tester.enterText(boxes.at(0), '29');
      await confirmAndSave(tester);
      final body = saved(backend);
      expect(body['time_accuracy'], 'unknown');
      expect(body.containsKey('birth_time_local'), isFalse);
      expect(body['birth_date'], '1996-02-29');
      expect(body['avatar'], 'female_1');
    },
  );
}
