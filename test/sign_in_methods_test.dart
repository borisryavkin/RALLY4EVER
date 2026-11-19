import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/participant/forms.dart';

import 'support/fake_participant.dart';

import 'package:rally4ever/participant/repository.dart';

class LinkedRepo extends FakeParticipantRepository {
  int links = 0;
  @override
  Future<void> addAppPassword(String password) async {
    links++;
    passwordUser = true;
    notifyListeners();
  }
}

class StaleLinkedRepo extends LinkedRepo {
  bool reverified = false;
  @override
  Future<void> reauthenticateGoogle() async {
    reverified = true;
  }

  @override
  Future<void> addAppPassword(String password) async {
    if (!reverified) throw RecentSignInRequired();
    await super.addAppPassword(password);
  }
}

void main() {
  testWidgets(
    'stale login offers Google verification and retries on the same account',
    (tester) async {
      final repo = StaleLinkedRepo()..googleUser = true;
      final uid = repo.uid;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: repo,
              builder: (context, _) => SignInMethodsPanel(repository: repo),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('link-password')),
        'Test-password-123!',
      );
      await tester.enterText(
        find.byKey(const Key('link-password-confirm')),
        'Test-password-123!',
      );
      await tester.tap(find.byKey(const Key('connect-email-password')));
      await tester.pumpAndSettle();
      expect(
        find.text('Verify with Google & enable email sign-in'),
        findsOneWidget,
      );
      expect(repo.links, 0);
      await tester.tap(find.byKey(const Key('connect-email-password')));
      await tester.pumpAndSettle();
      expect(repo.reverified, true);
      expect(repo.links, 1);
      expect(repo.uid, uid);
      expect(
        find.textContaining('Email/password sign-in: connected'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );

  testWidgets(
    'adding email sign-in requires matching passwords and keeps profile/role',
    (tester) async {
      final repo = LinkedRepo()..googleUser = true;
      final uid = repo.uid, profile = repo.profile;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: repo,
              builder: (context, _) => SignInMethodsPanel(repository: repo),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('connect-email-password')));
      await tester.pump();
      expect(repo.links, 0);
      expect(find.textContaining('Use at least 8'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('link-password')),
        'Test-password-123!',
      );
      await tester.enterText(
        find.byKey(const Key('link-password-confirm')),
        'different',
      );
      await tester.tap(find.byKey(const Key('connect-email-password')));
      await tester.pump();
      expect(repo.links, 0);
      await tester.enterText(
        find.byKey(const Key('link-password-confirm')),
        'Test-password-123!',
      );
      await tester.tap(find.byKey(const Key('connect-email-password')));
      await tester.pumpAndSettle();
      expect(repo.links, 1);
      expect(repo.uid, uid);
      expect(identical(repo.profile, profile), true);
      expect(
        find.textContaining('Email/password sign-in: connected'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('link-password')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  testWidgets(
    'already linked email does not offer another password or another account',
    (tester) async {
      final repo = LinkedRepo()
        ..googleUser = true
        ..passwordUser = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SignInMethodsPanel(repository: repo)),
        ),
      );
      expect(find.text('Google sign-in: connected'), findsOneWidget);
      expect(find.byKey(const Key('connect-email-password')), findsNothing);
      expect(
        find.textContaining('Email/password sign-in: connected'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
}
