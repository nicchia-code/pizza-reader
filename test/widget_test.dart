import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pizza_reader/src/ui/pizza_reader_app.dart';

void main() {
  testWidgets('shows the Pizza Reader workspace', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(PizzaReaderApp());

    expect(find.textContaining('Pizza'), findsWidgets);
    expect(find.text('Demo Pizza Book'), findsWidgets);
    expect(find.text('Velocita'), findsOneWidget);
    expect(find.text('Modalita'), findsOneWidget);
  });
}
