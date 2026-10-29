import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kundli_milan/shell.dart';

void main() {
  final home = Uri.parse('https://kundaliapi.zivantaai.com/');

  test('app pages stay in the WebView; signed PDF links leave it', () {
    expect(
      isAppLink(Uri.parse('https://kundaliapi.zivantaai.com/#/'), home),
      isTrue,
    );
    expect(isAppLink(Uri.parse('about:blank'), home), isTrue);
    expect(
      isAppLink(
        Uri.parse(
          'https://kundali-milan.s3.ap-south-1.amazonaws.com/r.pdf?X-Amz=1',
        ),
        home,
      ),
      isFalse,
    );
    expect(
      isAppLink(
        Uri.parse('http://localhost:9999/'),
        Uri.parse('http://localhost:8100/'),
      ),
      isFalse,
    );
  });

  test(
    'hand-over script stores a JSON string the web app SharedPreferences can read',
    () {
      final script = handoffScript({
        'session': "a'b\"c</script>",
        'locale': 'hi',
        'onboarded': true,
      });
      final literal = RegExp(
        r"setItem\('flutter\.kundli_handoff', (.*)\);location",
      ).firstMatch(script)!.group(1)!;
      // localStorage holds jsonEncode(value); the value is itself the JSON payload.
      final stored = jsonDecode(literal) as String;
      expect(jsonDecode(jsonDecode(stored) as String), {
        'session': "a'b\"c</script>",
        'locale': 'hi',
        'onboarded': true,
      });
      expect(script, endsWith("location.replace('./');"));
    },
  );

  testWidgets('splash draws the kundali and shows the name', (tester) async {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(seconds: 1),
    );
    await tester.pumpWidget(
      MaterialApp(home: Splash(intro: controller, waiting: false)),
    );
    controller.value = 1;
    await tester.pump();
    expect(find.text('KundliMilan'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is KundaliPainter,
      ),
      findsOneWidget,
    );
    controller.dispose();
  });

  testWidgets('offline screen offers retry in both languages', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      MaterialApp(home: Offline(onRetry: () => retried++)),
    );
    expect(find.text('इंटरनेट कनेक्शन नहीं है'), findsOneWidget);
    await tester.tap(find.text('Retry · फिर प्रयास करें'));
    expect(retried, 1);
  });
}
