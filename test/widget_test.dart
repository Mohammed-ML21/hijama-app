import 'package:flutter_test/flutter_test.dart';
import 'package:hijama/main.dart';

void main() {
  testWidgets('Hijama app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const HijamaApp());

    expect(find.text('حجامة'), findsWidgets);
  });
}