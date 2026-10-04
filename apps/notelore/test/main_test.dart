import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/main.dart' as app;

void main() {
  testWidgets('the app starts and shows its name', (tester) async {
    await tester.pumpWidget(const app.NoteloreApp());
    expect(find.text('Notelore'), findsOneWidget);
  });

  testWidgets('main() runs the app', (tester) async {
    app.main();
    await tester.pump();
    expect(find.byType(app.NoteloreApp), findsOneWidget);
  });
}
