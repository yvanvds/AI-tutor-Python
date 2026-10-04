// Every badge there is (#220): what it counts, its tiers, whether it is a
// secret, and its glyph with the glyph's author.
//
// Two promises the teacher made, and that nothing here may break:
//
//   - a badge is worth no XP — XP is for having worked (#217), a badge for
//     a moment worth marking;
//   - badges, like XP, never touch a grade.
//
// The tiers are set on the real numbers (23 students, 2 September to
// 2 October) and on a school year of about six such months: the first tier
// comes quickly, the highest only for the hardest workers by June. What a
// tier is worth may change later; what a student earned stays (see
// `earned_badges.dart`).
//
// The glyphs are from game-icons.net, under CC BY 3.0: every [BadgeIcon]
// names its author, and Options → About lists them with the licence. The
// files under `assets/badges/` are the repository's own SVGs with the black
// background square and the white fill taken out, so the frame can colour
// the glyph (`badge_style.dart`). Delapouite's where there is a fitting one
// — the cleanest style — and Lorc's for the owl and the pie.

import 'package:ai_tutor_python/services/badges/badge_facts.dart';
import 'package:ai_tutor_python/services/tutor/bank_choice.dart';
import 'package:flutter/foundation.dart';

/// A badge's glyph: one icon of game-icons.net.
@immutable
class BadgeIcon {
  const BadgeIcon(this.slug, {this.author = delapouite});

  static const String delapouite = 'Delapouite';
  static const String lorc = 'Lorc';

  /// The licence of every icon on game-icons.net.
  static const String licence = 'CC BY 3.0';
  static const String licenceUrl =
      'https://creativecommons.org/licenses/by/3.0/';

  /// The icon's name on game-icons.net, e.g. `weight-lifting-up`.
  final String slug;

  /// Who drew it.
  final String author;

  /// The bundled SVG.
  String get asset => 'assets/badges/$slug.svg';

  /// Where the icon lives on game-icons.net.
  String get sourceUrl =>
      'https://game-icons.net/1x1/${author.toLowerCase()}/$slug.html';

  /// The name as game-icons.net shows it: `Weight lifting up`.
  String get title {
    final words = slug.replaceAll('-', ' ');
    return words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);
  }

  @override
  bool operator ==(Object other) =>
      other is BadgeIcon && other.slug == slug && other.author == author;

  @override
  int get hashCode => Object.hash(slug, author);
}

/// Where a badge sits in the trophy case.
enum BadgeGroup {
  /// Badges in tiers: bronze, silver, gold, and dots past the third.
  tiers,

  /// "Kenner van {hoofddoel}": one per hoofddoel, all its LOs mastered.
  experts,

  /// The single, not so serious ones — most of them secret.
  fun,
}

/// One badge.
@immutable
class BadgeDefinition {
  const BadgeDefinition({
    required this.id,
    required this.group,
    required this.tiers,
    required this.icon,
    this.valueOf,
    this.secret = false,
    this.goalId,
  }) : assert(valueOf != null || goalId != null);

  /// What the account doc stores it under; never change one.
  final String id;

  final BadgeGroup group;

  /// The value each tier needs, lowest first. A single badge has one.
  final List<int> tiers;

  final BadgeIcon icon;

  /// The number in [BadgeFacts] this badge counts; `null` when it cannot be
  /// known (the lesson badges without lesson times). Unused for a "Kenner
  /// van …" badge, which reads [goalId]'s progress.
  final int? Function(BadgeFacts facts)? valueOf;

  /// Shown as a "?" until it is earned.
  final bool secret;

  /// The hoofddoel of a "Kenner van …" badge.
  final String? goalId;

  int get maxTier => tiers.length;

  /// What the student has for this badge now; `null` when it cannot be
  /// known.
  int? valueIn(BadgeFacts facts) {
    final goal = goalId;
    if (goal == null) return valueOf!(facts);
    final experts = facts.experts;
    if (experts == null) return null;
    final progress = experts[goal];
    if (progress == null) return 0;
    return progress.mastered >= progress.total ? 1 : 0;
  }

  /// The tier [value] reaches: 0 for none.
  int tierFor(int? value) {
    if (value == null) return 0;
    var tier = 0;
    for (final threshold in tiers) {
      if (value >= threshold) tier++;
    }
    return tier;
  }

  /// What the next tier after [tier] needs; `null` at the top.
  int? nextThreshold(int tier) =>
      tier >= 0 && tier < tiers.length ? tiers[tier] : null;

  @override
  bool operator ==(Object other) => other is BadgeDefinition && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The id of hoofddoel [goalId]'s "Kenner van …" badge.
String expertBadgeId(String goalId) => 'expert:$goalId';

// The numbers the badges count. Top-level so the catalog stays `const`.
int? _oefeningen(BadgeFacts f) => f.oefeningen;
int? _correct(BadgeFacts f) => f.correctOefeningen;
int? _home(BadgeFacts f) => f.homeOefeningen;
int? _lessonWeeks(BadgeFacts f) => f.lessonWeeks;
int? _hard(BadgeFacts f) => f.hardCorrect;
int? _streak(BadgeFacts f) => f.bestStreak;
int? _completeCode(BadgeFacts f) => f.correctByType['completeCodeQuestion'];
int? _explainCode(BadgeFacts f) => f.correctByType['explainCodeQuestion'];
int? _writeCode(BadgeFacts f) => f.correctByType['writeCodeQuestion'];
int? _allRounder(BadgeFacts f) =>
    f.correctOnEach(BankChoice.servedTypes.map((t) => t.name));
int? _knowledge(BadgeFacts f) => f.masteredLos;
int? _milestones(BadgeFacts f) => f.milestones;
int? _warmUp(BadgeFacts f) => f.warmUpCorrect;
int? _recheck(BadgeFacts f) => f.recheckCorrect;
int? _transfer(BadgeFacts f) => f.transferCredits;
int? _comeback(BadgeFacts f) => f.comebacks;
int? _wrongToRight(BadgeFacts f) => f.wrongToRight;
int? _hint(BadgeFacts f) => f.hintHits;
int? _persevered(BadgeFacts f) => f.persevered;
int? _toughest(BadgeFacts f) => f.toughest;
int? _earlyBird(BadgeFacts f) => f.earlyBird;
int? _nightOwl(BadgeFacts f) => f.nightOwl;
int? _weekend(BadgeFacts f) => f.weekend;
int? _friday(BadgeFacts f) => f.fridayAfternoonCorrect;
int? _piMinute(BadgeFacts f) => f.piMinute;
int? _piDay(BadgeFacts f) => f.piDay;
int? _halloween(BadgeFacts f) => f.halloween;
int? _ownQuestions(BadgeFacts f) => f.ownQuestions;
int? _backToFinished(BadgeFacts f) => f.backToFinished;
int? _keyDisputes(BadgeFacts f) => f.keyDisputes;
int? _slowCorrect(BadgeFacts f) => f.slowCorrect;

class BadgeCatalog {
  BadgeCatalog._();

  /// The glyph of every "Kenner van …" badge.
  static const BadgeIcon expertIcon = BadgeIcon('graduate-cap');

  /// The badges in tiers, in the order the trophy case shows them.
  static const List<BadgeDefinition> tiered = [
    BadgeDefinition(
      id: 'effort',
      group: BadgeGroup.tiers,
      tiers: [10, 100, 250, 500, 1000, 1500],
      icon: BadgeIcon('weight-lifting-up'),
      valueOf: _oefeningen,
    ),
    BadgeDefinition(
      id: 'homeWork',
      group: BadgeGroup.tiers,
      tiers: [50, 100, 250, 500, 1000],
      icon: BadgeIcon('house'),
      valueOf: _home,
    ),
    BadgeDefinition(
      id: 'lessonWeeks',
      group: BadgeGroup.tiers,
      tiers: [5, 10, 20, 30],
      icon: BadgeIcon('calendar'),
      valueOf: _lessonWeeks,
    ),
    BadgeDefinition(
      id: 'hardCorrect',
      group: BadgeGroup.tiers,
      tiers: [100, 250, 500, 750],
      icon: BadgeIcon('summits'),
      valueOf: _hard,
    ),
    BadgeDefinition(
      id: 'streak',
      group: BadgeGroup.tiers,
      tiers: [10, 20, 30, 50],
      icon: BadgeIcon('running-shoe'),
      valueOf: _streak,
    ),
    BadgeDefinition(
      id: 'gapFiller',
      group: BadgeGroup.tiers,
      tiers: [50, 100, 250],
      icon: BadgeIcon('puzzle'),
      valueOf: _completeCode,
    ),
    BadgeDefinition(
      id: 'fluentPython',
      group: BadgeGroup.tiers,
      tiers: [10, 25, 50],
      icon: BadgeIcon('snake-tongue'),
      valueOf: _explainCode,
    ),
    BadgeDefinition(
      id: 'writer',
      group: BadgeGroup.tiers,
      tiers: [3, 10, 20],
      icon: BadgeIcon('pencil'),
      valueOf: _writeCode,
    ),
    BadgeDefinition(
      id: 'allRounder',
      group: BadgeGroup.tiers,
      tiers: [3, 10, 20],
      icon: BadgeIcon('swiss-army-knife'),
      valueOf: _allRounder,
    ),
    BadgeDefinition(
      id: 'knowledge',
      group: BadgeGroup.tiers,
      tiers: [10, 25, 50, 100, 200],
      icon: BadgeIcon('book-pile'),
      valueOf: _knowledge,
    ),
    BadgeDefinition(
      id: 'milestones',
      group: BadgeGroup.tiers,
      tiers: [5, 10, 25, 50],
      icon: BadgeIcon('stairs-goal'),
      valueOf: _milestones,
    ),
    BadgeDefinition(
      id: 'elephantMemory',
      group: BadgeGroup.tiers,
      tiers: [5, 10, 25, 50],
      icon: BadgeIcon('elephant'),
      valueOf: _warmUp,
    ),
    BadgeDefinition(
      id: 'stillSharp',
      group: BadgeGroup.tiers,
      tiers: [1, 5, 10, 25],
      icon: BadgeIcon('alarm-clock'),
      valueOf: _recheck,
    ),
    BadgeDefinition(
      id: 'oldFriend',
      group: BadgeGroup.tiers,
      tiers: [50, 100, 250, 500],
      icon: BadgeIcon('shaking-hands'),
      valueOf: _transfer,
    ),
    BadgeDefinition(
      id: 'comeback',
      group: BadgeGroup.tiers,
      tiers: [1, 3, 5, 10],
      icon: BadgeIcon('boomerang'),
      valueOf: _comeback,
    ),
    BadgeDefinition(
      id: 'wrongToRight',
      group: BadgeGroup.tiers,
      tiers: [10, 25, 50, 100],
      icon: BadgeIcon('check-mark'),
      valueOf: _wrongToRight,
    ),
    BadgeDefinition(
      id: 'hintHit',
      group: BadgeGroup.tiers,
      tiers: [10, 25, 50, 100],
      icon: BadgeIcon('idea'),
      valueOf: _hint,
    ),
    BadgeDefinition(
      id: 'persevere',
      group: BadgeGroup.tiers,
      tiers: [1, 3, 10, 20],
      icon: BadgeIcon('push'),
      valueOf: _persevered,
    ),
    BadgeDefinition(
      id: 'tough',
      group: BadgeGroup.tiers,
      tiers: [20, 30, 50],
      icon: BadgeIcon('tortoise'),
      valueOf: _toughest,
    ),
  ];

  /// The single badges, in the order the trophy case shows them. Only the
  /// first is no secret.
  static const List<BadgeDefinition> fun = [
    BadgeDefinition(
      id: 'helloWorld',
      group: BadgeGroup.fun,
      tiers: [1],
      icon: BadgeIcon('earth-africa-europe'),
      valueOf: _oefeningen,
    ),
    BadgeDefinition(
      id: 'fortyTwo',
      group: BadgeGroup.fun,
      tiers: [42],
      icon: BadgeIcon('towel'),
      valueOf: _oefeningen,
      secret: true,
    ),
    BadgeDefinition(
      id: 'offByOne',
      group: BadgeGroup.fun,
      tiers: [99],
      icon: BadgeIcon('abacus'),
      valueOf: _correct,
      secret: true,
    ),
    BadgeDefinition(
      id: 'earlyBird',
      group: BadgeGroup.fun,
      tiers: [1],
      icon: BadgeIcon('rooster'),
      valueOf: _earlyBird,
      secret: true,
    ),
    BadgeDefinition(
      id: 'nightOwl',
      group: BadgeGroup.fun,
      tiers: [1],
      icon: BadgeIcon('owl', author: BadgeIcon.lorc),
      valueOf: _nightOwl,
      secret: true,
    ),
    BadgeDefinition(
      id: 'weekendWarrior',
      group: BadgeGroup.fun,
      tiers: [1],
      icon: BadgeIcon('viking-helmet'),
      valueOf: _weekend,
      secret: true,
    ),
    BadgeDefinition(
      id: 'fridayHero',
      group: BadgeGroup.fun,
      tiers: [1],
      icon: BadgeIcon('sunglasses'),
      valueOf: _friday,
      secret: true,
    ),
    BadgeDefinition(
      id: 'piHour',
      group: BadgeGroup.fun,
      tiers: [1],
      icon: BadgeIcon('watch'),
      valueOf: _piMinute,
      secret: true,
    ),
    BadgeDefinition(
      id: 'piDay',
      group: BadgeGroup.fun,
      tiers: [1],
      icon: BadgeIcon('pie-slice', author: BadgeIcon.lorc),
      valueOf: _piDay,
      secret: true,
    ),
    BadgeDefinition(
      id: 'spookyCode',
      group: BadgeGroup.fun,
      tiers: [1],
      icon: BadgeIcon('floating-ghost'),
      valueOf: _halloween,
      secret: true,
    ),
    BadgeDefinition(
      id: 'rubberDuck',
      group: BadgeGroup.fun,
      tiers: [1],
      icon: BadgeIcon('plastic-duck'),
      valueOf: _ownQuestions,
      secret: true,
    ),
    BadgeDefinition(
      id: 'ctrlZ',
      group: BadgeGroup.fun,
      tiers: [1],
      icon: BadgeIcon('backward-time'),
      valueOf: _backToFinished,
      secret: true,
    ),
    BadgeDefinition(
      id: 'bugHunter',
      group: BadgeGroup.fun,
      tiers: [1],
      icon: BadgeIcon('bug-net'),
      valueOf: _keyDisputes,
      secret: true,
    ),
    BadgeDefinition(
      id: 'rome',
      group: BadgeGroup.fun,
      tiers: [1],
      icon: BadgeIcon('aqueduct'),
      valueOf: _slowCorrect,
      secret: true,
    ),
  ];

  /// The "Kenner van …" badge of hoofddoel [goalId].
  static BadgeDefinition expert(String goalId) => BadgeDefinition(
    id: expertBadgeId(goalId),
    group: BadgeGroup.experts,
    tiers: const [1],
    icon: expertIcon,
    goalId: goalId,
  );

  /// Every badge, with a "Kenner van …" one per hoofddoel in [expertGoalIds]
  /// (in that order), between the tiers and the single ones.
  static List<BadgeDefinition> all({
    Iterable<String> expertGoalIds = const [],
  }) => [...tiered, for (final id in expertGoalIds) expert(id), ...fun];

  /// The badge stored under [id]; `null` for one this build does not know.
  static BadgeDefinition? byId(String id) {
    if (id.startsWith('expert:')) return expert(id.substring(7));
    for (final d in tiered) {
      if (d.id == id) return d;
    }
    for (final d in fun) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Every glyph in use, once each, for the credits.
  static List<BadgeIcon> get icons {
    final seen = <BadgeIcon>{};
    return [
      for (final d in [...tiered, expert(''), ...fun])
        if (seen.add(d.icon)) d.icon,
    ];
  }
}
