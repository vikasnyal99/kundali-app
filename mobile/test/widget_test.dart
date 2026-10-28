import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kundli_milan/main.dart';

void main() {
  testWidgets('Language choice persists and changes onboarding copy', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const KundliApp());
    await tester.pumpAndSettle();
    expect(find.text('Choose your language'), findsOneWidget);
    await tester.tap(find.text('हिन्दी'));
    await tester.pumpAndSettle();
    expect(find.text('अपनी भाषा चुनें'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('locale'), 'hi');
    expect(find.byType(FilledButton), findsOneWidget);
  });
}
