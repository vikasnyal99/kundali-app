import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kundli_milan/api.dart';
import 'package:kundli_milan/main.dart';

void main() {
  testWidgets(
    'choosing a language on the first screen saves it and opens the app',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final api = Api(
        client: MockClient((r) async => http.Response('{"token":"t"}', 201)),
        base: 'http://test',
      );
      await tester.pumpWidget(KundliApp(api: api));
      await tester.pumpAndSettle();
      expect(
        find.text('Ancient Wisdom\nfor a Brighter Tomorrow'),
        findsOneWidget,
      );
      expect(find.text('Traditional • Trusted • Thoughtful'), findsOneWidget);
      await tester.tap(find.text('हिंदी'));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('locale'), 'hi');
      expect(prefs.getBool('onboarded'), isTrue);
      expect(
        find.text('आपकी\nअनुकूलता जानें'),
        findsOneWidget,
      ); // Hindi home screen
    },
  );
}
