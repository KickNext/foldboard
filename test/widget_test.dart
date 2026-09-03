import 'support/sample_board.dart';

import 'package:foldboard/main.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('planner renders architecture and tools', (tester) async {
    final viewModel = PlannerViewModel(repository: sampleBoard());
    await tester.pumpWidget(FoldboardApp(viewModel: viewModel));

    await tester.pumpAndSettle();
    expect(find.text('Sample project'), findsWidgets);
    expect(find.text('Order service'), findsNothing);
    expect(find.text('Open fold'), findsOneWidget);
    expect(find.byIcon(Icons.file_download_outlined), findsOneWidget);
  });
}
