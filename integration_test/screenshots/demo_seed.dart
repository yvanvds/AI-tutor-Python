// The demo class behind the site screenshots (#290).
//
// Everything here is invented: the class, the names, the e-mail addresses
// (on the reserved `.example` domain), the answers, the grades and the
// texts. Nothing is read from Cosmos or from any other real source — the
// repository and the site are public, and the teacher pages of the real app
// show real students. Keep it that way: a new screen gets new invented data
// here, never a copy of something that happened.
//
// The curriculum is a small version of the real one (simple scripts,
// conditions, repetition, lists), written in Dutch like the real goals, with
// an English translation of every title, statement and lesson, so the English
// screenshots read as English. The timestamps are relative to the moment the
// run starts, so the teacher's chart of the last 30 days always has data.
//
// The badges stored on the demo student's account are counted from the
// history below with the app's own rules (`BadgeFacts`, `BadgeCatalog`), the
// way `BadgeService` counts them at start: what is stored equals what the
// history earns, so no "new badge" notice covers a screenshot.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/core/token_usage.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/badges/badge_catalog.dart';
import 'package:ai_tutor_python/services/badges/badge_facts.dart';
import 'package:ai_tutor_python/services/badges/class_podium.dart';
import 'package:ai_tutor_python/services/badges/earned_badges.dart';
import 'package:ai_tutor_python/services/classes/school_class.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/grading/grade_formula.dart';
import 'package:ai_tutor_python/services/grading/grade_proposal.dart';
import 'package:ai_tutor_python/services/grading/milestone.dart';
import 'package:ai_tutor_python/services/playground/playground_files_service.dart';
import 'package:ai_tutor_python/services/progress/progress_sample.dart';
import 'package:ai_tutor_python/services/question_bank/bank_question.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/supervision/supervision_source.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/complete_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:ai_tutor_python/services/tutor/responses/write_code.dart';

/// The two languages every screen is taken in.
enum DemoLanguage {
  nl,
  en;

  String get code => name;

  /// [nl] or [en], whichever this is.
  String pick(String nl, String en) => this == DemoLanguage.nl ? nl : en;
}

/// The demo class. Invented, like everything else here.
const String kDemoClass = '5ICT';

/// A second class, so the Students page has more than one.
const String kDemoOtherClass = '5WE';

const AccountIdentity demoStudent = AccountIdentity(
  oid: 'demo-mila',
  displayName: 'Mila Verbeke',
  email: 'mila.verbeke@school.example',
  firstName: 'Mila',
  lastName: 'Verbeke',
  isTeacher: false,
);

const AccountIdentity demoTeacher = AccountIdentity(
  oid: 'demo-teacher',
  displayName: 'Hilde Claes',
  email: 'hilde.claes@school.example',
  firstName: 'Hilde',
  lastName: 'Claes',
  isTeacher: true,
);

/// The classmates on the teacher's pages: uid, first and last name, class,
/// how far along the curriculum they are (subgoals finished, then the share
/// of the next one), their streak, and the grade proposal on the report.
typedef _Classmate = ({
  String uid,
  String first,
  String last,
  String className,
  int finished,
  double current,
  int streak,
  int grade,
  bool signed,
});

const List<_Classmate> _classmates = [
  (
    uid: 'demo-ruben',
    first: 'Ruben',
    last: 'Maes',
    className: kDemoClass,
    finished: 6,
    current: 0.5,
    streak: 6,
    grade: 84,
    signed: true,
  ),
  (
    uid: 'demo-noor',
    first: 'Noor',
    last: 'Wouters',
    className: kDemoClass,
    finished: 5,
    current: 0.0,
    streak: 2,
    grade: 78,
    signed: true,
  ),
  (
    uid: 'demo-lucas',
    first: 'Lucas',
    last: 'Jacobs',
    className: kDemoClass,
    finished: 3,
    current: 0.5,
    streak: 0,
    grade: 55,
    signed: false,
  ),
  (
    uid: 'demo-elise',
    first: 'Elise',
    last: 'Vermeulen',
    className: kDemoClass,
    finished: 4,
    current: 0.67,
    streak: 3,
    grade: 69,
    signed: false,
  ),
  (
    uid: 'demo-finn',
    first: 'Finn',
    last: 'De Smet',
    className: kDemoClass,
    finished: 2,
    current: 0.5,
    streak: 1,
    grade: 46,
    signed: false,
  ),
  (
    uid: 'demo-zoe',
    first: 'Zoë',
    last: 'Hermans',
    className: kDemoClass,
    finished: 7,
    current: 0.0,
    streak: 9,
    grade: 91,
    signed: true,
  ),
  (
    uid: 'demo-arthur',
    first: 'Arthur',
    last: 'Goossens',
    className: kDemoClass,
    finished: 4,
    current: 0.33,
    streak: 0,
    grade: 64,
    signed: false,
  ),
  (
    uid: 'demo-lina',
    first: 'Lina',
    last: 'Mertens',
    className: kDemoOtherClass,
    finished: 3,
    current: 1 / 3,
    streak: 2,
    grade: 0,
    signed: false,
  ),
  (
    uid: 'demo-jules',
    first: 'Jules',
    last: 'Willems',
    className: kDemoOtherClass,
    finished: 2,
    current: 0.5,
    streak: 4,
    grade: 0,
    signed: false,
  ),
  (
    uid: 'demo-hanne',
    first: 'Hanne',
    last: 'Peeters',
    className: kDemoOtherClass,
    finished: 1,
    current: 0.0,
    streak: 1,
    grade: 0,
    signed: false,
  ),
];

/// The subgoal the demo student is on.
const String kDemoCurrentSubgoal = 's5';

/// The root goal the demo student is on.
const String kDemoCurrentRoot = 'r2';

/// The demo student's oefeningen. 125 × 20 XP plus 433 mastery XP is
/// 2933 XP: level 6, 433 of 500 — so finishing [kDemoCurrentSubgoal] (67 XP
/// more) reaches level 7, which is what the level-up screen shows.
const int kDemoOefeningCount = 125;

// ---- Curriculum -------------------------------------------------------------

typedef _Lo = ({String id, String kind, String nl, String en});

typedef _Goal = ({
  String id,
  String? parentId,
  int order,
  String nl,
  String en,
  String nlDescription,
  String enDescription,
  List<_Lo> los,
});

const List<_Goal> _goals = [
  (
    id: 'r1',
    parentId: null,
    order: 1000,
    nl: 'Eenvoudige Python-scripts',
    en: 'Simple Python scripts',
    nlDescription: 'Je eerste programma\'s: tekst tonen, rekenen en invoer.',
    enDescription: 'Your first programs: showing text, calculating, input.',
    los: [],
  ),
  (
    id: 's1',
    parentId: 'r1',
    order: 1000,
    nl: 'Tekst tonen met print',
    en: 'Showing text with print',
    nlDescription: '',
    enDescription: '',
    los: [
      (
        id: 'lo-print',
        kind: 'apply',
        nl: 'Je kan tekst en getallen tonen met print().',
        en: 'You can show text and numbers with print().',
      ),
    ],
  ),
  (
    id: 's2',
    parentId: 'r1',
    order: 2000,
    nl: 'Variabelen',
    en: 'Variables',
    nlDescription: '',
    enDescription: '',
    los: [
      (
        id: 'lo-assign',
        kind: 'apply',
        nl: 'Je kan een waarde aan een naam geven.',
        en: 'You can give a value a name.',
      ),
      (
        id: 'lo-calc',
        kind: 'apply',
        nl: 'Je kan rekenen met variabelen.',
        en: 'You can calculate with variables.',
      ),
    ],
  ),
  (
    id: 's3',
    parentId: 'r1',
    order: 3000,
    nl: 'Invoer van de gebruiker',
    en: 'Input from the user',
    nlDescription: '',
    enDescription: '',
    los: [
      (
        id: 'lo-input',
        kind: 'apply',
        nl: 'Je kan de gebruiker iets laten typen met input().',
        en: 'You can let the user type something with input().',
      ),
      (
        id: 'lo-int',
        kind: 'apply',
        nl: 'Je kan tekst omzetten naar een getal.',
        en: 'You can turn text into a number.',
      ),
    ],
  ),
  (
    id: 'r2',
    parentId: null,
    order: 2000,
    nl: 'Condities',
    en: 'Conditions',
    nlDescription: 'Je programma laten kiezen: vergelijken, if, else en elif.',
    enDescription: 'Letting your program choose: comparing, if, else, elif.',
    los: [],
  ),
  (
    id: 's4',
    parentId: 'r2',
    order: 1000,
    nl: 'Vergelijkingen',
    en: 'Comparisons',
    nlDescription: '',
    enDescription: '',
    los: [
      (
        id: 'lo-compare',
        kind: 'apply',
        nl: 'Je kan twee waarden vergelijken met <, >, == en !=.',
        en: 'You can compare two values with <, >, == and !=.',
      ),
      (
        id: 'lo-bool',
        kind: 'predict',
        nl: 'Je kan voorspellen of een vergelijking True of False is.',
        en: 'You can predict whether a comparison is True or False.',
      ),
    ],
  ),
  (
    id: 's5',
    parentId: 'r2',
    order: 2000,
    nl: 'Beslissingen met if en else',
    en: 'Decisions with if and else',
    nlDescription: '',
    enDescription: '',
    los: [
      (
        id: 'lo-if',
        kind: 'apply',
        nl: 'Je kan code laten uitvoeren als een voorwaarde waar is.',
        en: 'You can run code only when a condition is true.',
      ),
      (
        id: 'lo-else',
        kind: 'apply',
        nl: 'Je kan met else zeggen wat er anders moet gebeuren.',
        en: 'You can use else to say what happens otherwise.',
      ),
      (
        id: 'lo-trace',
        kind: 'predict',
        nl: 'Je kan voorspellen welke tak van een if-else uitgevoerd wordt.',
        en: 'You can predict which branch of an if-else runs.',
      ),
    ],
  ),
  (
    id: 's6',
    parentId: 'r2',
    order: 3000,
    nl: 'elif en samengestelde voorwaarden',
    en: 'elif and compound conditions',
    nlDescription: '',
    enDescription: '',
    los: [
      (
        id: 'lo-elif',
        kind: 'apply',
        nl: 'Je kan meer dan twee gevallen onderscheiden met elif.',
        en: 'You can tell more than two cases apart with elif.',
      ),
      (
        id: 'lo-andor',
        kind: 'apply',
        nl: 'Je kan voorwaarden combineren met and en or.',
        en: 'You can combine conditions with and and or.',
      ),
    ],
  ),
  (
    id: 'r3',
    parentId: null,
    order: 3000,
    nl: 'Herhaling',
    en: 'Repetition',
    nlDescription: 'Code herhalen met for en while.',
    enDescription: 'Repeating code with for and while.',
    los: [],
  ),
  (
    id: 's7',
    parentId: 'r3',
    order: 1000,
    nl: 'De for-lus',
    en: 'The for loop',
    nlDescription: '',
    enDescription: '',
    los: [
      (
        id: 'lo-for',
        kind: 'apply',
        nl: 'Je kan code een aantal keer herhalen met for en range().',
        en: 'You can repeat code a number of times with for and range().',
      ),
    ],
  ),
  (
    id: 's8',
    parentId: 'r3',
    order: 2000,
    nl: 'De while-lus',
    en: 'The while loop',
    nlDescription: '',
    enDescription: '',
    los: [
      (
        id: 'lo-while',
        kind: 'apply',
        nl: 'Je kan herhalen zolang een voorwaarde waar is.',
        en: 'You can repeat while a condition is true.',
      ),
    ],
  ),
  (
    id: 'r4',
    parentId: null,
    order: 4000,
    nl: 'Lijsten',
    en: 'Lists',
    nlDescription: 'Meer waarden in één variabele.',
    enDescription: 'Many values in one variable.',
    los: [],
  ),
  (
    id: 's9',
    parentId: 'r4',
    order: 1000,
    nl: 'Lijsten maken en lezen',
    en: 'Making and reading lists',
    nlDescription: '',
    enDescription: '',
    los: [
      (
        id: 'lo-list',
        kind: 'apply',
        nl: 'Je kan een lijst maken en een element lezen met een index.',
        en: 'You can make a list and read an element by its index.',
      ),
    ],
  ),
];

/// The subgoals in curriculum order — the order a student finishes them in.
final List<_Goal> _subgoals = [
  for (final root in _goals.where((g) => g.parentId == null))
    ..._goals.where((g) => g.parentId == root.id),
];

Map<String, dynamic> _goalDoc(_Goal g) => {
  'id': g.id,
  'type': 'goal',
  'title': g.nl,
  'description': g.nlDescription,
  'parentId': g.parentId,
  'order': g.order,
  'optional': false,
  'teachingTips': const <String>[],
  'allowChains': false,
  'objectives': [
    for (final lo in g.los)
      {
        'id': lo.id,
        'statement': lo.nl,
        'kind': lo.kind,
        'weight': 1.0,
        'optional': false,
      },
  ],
  'contentId': _lessons.containsKey(g.id) ? g.id : null,
  'moduleId': 'python-basics',
};

// ---- Lessons ----------------------------------------------------------------

/// The live example of the lesson the demo student is on, and what it
/// prints, per language.
String demoLessonCode(DemoLanguage lang) => lang.pick(
  'temperatuur = 24\n'
      '\n'
      'if temperatuur > 20:\n'
      '    print("Neem een t-shirt mee.")\n'
      'else:\n'
      '    print("Neem een trui mee.")\n'
      'print("Fijne dag!")',
  'temperature = 24\n'
      '\n'
      'if temperature > 20:\n'
      '    print("Bring a T-shirt.")\n'
      'else:\n'
      '    print("Bring a sweater.")\n'
      'print("Have a nice day!")',
);

String demoLessonOutput(DemoLanguage lang) => lang.pick(
  'Neem een t-shirt mee.\nFijne dag!',
  'Bring a T-shirt.\nHave a nice day!',
);

String _escape(String code) => code
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _ifElseLesson(DemoLanguage lang) =>
    '<p>${lang.pick('Met <code>if</code> laat je je programma kiezen. De code die inspringt onder <code>if</code> loopt alleen als de voorwaarde <code>True</code> is. Is ze <code>False</code>, dan loopt de code onder <code>else</code>.', 'With <code>if</code> your program makes a choice. The indented code under <code>if</code> only runs when the condition is <code>True</code>. When it is <code>False</code>, the code under <code>else</code> runs instead.')}</p>'
    '<h2>${lang.pick('Twee kanten op', 'Two ways to go')}</h2>'
    '<p>${lang.pick('Verander de temperatuur en kijk wat het programma dan toont. Precies één van de twee blokken loopt, nooit allebei.', 'Change the temperature and see what the program shows. Exactly one of the two blocks runs, never both.')}</p>'
    '<pre class="run"><code>${_escape(demoLessonCode(lang))}</code></pre>'
    '<p>${lang.pick('De laatste regel springt niet in: die hoort niet bij de <code>if</code> en loopt dus altijd.', 'The last line is not indented: it is not part of the <code>if</code>, so it always runs.')}</p>'
    '<div class="callout warn"><p>${lang.pick('Vergeet de dubbele punt niet, na de voorwaarde en na <code>else</code>. Zonder dubbele punt weigert Python je programma.', 'Do not forget the colon, after the condition and after <code>else</code>. Without it, Python refuses to run your program.')}</p></div>'
    '<h2>${lang.pick('Een vergelijking als voorwaarde', 'A comparison as the condition')}</h2>'
    '<p>${lang.pick('De voorwaarde is meestal een vergelijking, zoals je die in de vorige les leerde: <code>&gt;</code>, <code>&lt;</code>, <code>==</code> of <code>!=</code>.', 'The condition is usually a comparison, like the ones from the previous lesson: <code>&gt;</code>, <code>&lt;</code>, <code>==</code> or <code>!=</code>.')}</p>';

String _shortLesson(DemoLanguage lang, String nl, String en, String code) =>
    '<p>${lang.pick(nl, en)}</p><pre><code>${_escape(code)}</code></pre>';

/// The lessons, by subgoal (a lesson's id is its subgoal's): title and body
/// per language.
final Map<
  String,
  ({String nlTitle, String enTitle, String Function(DemoLanguage) body})
>
_lessons = {
  's1': (
    nlTitle: 'Tekst tonen met print',
    enTitle: 'Showing text with print',
    body: (l) => _shortLesson(
      l,
      'Met <code>print()</code> toon je tekst op het scherm.',
      'With <code>print()</code> you show text on the screen.',
      'print("Hallo!")',
    ),
  ),
  's2': (
    nlTitle: 'Variabelen',
    enTitle: 'Variables',
    body: (l) => _shortLesson(
      l,
      'Een variabele is een naam voor een waarde.',
      'A variable is a name for a value.',
      'leeftijd = 16\nprint(leeftijd + 1)',
    ),
  ),
  's3': (
    nlTitle: 'Invoer van de gebruiker',
    enTitle: 'Input from the user',
    body: (l) => _shortLesson(
      l,
      'Met <code>input()</code> laat je de gebruiker iets typen.',
      'With <code>input()</code> the user can type something.',
      'naam = input("Hoe heet je? ")',
    ),
  ),
  's4': (
    nlTitle: 'Vergelijkingen',
    enTitle: 'Comparisons',
    body: (l) => _shortLesson(
      l,
      'Een vergelijking is <code>True</code> of <code>False</code>.',
      'A comparison is either <code>True</code> or <code>False</code>.',
      'print(3 > 2)',
    ),
  ),
  's5': (
    nlTitle: 'Beslissingen met if en else',
    enTitle: 'Decisions with if and else',
    body: _ifElseLesson,
  ),
  's6': (
    nlTitle: 'elif en samengestelde voorwaarden',
    enTitle: 'elif and compound conditions',
    body: (l) => _shortLesson(
      l,
      'Met <code>elif</code> onderscheid je meer dan twee gevallen.',
      'With <code>elif</code> you tell more than two cases apart.',
      'if punten >= 16:\n    print("top")\nelif punten >= 10:\n    print("goed")',
    ),
  ),
};

// ---- Dates ------------------------------------------------------------------

/// The class's lessons: Tuesday 10:25–11:15 and Thursday 13:30–14:20.
List<Map<String, dynamic>> _lessonTimes() => [
  {'weekday': DateTime.tuesday, 'start': '10:25', 'end': '11:15'},
  {'weekday': DateTime.thursday, 'start': '13:30', 'end': '14:20'},
];

Map<String, dynamic> _classesDoc() => {
  'id': CosmosDocId.classes,
  'type': 'config',
  'classes': [
    {'name': kDemoClass, 'lessons': _lessonTimes()},
    {
      'name': kDemoOtherClass,
      'lessons': [
        {'weekday': DateTime.monday, 'start': '08:30', 'end': '10:10'},
      ],
    },
  ],
  'updatedAt': '2026-09-01T08:00:00.000Z',
};

/// Midnight, local time, [days] days before [now]. Counted in calendar
/// days, not in 24-hour steps: across the change to winter time those land
/// an hour off, and a lesson at 10:30 becomes one at 11:30.
DateTime _day(DateTime now, int days) =>
    DateTime(now.year, now.month, now.day - days);

// ---- The demo student's history -------------------------------------------

/// Where the oefeningen of [_history] go, in order: how many each subgoal
/// got, the last one finishing it (but the current one).
const List<({String subgoal, int count})> _historyPlan = [
  (subgoal: 's1', count: 18),
  (subgoal: 's2', count: 26),
  (subgoal: 's3', count: 25),
  (subgoal: 's4', count: 31),
  (subgoal: 's5', count: 25),
];

const List<String> _questionTypes = [
  'completeCodeQuestion',
  'mcQuestion',
  'writeCodeQuestion',
  'completeCodeQuestion',
  'explainCodeQuestion',
];

/// The moments of [kDemoOefeningCount] oefeningen over the last six weeks:
/// ten in every lesson of [kDemoClass] (Tuesday 10:30, Thursday 13:35, four
/// minutes apart) and a few on Sunday evening at home, oldest first.
List<DateTime> _oefeningMoments(DateTime now) {
  final moments = <DateTime>[];
  for (var days = 44; days >= 1; days--) {
    final day = _day(now, days);
    final (int hour, int minute, int count) = switch (day.weekday) {
      DateTime.tuesday => (10, 30, 10),
      DateTime.thursday => (13, 35, 10),
      DateTime.sunday => (19, 30, 4),
      _ => (0, 0, 0),
    };
    for (var i = 0; i < count; i++) {
      moments.add(DateTime(day.year, day.month, day.day, hour, minute + 4 * i));
    }
  }
  return moments.length <= kDemoOefeningCount
      ? moments
      : moments.sublist(moments.length - kDemoOefeningCount);
}

/// The demo student's graded oefeningen, as `turn_history` holds them.
List<PersistedTurnRecord> _history(DateTime now) {
  final moments = _oefeningMoments(now);
  final records = <PersistedTurnRecord>[];
  var i = 0;
  for (final step in _historyPlan) {
    final goal = _goals.firstWhere((g) => g.id == step.subgoal);
    final finishes = step.subgoal != kDemoCurrentSubgoal;
    for (var k = 0; k < step.count && i < moments.length; k++, i++) {
      final lo = goal.los[k % goal.los.length];
      // Mostly right, now and then wrong or half: runs of right answers of
      // about a dozen, the way a steady student works.
      final quality = i % 13 == 6
          ? AnswerQuality.wrong
          : (i % 9 == 4 ? AnswerQuality.partial : AnswerQuality.correct);
      final last = k == step.count - 1;
      // The LOs of a finished subgoal are mastered in its second half; of
      // the current one only the first.
      final mastered = finishes
          ? k >= step.count ~/ 2
          : (lo.id == 'lo-if' && k >= 12);
      records.add(
        PersistedTurnRecord(
          id: CosmosDocId.turnHistory(moments[i]),
          turnAt: moments[i].toUtc(),
          subgoalId: step.subgoal,
          targetLOIds: [lo.id],
          questionType: _questionTypes[k % _questionTypes.length],
          difficulty: k > step.count * 2 ~/ 3
              ? QuestionDifficulty.hard
              : QuestionDifficulty.medium,
          isFollowUp: false,
          chainDepth: 0,
          selectionReason: null,
          overallQuality: quality,
          loSignals: const [],
          hadFallback: false,
          appliedSignals: const [],
          calibrationBefore: QuestionDifficulty.medium,
          calibrationAfter: QuestionDifficulty.medium,
          subgoalProgressAfter: finishes && last ? 1.0 : 0.0,
          loStatusAfter: [
            TurnLoStatus(
              loId: lo.id,
              mean: mastered ? 0.88 : 0.62,
              evidence: mastered ? 7 : 3,
              mastered: mastered,
              stuck: false,
            ),
          ],
          subgoalAdvanced: finishes && last,
          askedAt: moments[i].toUtc().subtract(const Duration(minutes: 2)),
          usage: const TurnUsage(
            byCall: {
              UsageCallKind.question: TokenUsage(
                promptTokens: 1840,
                completionTokens: 230,
              ),
              UsageCallKind.grading: TokenUsage(
                promptTokens: 1460,
                completionTokens: 170,
              ),
            },
            model: 'gpt-5-mini',
          ),
        ),
      );
    }
  }
  return records;
}

/// The places the demo student holds on the class podium: gold on
/// "Variables", bronze on "Comparisons".
List<PodiumPlace> _podiumPlaces(DateTime now) => [
  PodiumPlace(
    className: kDemoClass,
    subgoalId: 's2',
    place: 1,
    uid: demoStudent.oid,
    awardedAt: _day(now, 30).add(const Duration(hours: 11)).toUtc(),
  ),
  PodiumPlace(
    className: kDemoClass,
    subgoalId: 's4',
    place: 3,
    uid: demoStudent.oid,
    awardedAt: _day(now, 12).add(const Duration(hours: 14)).toUtc(),
  ),
];

/// What the account doc stores under `badges`: every badge [_history]
/// earns at the tier it earns it (counted the way `BadgeService` counts
/// them at start), the podium medals, and one badge from the teacher.
Map<String, dynamic> _badges(DateTime now, List<PersistedTurnRecord> history) {
  final goals = [for (final g in _goals) Goal.fromCosmos(_goalDoc(g))];
  final classes = ClassList.fromDoc(_classesDoc());
  final facts = BadgeFacts.from(
    records: history,
    goals: goals,
    inLesson: (at) => classes.isDuringLesson(
      kDemoClass,
      at,
      margin: ScheduleSupervisionSource.margin,
    ),
  );
  final roots = goals.where((g) => g.parentId == null).toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  final earnedAt = history.last.turnAt.toUtc().toIso8601String();
  return {
    for (final badge in BadgeCatalog.all(expertGoalIds: roots.map((g) => g.id)))
      if (badge.tierFor(badge.valueIn(facts)) > 0)
        badge.id: {
          'tier': badge.tierFor(badge.valueIn(facts)),
          'earnedAt': earnedAt,
        },
    for (final place in _podiumPlaces(now))
      podiumBadgeId(place.subgoalId): place.toEarned().toJson(),
    'teacher:helpingHand': {
      'tier': 1,
      'earnedAt': _day(
        now,
        9,
      ).add(const Duration(hours: 11)).toUtc().toIso8601String(),
      'awardedBy': kAwardedByTeacher,
      'count': 2,
      // Seen already: the student's app announced it the day it came.
      'seen': 2,
    },
  };
}

Map<String, dynamic> _account({
  required String uid,
  required String first,
  required String last,
  required String className,
  required int streak,
  required int oefeningCount,
  required DateTime lastActive,
  Map<String, dynamic>? badges,
}) => {
  'id': uid,
  'uid': uid,
  'email':
      '${first.toLowerCase().replaceAll('ë', 'e')}.${last.toLowerCase().replaceAll(' ', '')}@school.example',
  'firstName': first,
  'lastName': last,
  'targetGoal': '',
  'mayUseGlobalKey': true,
  'createdAt': '2026-09-01T08:00:00.000Z',
  'updatedAt': lastActive.toUtc().toIso8601String(),
  'calibration': {
    'difficulty': 'medium',
    'recentAnswers': const [],
    'recentQuestionTypes': const [],
  },
  'streakDays': streak,
  'className': className,
  'oefeningCount': oefeningCount,
  if (badges != null) 'badges': badges,
};

Map<String, dynamic> _progress(
  String uid,
  String goalId,
  double value,
  DateTime at, {
  bool root = false,
}) => {
  'id': '${uid}_$goalId',
  'uid': uid,
  'goalId': goalId,
  'progress': value,
  if (value >= 1.0 && !root) 'advancedAt': at.toUtc().toIso8601String(),
  'updatedAt': at.toUtc().toIso8601String(),
  'lastSessionAt': at.toUtc().toIso8601String(),
};

/// Progress docs for a student who finished the first [finished] subgoals
/// and is [current] of the way into the next, the last one [daysAgo] days
/// ago — and, as the conductor keeps them, one per goal they started: the
/// average of its subgoals.
List<Map<String, dynamic>> _progressOf(
  DateTime now,
  String uid, {
  required int finished,
  required double current,
  int daysAgo = 1,
}) {
  final last = _day(now, daysAgo).add(const Duration(hours: 11));
  final byGoal = <String, double>{
    for (var i = 0; i < finished && i < _subgoals.length; i++)
      _subgoals[i].id: 1.0,
    if (finished < _subgoals.length) _subgoals[finished].id: current,
  };
  return [
    for (var i = 0; i < _subgoals.length; i++)
      if (byGoal[_subgoals[i].id] case final value?)
        _progress(
          uid,
          _subgoals[i].id,
          value,
          i < finished
              ? _day(
                  now,
                  daysAgo + 3 * (finished - i),
                ).add(const Duration(hours: 11))
              : last,
        ),
    for (final root in _goals.where((g) => g.parentId == null))
      if (_goals.any((g) => g.parentId == root.id && byGoal.containsKey(g.id)))
        _progress(
          uid,
          root.id,
          [
                for (final g in _goals.where((g) => g.parentId == root.id))
                  byGoal[g.id] ?? 0.0,
              ].reduce((a, b) => a + b) /
              _goals.where((g) => g.parentId == root.id).length,
          last,
          root: true,
        ),
  ];
}

/// The demo student's beliefs: every LO of a finished subgoal mastered and
/// stamped, probed directly a few days ago; on the current subgoal the first
/// LO demonstrated, the second on its way and the third not asked yet.
List<Map<String, dynamic>> _beliefs(DateTime now) {
  Map<String, dynamic> belief(
    String subgoalId,
    String loId, {
    required double alpha,
    required double beta,
    required int daysAgo,
    bool stamped = false,
  }) {
    final at = _day(now, daysAgo).add(const Duration(hours: 11)).toUtc();
    return {
      'id': '${demoStudent.oid}_${subgoalId}_$loId',
      'type': 'lo_belief',
      'uid': demoStudent.oid,
      'subgoalId': subgoalId,
      'loId': loId,
      'alpha': alpha,
      'beta': beta,
      'lastUpdatedAt': at.toIso8601String(),
      'lastQuestionType': 'completeCodeQuestion',
      'lastPositiveAtCalibratedAt': at.toIso8601String(),
      'highestPositiveDifficulty': stamped ? 'hard' : 'medium',
      'recentNegativesAtCalibrated': 0,
      if (stamped) 'firstMasteredAt': at.toIso8601String(),
      'lastProbedAt': at.toIso8601String(),
      'thinCheckedAt': at.toIso8601String(),
      'ownQuestions': 4,
      'ownQuestionsRight': 3,
      'ownQuestionsRightNonMcq': 2,
    };
  }

  return [
    for (final g in _subgoals.take(4))
      for (final lo in g.los)
        belief(g.id, lo.id, alpha: 9, beta: 1, daysAgo: 3, stamped: true),
    belief('s5', 'lo-if', alpha: 6, beta: 1, daysAgo: 2, stamped: true),
    belief('s5', 'lo-else', alpha: 2.4, beta: 1.3, daysAgo: 2),
  ];
}

/// The demo student's progress over the last weeks, for the teacher's
/// chart: "Comparisons" climbing to done, then a third of "if and else".
List<Map<String, dynamic>> _progressHistory(DateTime now) {
  Map<String, dynamic> sample(String goalId, double value, int daysAgo) =>
      ProgressSample(
        goalID: goalId,
        progress: value,
        quality: AnswerQuality.correct,
        at: _day(now, daysAgo).add(const Duration(hours: 10, minutes: 50)),
      ).toMap(uid: demoStudent.oid);
  return [
    sample('s4', 0.0, 25),
    sample('s4', 0.25, 22),
    sample('s4', 0.5, 20),
    sample('s4', 0.5, 18),
    sample('s4', 0.75, 15),
    sample('s4', 1.0, 13),
    sample('s5', 0.0, 11),
    sample('s5', 0.0, 8),
    sample('s5', 0.33, 6),
    sample('s5', 0.33, 2),
  ];
}

List<Map<String, dynamic>> _statusReports(DemoLanguage lang, DateTime now) => [
  for (final (goalId, nl, en, daysAgo) in [
    (
      's3',
      'Mila werkt vlot met input() en zet tekst zelf om naar een getal. Ze vergat int() twee keer, maar zag het telkens zelf na de uitvoer.',
      'Mila works smoothly with input() and turns text into a number herself. She forgot int() twice, but spotted it herself each time from the output.',
      27,
    ),
    (
      's4',
      'Mila voorspelt vergelijkingen betrouwbaar, ook op moeilijk niveau. Het verschil tussen = en == zit goed.',
      'Mila predicts comparisons reliably, also at the hard level. The difference between = and == is clear to her.',
      13,
    ),
  ])
    {
      'id': CosmosDocId.statusReport(demoStudent.oid, goalId),
      'uid': demoStudent.oid,
      'goalId': goalId,
      'statusReport': lang.pick(nl, en),
      'updatedAt': _day(
        now,
        daysAgo,
      ).add(const Duration(hours: 11)).toUtc().toIso8601String(),
    },
];

// ---- Teacher side -------------------------------------------------------

const String kDemoMilestoneId = 'demo-report-1';

Map<String, dynamic> _milestone(DemoLanguage lang, DateTime now) => Milestone(
  id: kDemoMilestoneId,
  title: lang.pick('Rapport 1 — kerstexamen', 'Report 1 — Christmas'),
  periodStart: DateTime.utc(2026, 9, 1),
  dueAt: _day(now, -10).toUtc(),
  expectedDifficulty: QuestionDifficulty.medium,
  subgoalIds: const ['s1', 's2', 's3', 's4', 's5'],
  coreLoKeys: {
    for (final g in _subgoals.take(5))
      if (g.los.isNotEmpty) Milestone.loKey(g.id, g.los.first.id),
  },
).toMap();

/// The grade proposal of the demo student, with the justification the
/// screenshot shows.
GradeProposal _demoProposal(DemoLanguage lang, DateTime now) => GradeProposal(
  uid: demoStudent.oid,
  milestoneId: kDemoMilestoneId,
  formulaVersion: GradingConstants.formulaVersion,
  computedAt: _day(now, 1).add(const Duration(hours: 20)).toUtc(),
  k: 1.0,
  u: 0.6,
  d: 0.8,
  mEnd: 0.76,
  proposal: 76,
  coreTotal: 5,
  coreCounted: 5,
  extensionTotal: 5,
  extensionMastered: 3,
  masteredTotal: 8,
  hardCount: 6,
  staleLoCount: 0,
  neverProbedCount: 1,
  supervisedTurns: 98,
  homeTurns: 27,
  justification: lang.pick(
    'Mila beheerst alle kerndoelen van deze periode, de meeste op moeilijk '
        'niveau. Print, variabelen, invoer en vergelijkingen zitten goed. '
        'Bij if en else kan ze code laten kiezen, maar else gebruikt ze nog '
        'niet zeker, en voorspellen welke tak loopt kreeg ze nog weinig '
        'vragen over. Ze werkt regelmatig, in de les en thuis.',
    'Mila masters every core objective of this period, most of them at the '
        'hard level. Print, variables, input and comparisons are solid. With '
        'if and else she can make code choose, but she does not use else '
        'with confidence yet, and she got few questions so far on predicting '
        'which branch runs. She works steadily, in class and at home.',
  ),
  justificationAt: _day(now, 1).add(const Duration(hours: 20)).toUtc(),
);

List<Map<String, dynamic>> _proposals(DemoLanguage lang, DateTime now) => [
  _demoProposal(lang, now).toMap(),
  for (final c in _classmates.where((c) => c.className == kDemoClass))
    GradeProposal(
      uid: c.uid,
      milestoneId: kDemoMilestoneId,
      formulaVersion: GradingConstants.formulaVersion,
      computedAt: _day(now, 1).add(const Duration(hours: 20)).toUtc(),
      k: c.grade >= 50 ? 1.0 : 0.6,
      u: (c.grade - 50).clamp(0, 50) / 50,
      d: 0.7,
      mEnd: c.grade / 100,
      proposal: c.grade,
      coreTotal: 5,
      coreCounted: c.grade >= 50 ? 5 : 3,
      extensionTotal: 5,
      extensionMastered: ((c.grade - 50).clamp(0, 50) / 10).round(),
      masteredTotal: (c.grade / 12).round(),
      hardCount: (c.grade / 20).round(),
      staleLoCount: 0,
      neverProbedCount: c.grade >= 60 ? 0 : 2,
      supervisedTurns: 80 + c.grade ~/ 4,
      homeTurns: c.grade ~/ 5,
      justification: lang.pick(
        '${c.first} werkt in de les mee en haalt de kerndoelen.',
        '${c.first} works along in class and meets the core objectives.',
      ),
      justificationAt: _day(now, 1).add(const Duration(hours: 20)).toUtc(),
      signedOffAt: c.signed
          ? _day(now, 0).add(const Duration(hours: 8)).toUtc()
          : null,
    ).toMap(),
];

/// The question bank on "if and else", in the screenshot's language.
List<Map<String, dynamic>> _bankQuestions(DemoLanguage lang, DateTime now) {
  Map<String, dynamic> stored(
    ChatResponse response, {
    required String lo,
    required QuestionDifficulty difficulty,
    required int asked,
    required int answered,
    required int correct,
    required int daysAgo,
  }) => {
    ...BankQuestion.fromResponse(
      response,
      subgoalId: kDemoCurrentSubgoal,
      rootGoalId: kDemoCurrentRoot,
      targetLOIds: [lo],
      difficulty: difficulty,
      language: lang.code,
      model: 'gpt-5-mini',
      createdByUid: demoStudent.oid,
      createdAt: _day(now, daysAgo).add(const Duration(hours: 10)).toUtc(),
    )!.toMap(),
    'askedCount': asked,
    'answeredCount': answered,
    'correctCount': correct,
    'lastAskedAt': _day(
      now,
      1,
    ).add(const Duration(hours: 10)).toUtc().toIso8601String(),
  };

  return [
    stored(
      MultipleChoice(
        type: 'multiple_choice',
        prompt: lang.pick(
          'Wat toont dit programma?',
          'What does this program print?',
        ),
        code: lang.pick(
          'punten = 12\nif punten >= 10:\n    print("geslaagd")\nelse:\n    print("niet geslaagd")',
          'points = 12\nif points >= 10:\n    print("passed")\nelse:\n    print("failed")',
        ),
        options: [
          lang.pick('geslaagd', 'passed'),
          lang.pick('niet geslaagd', 'failed'),
          lang.pick('geslaagd\nniet geslaagd', 'passed\nfailed'),
        ],
        correct: lang.pick('geslaagd', 'passed'),
      ),
      lo: 'lo-trace',
      difficulty: QuestionDifficulty.easy,
      asked: 14,
      answered: 13,
      correct: 12,
      daysAgo: 9,
    ),
    stored(
      CompleteCode(
        type: 'complete_code',
        prompt: lang.pick(
          'Vul de voorwaarde aan: het programma toont "Je mag binnen." vanaf 16 jaar.',
          'Complete the condition: the program shows "You may enter." from age 16.',
        ),
        code: lang.pick(
          'leeftijd = 17\nif ___:\n    print("Je mag binnen.")',
          'age = 17\nif ___:\n    print("You may enter.")',
        ),
      ),
      lo: 'lo-if',
      difficulty: QuestionDifficulty.medium,
      asked: 11,
      answered: 11,
      correct: 8,
      daysAgo: 8,
    ),
    stored(
      WriteCode(
        type: 'write_code',
        prompt: lang.pick(
          'Schrijf een programma dat voor een getal toont of het even of oneven is.',
          'Write a program that shows whether a number is even or odd.',
        ),
      ),
      lo: 'lo-else',
      difficulty: QuestionDifficulty.medium,
      asked: 9,
      answered: 8,
      correct: 5,
      daysAgo: 7,
    ),
    stored(
      MultipleChoice(
        type: 'multiple_choice',
        prompt: lang.pick(
          'Welke regel loopt altijd, wat de temperatuur ook is?',
          'Which line always runs, whatever the temperature?',
        ),
        code: lang.pick(
          'if temperatuur > 25:\n    print("warm")\nelse:\n    print("fris")\nprint("klaar")',
          'if temperature > 25:\n    print("warm")\nelse:\n    print("cool")\nprint("done")',
        ),
        options: [
          'print("${lang.pick('klaar', 'done')}")',
          'print("warm")',
          'print("${lang.pick('fris', 'cool')}")',
        ],
        correct: 'print("${lang.pick('klaar', 'done')}")',
      ),
      lo: 'lo-trace',
      difficulty: QuestionDifficulty.hard,
      asked: 7,
      answered: 7,
      correct: 4,
      daysAgo: 5,
    ),
  ];
}

/// The demo student's files in the playground, as the account holds them.
List<Map<String, dynamic>> _playgroundFiles(DemoLanguage lang, DateTime now) {
  final files = <String, String>{
    lang.pick('dobbelsteen', 'dice'): demoPlaygroundCode(lang),
    lang.pick('rekenmachine', 'calculator'): lang.pick(
      'a = int(input("Eerste getal: "))\nb = int(input("Tweede getal: "))\nprint("Som:", a + b)\n',
      'a = int(input("First number: "))\nb = int(input("Second number: "))\nprint("Sum:", a + b)\n',
    ),
    lang.pick('raad_het_getal', 'guess_the_number'): 'import random\n',
    lang.pick('tafels', 'times_tables'):
        'for i in range(1, 11):\n    print(i, "x 7 =", i * 7)\n',
    lang.pick('weerbericht', 'weather'): demoLessonCode(lang),
  };
  var minutes = 0;
  return [
    for (final entry in files.entries)
      PlaygroundFileDoc(
        name: entry.key,
        code: entry.value,
        updatedAt: _day(
          now,
          2,
        ).add(Duration(hours: 20, minutes: minutes += 7)).toUtc(),
      ).toMap(demoStudent.oid),
  ];
}

/// The program open in the playground screenshot, and what it prints.
String demoPlaygroundCode(DemoLanguage lang) => lang.pick(
  'import random\n'
      '\n'
      'worpen = []\n'
      'for i in range(5):\n'
      '    worp = random.randint(1, 6)\n'
      '    worpen.append(worp)\n'
      '    print("Worp", i + 1, ":", worp)\n'
      '\n'
      'print("Totaal:", sum(worpen))\n',
  'import random\n'
      '\n'
      'rolls = []\n'
      'for i in range(5):\n'
      '    roll = random.randint(1, 6)\n'
      '    rolls.append(roll)\n'
      '    print("Roll", i + 1, ":", roll)\n'
      '\n'
      'print("Total:", sum(rolls))\n',
);

String demoPlaygroundOutput(DemoLanguage lang) => lang.pick(
  'Worp 1 : 4\nWorp 2 : 6\nWorp 3 : 1\nWorp 4 : 6\nWorp 5 : 3\nTotaal: 20\n',
  'Roll 1 : 4\nRoll 2 : 6\nRoll 3 : 1\nRoll 4 : 6\nRoll 5 : 3\nTotal: 20\n',
);

/// The English translation of every goal, learning objective and lesson.
/// The Dutch screenshots use none of it; the English ones read nothing
/// else.
List<Map<String, dynamic>> _translations() => [
  for (final g in _goals) ...[
    Translation.goal(
      language: 'en',
      goalId: g.id,
      title: g.en,
      description: g.enDescription,
      sourceHash: translationSourceHash(g.nl, g.nlDescription),
      updatedAt: DateTime.utc(2026, 9, 1),
    ).toMap(),
    for (final lo in g.los)
      Translation.objective(
        language: 'en',
        subgoalId: g.id,
        loId: lo.id,
        statement: lo.en,
        sourceHash: translationSourceHash('', lo.nl),
        updatedAt: DateTime.utc(2026, 9, 1),
      ).toMap(),
  ],
  for (final entry in _lessons.entries)
    Translation.content(
      language: 'en',
      contentId: entry.key,
      title: entry.value.enTitle,
      body: entry.value.body(DemoLanguage.en),
      sourceHash: translationSourceHash(
        entry.value.nlTitle,
        entry.value.body(DemoLanguage.nl),
      ),
      updatedAt: DateTime.utc(2026, 9, 1),
    ).toMap(),
];

/// Every Cosmos doc of the demo, by container, on top of the harness seed:
/// it replaces the seed's goals, lesson and module (same ids) and adds the
/// rest. [lang] picks the language of what was *written* in a language —
/// the reports, the bank, the file names; the goals and lessons are Dutch
/// with their English translation, as in the real app.
Map<String, List<Map<String, dynamic>>> demoDocs(
  DemoLanguage lang, {
  required DateTime now,
}) {
  final history = _history(now);
  return {
    'modules': [
      {
        'id': 'python-basics',
        'type': 'module',
        'title': 'Python',
        'order': 0,
        'updatedAt': '2026-09-01T08:00:00.000Z',
      },
    ],
    'goals': [for (final g in _goals) _goalDoc(g)],
    'content': [
      for (final entry in _lessons.entries)
        {
          'id': entry.key,
          'type': 'content',
          'title': entry.value.nlTitle,
          'body': entry.value.body(DemoLanguage.nl),
          'updatedAt': '2026-09-01T08:00:00.000Z',
        },
    ],
    'translations': _translations(),
    'config': [
      _classesDoc(),
      for (final place in _podiumPlaces(now)) place.toDoc(),
    ],
    'accounts': [
      _account(
        uid: demoStudent.oid,
        first: demoStudent.firstName,
        last: demoStudent.lastName,
        className: kDemoClass,
        streak: 4,
        oefeningCount: kDemoOefeningCount,
        lastActive: history.last.turnAt,
        badges: _badges(now, history),
      ),
      _account(
        uid: demoTeacher.oid,
        first: demoTeacher.firstName,
        last: demoTeacher.lastName,
        className: '',
        streak: 0,
        oefeningCount: 0,
        lastActive: _day(now, 0).add(const Duration(hours: 8)),
      ),
      for (final c in _classmates)
        _account(
          uid: c.uid,
          first: c.first,
          last: c.last,
          className: c.className,
          streak: c.streak,
          oefeningCount: 30 + 14 * c.finished,
          lastActive: _day(
            now,
            c.streak > 0 ? 1 + c.finished % 3 : 6,
          ).add(Duration(hours: 10, minutes: 40 + c.finished)),
        ),
    ],
    'progress': [
      ..._progressOf(now, demoStudent.oid, finished: 4, current: 1 / 3),
      for (final c in _classmates)
        ..._progressOf(
          now,
          c.uid,
          finished: c.finished,
          current: c.current,
          daysAgo: c.streak > 0 ? 1 : 6,
        ),
    ],
    'progress_history': _progressHistory(now),
    'status_reports': _statusReports(lang, now),
    'lo_beliefs': _beliefs(now),
    'turn_history': [for (final r in history) r.toMap(uid: demoStudent.oid)],
    'milestones': [_milestone(lang, now)],
    'grade_proposals': _proposals(lang, now),
    'questions': _bankQuestions(lang, now),
    'playground_files': _playgroundFiles(lang, now),
  };
}
