// Issue #4 — `ContentService.reassign` moves an orphaned content doc under a
// new subgoal id (content id mirrors subgoal id), deletes the old doc, and
// patches the cached list so the tree updates before the next poll.

import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

void main() {
  late InMemoryCosmos cosmos;
  late ProviderContainer container;

  setUp(() {
    cosmos = InMemoryCosmos([
      {
        'id': 's-old',
        'type': 'content',
        'title': 'Loops lesson',
        'body': '<p>loops</p>',
      },
      {
        'id': 's-taken',
        'type': 'content',
        'title': 'Old lesson',
        'body': '<p>old</p>',
      },
    ]);
    container = ProviderContainer(
      overrides: [
        contentServiceProvider.overrideWith(
          () => ContentService(container: cosmos.container),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  ContentService svc() => container.read(contentServiceProvider.notifier);

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test(
    'copies body under the target id, deletes the orphan, patches cache',
    () async {
      container.listen(contentServiceProvider, (_, _) {});
      await settle();
      expect(
        container.read(contentServiceProvider).map((c) => c.id),
        containsAll(['s-old', 's-taken']),
      );

      final orphan = Content(
        id: 's-old',
        title: 'Loops lesson',
        body: '<p>loops</p>',
      );
      final moved = await svc().reassign(orphan, 's-new');

      expect(moved.id, 's-new');
      expect(cosmos['s-new'], isNotNull);
      expect(cosmos['s-new']!['body'], '<p>loops</p>');
      expect(cosmos['s-new']!['title'], 'Loops lesson');
      expect(cosmos['s-new']!['type'], 'content');
      expect(cosmos['s-old'], isNull);

      final cached = container.read(contentServiceProvider);
      expect(cached.map((c) => c.id).toSet(), {'s-new', 's-taken'});
    },
  );

  test('overwrites an existing doc at the target id', () async {
    final orphan = Content(
      id: 's-old',
      title: 'Loops lesson',
      body: '<p>loops</p>',
    );
    await svc().reassign(orphan, 's-taken');

    expect(cosmos['s-taken']!['body'], '<p>loops</p>');
    expect(cosmos['s-old'], isNull);
    final cached = container.read(contentServiceProvider);
    expect(cached.where((c) => c.id == 's-taken'), hasLength(1));
  });

  test('same-id reassign (relink) upserts without deleting', () async {
    final orphan = Content(
      id: 's-old',
      title: 'Loops lesson',
      body: '<p>loops</p>',
    );
    await svc().reassign(orphan, 's-old');
    expect(cosmos['s-old'], isNotNull);
    expect(cosmos['s-old']!['body'], '<p>loops</p>');
  });
}
