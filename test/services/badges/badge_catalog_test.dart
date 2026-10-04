// Issue #220 — the badge set itself: tiers as the issue sets them, ids that
// never collide, a name and a rule for every badge in both languages, and a
// glyph for every badge that is a plain game-icons.net SVG with its author
// on record (CC BY 3.0 asks for the attribution).

import 'dart:io';

import 'package:ai_tutor_python/features/badges/badge_text.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/badges/badge_catalog.dart';
import 'package:ai_tutor_python/services/badges/badge_facts.dart';
import 'package:ai_tutor_python/services/tutor/bank_choice.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final all = BadgeCatalog.all(expertGoalIds: const ['r1', 'r2']);

  test('the tiers of the issue, lowest first', () {
    Map<String, List<int>> tiersOf(List<BadgeDefinition> defs) => {
      for (final d in defs) d.id: d.tiers,
    };
    expect(tiersOf(BadgeCatalog.tiered), {
      'effort': [10, 100, 250, 500, 1000, 1500],
      'homeWork': [50, 100, 250, 500, 1000],
      'lessonWeeks': [5, 10, 20, 30],
      'hardCorrect': [100, 250, 500, 750],
      'streak': [10, 20, 30, 50],
      'gapFiller': [50, 100, 250],
      'fluentPython': [10, 25, 50],
      'writer': [3, 10, 20],
      'allRounder': [3, 10, 20],
      'knowledge': [10, 25, 50, 100, 200],
      'milestones': [5, 10, 25, 50],
      'elephantMemory': [5, 10, 25, 50],
      'stillSharp': [1, 5, 10, 25],
      'oldFriend': [50, 100, 250, 500],
      'comeback': [1, 3, 5, 10],
      'wrongToRight': [10, 25, 50, 100],
      'hintHit': [10, 25, 50, 100],
      'persevere': [1, 3, 10, 20],
      'tough': [20, 30, 50],
    });
    for (final d in BadgeCatalog.fun) {
      expect(d.tiers, hasLength(1), reason: d.id);
    }
    expect(BadgeCatalog.byId('fortyTwo')!.tiers, [42]);
    expect(BadgeCatalog.byId('offByOne')!.tiers, [99]);
  });

  test('ids are unique, and every badge is found by its id', () {
    final ids = all.map((d) => d.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    for (final d in all) {
      expect(BadgeCatalog.byId(d.id), d, reason: d.id);
    }
    expect(BadgeCatalog.byId('expert:r9')!.goalId, 'r9');
    expect(BadgeCatalog.byId('somethingFromALaterBuild'), isNull);
  });

  test('every secret is a single badge, all of them but "Hello, World!"', () {
    expect(BadgeCatalog.tiered.where((d) => d.secret), isEmpty);
    expect(BadgeCatalog.fun.where((d) => !d.secret).map((d) => d.id), [
      'helloWorld',
    ]);
  });

  test('a tier is the number of thresholds reached; nothing known is none', () {
    final effort = BadgeCatalog.byId('effort')!;
    expect(effort.tierFor(null), 0);
    expect(effort.tierFor(9), 0);
    expect(effort.tierFor(10), 1);
    expect(effort.tierFor(152), 2);
    expect(effort.tierFor(5000), 6);
    expect(effort.nextThreshold(0), 10);
    expect(effort.nextThreshold(2), 250);
    expect(effort.nextThreshold(6), isNull);
  });

  test('each badge reads its own number', () {
    const facts = BadgeFacts(
      oefeningen: 152,
      correctOefeningen: 99,
      hardCorrect: 76,
      correctByType: {
        'mcQuestion': 5,
        'completeCodeQuestion': 36,
        'explainCodeQuestion': 7,
        'writeCodeQuestion': 4,
      },
      experts: {'r1': (mastered: 3, total: 3), 'r2': (mastered: 2, total: 3)},
    );
    int? value(String id) => BadgeCatalog.byId(id)!.valueIn(facts);
    expect(value('effort'), 152);
    expect(value('hardCorrect'), 76);
    expect(value('gapFiller'), 36);
    expect(value('fluentPython'), 7);
    expect(value('writer'), 4);
    expect(value('allRounder'), 4, reason: 'the weakest served type');
    expect(value('homeWork'), isNull, reason: 'no lesson times');
    expect(value('lessonWeeks'), isNull);
    expect(value('helloWorld'), 152);
    expect(value('offByOne'), 99);
    expect(value('expert:r1'), 1);
    expect(value('expert:r2'), 0);
    expect(value('expert:r3'), 0);
    expect(
      BadgeCatalog.byId('expert:r1')!.valueIn(BadgeFacts.empty),
      isNull,
      reason: 'goals not known',
    );
  });

  test('Allrounder asks every type the bank serves', () {
    final served = BankChoice.servedTypes.map((t) => t.name).toSet();
    final facts = BadgeFacts(correctByType: {for (final t in served) t: 10});
    expect(BadgeCatalog.byId('allRounder')!.valueIn(facts), 10);
    final oneShort = BadgeFacts(
      correctByType: {for (final t in served) t: t == served.first ? 2 : 10},
    );
    expect(BadgeCatalog.byId('allRounder')!.valueIn(oneShort), 2);
  });

  group('the glyphs (game-icons.net, CC BY 3.0)', () {
    final dir = Directory('assets/badges');

    test('every badge\'s glyph is bundled, and every bundled one is used', () {
      final used = BadgeCatalog.icons.map((i) => i.asset).toSet();
      for (final d in all) {
        expect(File(d.icon.asset).existsSync(), isTrue, reason: d.icon.asset);
      }
      final bundled = dir
          .listSync()
          .whereType<File>()
          .map((f) => 'assets/badges/${f.uri.pathSegments.last}')
          .toSet();
      expect(bundled, used);
    });

    test('each is a plain SVG: paths only, no script, no foreign content, no '
        'external reference, no colour of its own', () {
      final tag = RegExp(r'<\s*([A-Za-z][\w:-]*)');
      final attribute = RegExp(r'\s([A-Za-z][\w:-]*)\s*=');
      for (final file in dir.listSync().whereType<File>()) {
        final svg = file.readAsStringSync();
        final name = file.uri.pathSegments.last;
        expect(tag.allMatches(svg).map((m) => m.group(1)).toSet(), {
          'svg',
          'path',
        }, reason: name);
        expect(attribute.allMatches(svg).map((m) => m.group(1)).toSet(), {
          'xmlns',
          'viewBox',
          'd',
        }, reason: name);
        expect(svg, isNot(contains('url(')), reason: name);
        expect(svg, contains('viewBox="0 0 512 512"'), reason: name);
      }
    });

    test('the class podium and the teacher\'s badges (#221) have glyphs by '
        'Delapouite, in the credits', () {
      final icons = BadgeCatalog.icons;
      for (final d in [BadgeCatalog.podium('s1'), ...BadgeCatalog.teacher]) {
        expect(d.icon.author, BadgeIcon.delapouite, reason: d.id);
        expect(icons, contains(d.icon), reason: d.id);
        expect(File(d.icon.asset).existsSync(), isTrue, reason: d.id);
      }
      expect(BadgeCatalog.podiumIcon.slug, 'sport-medal');
      expect(BadgeCatalog.teacher.map((d) => d.icon.slug), [
        'sherlock-holmes',
        'life-buoy',
        'think',
      ]);
    });

    test('every glyph names its author, for the credits', () {
      final authors = BadgeCatalog.icons.map((i) => i.author).toSet();
      expect(authors, {BadgeIcon.delapouite, BadgeIcon.lorc});
      expect(BadgeIcon.licence, 'CC BY 3.0');
      final owl = BadgeCatalog.byId('nightOwl')!.icon;
      expect(owl.author, BadgeIcon.lorc);
      expect(owl.title, 'Owl');
      expect(owl.sourceUrl, 'https://game-icons.net/1x1/lorc/owl.html');
      expect(BadgeCatalog.byId('effort')!.icon.title, 'Weight lifting up');
    });
  });

  group('the class podium and the teacher\'s badges (#221)', () {
    test('found by the id they are stored under; no rule counts them', () {
      final medal = BadgeCatalog.byId('podium:s1')!;
      expect(medal.group, BadgeGroup.podium);
      expect(medal.goalId, 's1');
      expect(medal.tiers, [1, 2, 3]);
      expect(medal.valueIn(BadgeFacts.empty), isNull);
      expect(medal.tierFor(medal.valueIn(BadgeFacts.empty)), 0);
      expect(BadgeCatalog.byId('podium:'), isNull);
      expect(BadgeCatalog.teacher.map((d) => d.id), [
        'teacher:faultFinder',
        'teacher:helpingHand',
        'teacher:goodQuestion',
      ]);
      for (final d in BadgeCatalog.teacher) {
        expect(BadgeCatalog.byId(d.id), d);
        expect(d.group, BadgeGroup.teacher);
        expect(d.secret, isFalse, reason: 'a student may know what it is for');
        expect(d.valueIn(BadgeFacts.empty), isNull);
      }
      expect(BadgeCatalog.byId('teacher:unknown'), isNull);
      // The rules never count them.
      final ruled = BadgeCatalog.all(expertGoalIds: ['r1']).map((d) => d.group);
      expect(ruled, isNot(contains(BadgeGroup.podium)));
      expect(ruled, isNot(contains(BadgeGroup.teacher)));
    });

    test('a medal says its metal and its subgoal; a teacher\'s badge its '
        'name, in Dutch and in English', () {
      final nl = lookupAppLocalizations(const Locale('nl'));
      final en = lookupAppLocalizations(const Locale('en'));
      final medal = BadgeCatalog.podium('s1');
      expect(
        badgeName(nl, medal, goalTitle: 'Variabelen', tier: 3),
        'Goud: Variabelen',
      );
      expect(
        badgeName(nl, medal, goalTitle: 'Variabelen', tier: 2),
        'Zilver: Variabelen',
      );
      expect(badgeName(nl, medal, tier: 1), 'Brons: een onderwerp');
      expect(
        badgeDescription(nl, medal, tier: 3),
        'Je rondde dit onderwerp als eerste van je klas af.',
      );
      expect(
        badgeDescription(en, medal, tier: 1),
        'You were the third in your class to finish this topic.',
      );
      expect(
        badgeName(nl, BadgeCatalog.byId('teacher:faultFinder')!),
        'Foutenjager',
      );
      expect(
        badgeName(nl, BadgeCatalog.byId('teacher:helpingHand')!),
        'Helpende hand',
      );
      expect(
        badgeName(nl, BadgeCatalog.byId('teacher:goodQuestion')!),
        'Goede vraag!',
      );
      expect(
        badgeDescription(nl, BadgeCatalog.byId('teacher:faultFinder')!),
        contains('#3fa91c'),
      );
      for (final l in [nl, en]) {
        final names = <String>{
          for (final d in BadgeCatalog.all(expertGoalIds: ['r1']))
            badgeName(l, d, goalTitle: 'Python'),
        };
        for (final d in BadgeCatalog.teacher) {
          expect(names.add(badgeName(l, d)), isTrue, reason: d.id);
          expect(badgeDescription(l, d).trim(), isNotEmpty, reason: d.id);
        }
      }
    });
  });

  test('every badge has a name and a rule in Dutch and in English', () {
    for (final locale in const [Locale('nl'), Locale('en')]) {
      final l = lookupAppLocalizations(locale);
      final names = <String>{};
      for (final d in all) {
        final name = badgeName(l, d, goalTitle: 'Python ${d.goalId}');
        final rule = badgeDescription(l, d, goalTitle: 'Python');
        expect(
          name.trim(),
          isNotEmpty,
          reason: '${locale.languageCode} ${d.id}',
        );
        expect(name, isNot(d.id), reason: '${locale.languageCode} ${d.id}');
        expect(
          rule.trim(),
          isNotEmpty,
          reason: '${locale.languageCode} ${d.id}',
        );
        names.add(name);
      }
      expect(names, hasLength(all.length), reason: 'no two badges alike');
    }
    final nl = lookupAppLocalizations(const Locale('nl'));
    expect(badgeName(nl, BadgeCatalog.byId('effort')!), 'Inzet');
    expect(
      badgeName(nl, BadgeCatalog.expert('r1'), goalTitle: 'Lussen'),
      'Kenner van Lussen',
    );
    expect(
      badgeDescription(nl, BadgeCatalog.byId('bugHunter')!),
      'Jij had gelijk, de computer niet.',
    );
  });
}
