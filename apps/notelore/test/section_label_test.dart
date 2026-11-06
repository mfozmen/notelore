import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/section_label.dart';
import 'package:notelore/src/strings.dart';
import 'package:notelore/src/theme.dart';

Future<void> _show(WidgetTester tester, Widget label) => tester.pumpWidget(
  MaterialApp(
    theme: noteloreTheme(Brightness.light),
    home: Scaffold(body: label),
  ),
);

void main() {
  testWidgets('a section label: capitals with a star, read as its words, a header', (tester) async {
    await _show(tester, SectionLabel('Gelişmiş', strings: TurkishStrings()));
    expect(find.text('GELİŞMİŞ'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('GELİŞMİŞ')),
      matchesSemantics(label: 'Gelişmiş', isHeader: true),
    );
    final colors = Theme.of(tester.element(find.byType(Star))).colorScheme;
    expect(tester.widget<Text>(find.text('GELİŞMİŞ')).style?.color, colors.primary);
    expect(tester.widget<Star>(find.byType(Star)).color, colors.primary);
  });

  testWidgets('a late group is in the error colour', (tester) async {
    await _show(tester, SectionLabel('Overdue', strings: EnglishStrings(), late: true));
    final colors = Theme.of(tester.element(find.byType(Star))).colorScheme;
    expect(tester.widget<Text>(find.text('OVERDUE')).style?.color, colors.error);
    expect(tester.widget<Star>(find.byType(Star)).color, colors.error);
    await _show(tester, SectionLabel('Overdue', strings: EnglishStrings()));
    expect(tester.widget<Star>(find.byType(Star)).color, colors.primary); // repainted
  });

  testWidgets('a long label at large text wraps beside its star, nothing overflows', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _show(tester, SectionLabel('Wednesday, 18 November' * 3, strings: EnglishStrings()));
    expect(tester.takeException(), isNull);
  });
}
