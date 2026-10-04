// #221 — "Badge toekennen": the teacher picks one of a fixed list of badges
// for a student, sees how often each was given so far, and the badge lands
// on the student's account doc with the others (`awardedBy: teacher`,
// `earnedAt`), its count one higher each time.

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/features/account/detail/award_badge_dialog.dart';
import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/badges/earned_badges.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/localization.dart';

class _NoAuth extends AuthService {
  @override
  AccountIdentity? build() => null;
}

/// The accounts container, whose writes can be made to fail.
class _Accounts implements CosmosContainer {
  _Accounts(this.inner);
  final CosmosContainer inner;
  bool failWrites = false;

  @override
  Future<Map<String, dynamic>> replace(
    String id,
    Map<String, Object?> doc, {
    required Object partitionKey,
    String? ifMatch,
  }) {
    if (failWrites) throw CosmosException(503, 'unavailable');
    return inner.replace(id, doc, partitionKey: partitionKey, ifMatch: ifMatch);
  }

  @override
  Future<Map<String, dynamic>?> read(
    String id, {
    required Object partitionKey,
  }) => inner.read(id, partitionKey: partitionKey);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late InMemoryCosmos accounts;
  late _Accounts container;

  Map<String, dynamic> doc() => {
    'id': 'u1',
    'uid': 'u1',
    'firstName': 'Sam',
    'lastName': 'Student',
    'email': 'sam@example.com',
    'className': '6EWI',
    'oefeningCount': 40,
    'badges': {
      'effort': {'tier': 1, 'earnedAt': '2026-10-01T10:00:00.000Z'},
      'teacher:helpingHand': {
        'tier': 1,
        'awardedBy': 'teacher',
        'count': 2,
        'seen': 2,
      },
    },
  };

  setUp(() {
    accounts = InMemoryCosmos([doc()]);
    container = _Accounts(accounts.container);
  });

  Future<void> open(WidgetTester tester, {Account? account}) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shown = account ?? Account.fromMap(doc());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWith(_NoAuth.new),
          accountServiceProvider.overrideWith(
            () => AccountService(container: container),
          ),
        ],
        child: localizedTestApp(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAwardBadgeDialog(context, shown),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder choice(String id) => find.byKey(ValueKey('award-badge-$id'));

  FilledButton confirm(WidgetTester tester) => tester.widget<FilledButton>(
    find.byKey(const ValueKey('award-badge-confirm')),
  );

  EarnedBadge? stored(String id) =>
      EarnedBadges.fromDoc(accounts.docs['u1']!)!.byId[id];

  testWidgets('the fixed list, with how often each was given', (tester) async {
    await open(tester);
    expect(find.text('Award a badge to Sam Student'), findsOneWidget);
    expect(find.textContaining('Sam gets a notice'), findsOneWidget);
    expect(
      find.descendant(
        of: choice('teacher:faultFinder'),
        matching: find.text('Fault finder'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: choice('teacher:faultFinder'),
        matching: find.text(
          'Reported a wrong question, by the ID at the top of the exercise.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: choice('teacher:helpingHand'),
        matching: find.text('Given 2× so far'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: choice('teacher:goodQuestion'),
        matching: find.text('Not given yet'),
      ),
      findsOneWidget,
    );
    // Nothing chosen: nothing to award.
    expect(confirm(tester).onPressed, isNull);
  });

  testWidgets('awarding counts it up on the student\'s doc, keeps the rest, '
      'and says so', (tester) async {
    await open(tester);
    await tester.tap(choice('teacher:helpingHand'));
    await tester.pump();
    expect(confirm(tester).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('award-badge-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('award-badge-dialog')), findsNothing);
    expect(find.text('Helping hand awarded (3×).'), findsOneWidget);
    final entry = stored('teacher:helpingHand')!;
    expect(entry.count, 3);
    expect(entry.seen, 2, reason: 'the student has not seen the third yet');
    expect(entry.awardedBy, kAwardedByTeacher);
    expect(entry.earnedAt, isNotNull);
    expect(stored('effort')!.tier, 1);
    expect(accounts.docs['u1']!['oefeningCount'], 40);

    // A badge never given before starts at one.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(choice('teacher:faultFinder'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('award-badge-confirm')));
    await tester.pumpAndSettle();
    expect(stored('teacher:faultFinder')!.count, 1);
    expect(find.text('Fault finder awarded (1×).'), findsOneWidget);
  });

  testWidgets('the counts are read again: the drawer\'s account may be '
      'older than the doc', (tester) async {
    final old = Account.fromMap({...doc(), 'badges': <String, dynamic>{}});
    await open(tester, account: old);
    expect(
      find.descendant(
        of: choice('teacher:helpingHand'),
        matching: find.text('Given 2× so far'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a write that fails says so and keeps the dialog open', (
    tester,
  ) async {
    container.failWrites = true;
    await open(tester);
    await tester.tap(choice('teacher:goodQuestion'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('award-badge-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('award-badge-dialog')), findsOneWidget);
    expect(
      find.text('The badge could not be awarded. Try again.'),
      findsOneWidget,
    );
    expect(stored('teacher:goodQuestion'), isNull);

    // Cancel: nothing given.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('award-badge-dialog')), findsNothing);
    expect(find.textContaining('awarded'), findsNothing);
  });
}
