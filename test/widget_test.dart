// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:check_data_viettel/main.dart';

void main() {
  testWidgets('Viettel 4G Checker smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ViettelDataApp());

    // Verify that our app header is present.
    expect(find.text('Viettel 4G'), findsOneWidget);
    expect(find.text('Kiểm Tra Dung Lượng'), findsOneWidget);
  });
}
