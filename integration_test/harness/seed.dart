// Fixture data for the integration harness (#28): one identity, its account
// doc, and a small curriculum with one lesson that carries a live-preview
// block. Everything is plain Cosmos doc maps so the real services read them
// exactly as they would read the production containers.

import 'package:ai_tutor_python/services/auth/auth_service.dart';

import '../../test/helpers/in_memory_cosmos.dart';

const String kStudentUid = 'it-student';

const AccountIdentity studentIdentity = AccountIdentity(
  oid: kStudentUid,
  displayName: 'Sam Student',
  email: 'sam@example.com',
  firstName: 'Sam',
  lastName: 'Student',
  isTeacher: false,
);

const AccountIdentity teacherIdentity = AccountIdentity(
  oid: 'it-teacher',
  displayName: 'Yvan Teacher',
  email: 'yvan@example.com',
  firstName: 'Yvan',
  lastName: 'Teacher',
  isTeacher: true,
);

/// The Python inside the seeded lesson's `<pre class="run">` block; the page
/// posts exactly this string on the runner channel when the lesson loads.
const String kLessonExampleCode = 'naam = "Mira"\nprint("Hallo", naam)';

const String kLessonBody =
    '<h2>Print</h2>'
    '<p>Zo toon je iets op het scherm.</p>'
    '<pre class="run"><code>$kLessonExampleCode</code></pre>'
    '<pre><code>print("geen preview")</code></pre>';

Map<String, dynamic> accountDoc(AccountIdentity who) => {
  'id': who.oid,
  'uid': who.oid,
  'email': who.email,
  'firstName': who.firstName,
  'lastName': who.lastName,
  'targetGoal': 'Python',
  // On the bundled key, so boot lands on the shell instead of the local
  // key gate.
  'mayUseGlobalKey': true,
  'createdAt': '2026-05-01T10:00:00Z',
  'updatedAt': '2026-05-01T10:00:00Z',
  'calibration': {
    'difficulty': 'medium',
    'recentAnswers': const [],
    'recentQuestionTypes': const [],
  },
};

Map<String, dynamic> goalDoc({
  required String id,
  required String title,
  String? parentId,
  int order = 1000,
  String? contentId,
  bool optional = false,
  List<Map<String, dynamic>> objectives = const [],
}) => {
  'id': id,
  'type': 'goal',
  'title': title,
  'parentId': parentId,
  'order': order,
  'optional': optional,
  'teachingTips': const <String>[],
  'allowChains': false,
  'objectives': objectives,
  'contentId': contentId,
  'moduleId': 'python-basics',
};

Map<String, dynamic> objective(String id, String statement) => {
  'id': id,
  'statement': statement,
  'kind': 'apply',
  'weight': 1.0,
  'optional': false,
};

/// Containers as `CosmosPaths` names them. Root "Basics" with two subgoals;
/// "Print" (first, unstarted) links the lesson with the live example, so the
/// conductor targets it and the explain view renders it.
Map<String, InMemoryCosmos> seedCosmos(AccountIdentity who) => {
  'accounts': InMemoryCosmos([accountDoc(who)]),
  'modules': InMemoryCosmos([
    {
      'id': 'python-basics',
      'type': 'module',
      'title': 'Python basics',
      'order': 0,
      'updatedAt': '2026-05-01T10:00:00Z',
    },
  ]),
  'goals': InMemoryCosmos([
    goalDoc(id: 'r1', title: 'Basics'),
    goalDoc(
      id: 's1',
      title: 'Print',
      parentId: 'r1',
      order: 1000,
      contentId: 's1',
      objectives: [objective('lo-print', 'Use print() to show text')],
    ),
    goalDoc(
      id: 's2',
      title: 'Variables',
      parentId: 'r1',
      order: 2000,
      objectives: [objective('lo-var', 'Assign a value to a name')],
    ),
  ]),
  'content': InMemoryCosmos([
    {
      'id': 's1',
      'type': 'content',
      'title': 'Print',
      'body': kLessonBody,
      'updatedAt': '2026-05-01T10:00:00Z',
    },
  ]),
  'config': InMemoryCosmos([
    {'id': 'global', 'type': 'config', 'Model': 'gpt-4o', 'ApiKey': ''},
  ]),
};
