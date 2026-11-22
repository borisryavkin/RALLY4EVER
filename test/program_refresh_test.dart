import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/participant/catalogue.dart';

import 'support/fake_participant.dart';

class RefreshRepo extends FakeParticipantRepository {
  final pending = Completer<void>();
  int refreshCalls = 0;
  bool fail = false;
  @override
  Future<void> refreshCatalogue() async {
    refreshCalls++;
    await pending.future;
    if (fail) throw StateError('offline');
    programs = [
      {
        'id': 'new',
        'name': 'New published program',
        'status': 'active',
        'sport': 'tennis',
        'venue': {'suburb': 'Ultimo', 'state': 'NSW'},
      },
    ];
    notifyListeners();
  }
}

void main() {
  Future<void> show(WidgetTester tester, RefreshRepo repo) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProgramBrowser(repository: repo, onSelect: (_) {}),
        ),
      ),
    ),
  );
  testWidgets(
    'refresh loads a newly published program and prevents duplicate requests',
    (tester) async {
      final repo = RefreshRepo()..catalogueReady = true;
      await show(tester, repo);
      await tester.tap(find.byKey(const Key('refresh-programs')));
      await tester.pump();
      expect(find.text('Refreshing…'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('refresh-programs')))
            .onPressed,
        isNull,
      );
      expect(repo.refreshCalls, 1);
      repo.pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('New published program'), findsOneWidget);
      expect(find.text('Programs are up to date.'), findsOneWidget);
    },
  );
  testWidgets('refresh failure stays visible and enables retry', (
    tester,
  ) async {
    final repo = RefreshRepo()
      ..catalogueReady = true
      ..fail = true;
    await show(tester, repo);
    await tester.tap(find.byKey(const Key('refresh-programs')));
    repo.pending.complete();
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Could not refresh programs. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('refresh-programs')))
          .onPressed,
      isNotNull,
    );
  });
}
