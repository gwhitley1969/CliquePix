import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clique_pix/models/reactor_model.dart';
import 'package:clique_pix/widgets/reactor_list_sheet.dart';

ReactorEntry _entry({
  required String id,
  required String userId,
  required String name,
  required String type,
  DateTime? createdAt,
}) {
  return ReactorEntry(
    id: id,
    userId: userId,
    displayName: name,
    reactionType: type,
    createdAt: createdAt ?? DateTime(2026, 5, 2, 12),
  );
}

ReactorList _listOf(List<ReactorEntry> reactors) {
  final byType = <String, int>{};
  for (final r in reactors) {
    byType[r.reactionType] = (byType[r.reactionType] ?? 0) + 1;
  }
  return ReactorList(
    mediaId: 'media-1',
    totalReactions: reactors.length,
    byType: byType,
    reactors: reactors,
  );
}

Future<void> _openSheet(
  WidgetTester tester, {
  required Future<ReactorList> Function() fetch,
  String? initialFilter,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => Center(
          child: ElevatedButton(
            onPressed: () => ReactorListSheet.show(
              ctx,
              fetchReactors: fetch,
              initialFilter: initialFilter,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pump(); // schedule the sheet route
  await tester.pump(const Duration(milliseconds: 400)); // sheet animation
}

void main() {
  testWidgets(
    'tabs skip empty reaction types and order by AppConstants.reactionTypes',
    (tester) async {
      // Reactors with only heart + fire — laugh and wow tabs must be hidden.
      final list = _listOf([
        _entry(id: 'r1', userId: 'u-paula', name: 'Paula', type: 'heart',
            createdAt: DateTime(2026, 5, 2, 12, 2)),
        _entry(id: 'r2', userId: 'u-bob', name: 'Bob', type: 'fire',
            createdAt: DateTime(2026, 5, 2, 12, 1)),
        _entry(id: 'r3', userId: 'u-carol', name: 'Carol', type: 'heart',
            createdAt: DateTime(2026, 5, 2, 12, 0)),
      ]);

      await _openSheet(tester, fetch: () async => list);
      // Settle the FutureBuilder (already-completed future fires next frame).
      await tester.pump();

      expect(find.text('All 3'), findsOneWidget);
      expect(find.textContaining('❤️ 2'), findsOneWidget);
      expect(find.textContaining('🔥 1'), findsOneWidget);
      // Empty types must not get a tab.
      expect(find.textContaining('😂'), findsNothing);
      expect(find.textContaining('😮'), findsNothing);

      // All tab is selected initially → all 3 reactor names visible.
      expect(find.text('Paula'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Carol'), findsOneWidget);
    },
  );

  testWidgets(
    'sheet shows skeleton then list across async states (and shows empty state for no reactions)',
    (tester) async {
      // 1) Skeleton state — Future never completes during the pump window.
      final neverComplete = Completer<ReactorList>();
      await _openSheet(tester, fetch: () => neverComplete.future);
      // Sheet content rendered, but FutureBuilder still loading → no list rows.
      expect(find.text('Reactions'), findsOneWidget);
      // Skeleton circles are CircleAvatars; finder asserts at least one.
      expect(find.byType(CircleAvatar), findsWidgets);

      // 2) Resolve the future to an empty list and verify the All-tab empty
      // state copy renders.
      neverComplete.complete(_listOf(const []));
      await tester.pump(); // FutureBuilder rebuild
      await tester.pump(); // Tab content
      expect(find.text("No one's reacted with this yet."), findsOneWidget);
    },
  );
}
