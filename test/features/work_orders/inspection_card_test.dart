import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsl_facility_manager/features/work_orders/data/sample_work_orders.dart';
import 'package:tsl_facility_manager/features/work_orders/presentation/widgets/inspection_card.dart';

void main() {
  final now = DateTime(2026, 11, 5, 10);
  final review = sampleWorkOrders(now).firstWhere((o) => o.isAwaitingReview);

  Future<void> show(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  testWidgets('shows the checklist and note once the work is confirmed', (
    tester,
  ) async {
    final done = review.confirm(
      at: now,
      inspectionNote: 'Checked on site. Light works well.',
      checks: ['Unit operating correctly', 'Area clean and safe'],
      media: const [],
    );
    await show(tester, InspectionCard(done));

    expect(find.text('Supervisor inspection'), findsOneWidget);
    expect(find.text('Unit operating correctly'), findsOneWidget);
    expect(find.text('Area clean and safe'), findsOneWidget);
    expect(find.text('Checked on site. Light works well.'), findsOneWidget);
  });

  testWidgets('shows nothing before the work is confirmed', (tester) async {
    await show(tester, InspectionCard(review));
    expect(find.text('Supervisor inspection'), findsNothing);
  });
}
