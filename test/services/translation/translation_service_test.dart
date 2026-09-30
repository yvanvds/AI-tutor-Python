// Issue #206 — the translation service over an in-memory `translations`
// container partitioned on `/language` (the same id lives once per
// language): reading one language only and nothing for Dutch, writes that
// stay out of Dutch, moving a lesson's translations in every language, and
// the two error contracts when the container was never created — the
// student's reads fall back to "no translations" and leave the container
// alone for a while, the teacher's writes throw.

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/unprovisioned_cosmos.dart';

Map<String, dynamic> _lesson(
  String language,
  String contentId, {
  String title = 'Title',
  String body = '<p>body</p>',
  String sourceHash = 'h',
  Map<String, dynamic> extra = const {},
}) => {
  ...Translation.content(
    language: language,
    contentId: contentId,
    title: title,
    body: body,
    sourceHash: sourceHash,
  ).toMap(),
  ...extra,
};

Map<String, dynamic> _goal(String language, String goalId) => Translation.goal(
  language: language,
  goalId: goalId,
  title: 'Goal $goalId',
  description: 'About $goalId',
  sourceHash: 'h',
).toMap();

void main() {
  var now = DateTime.utc(2026, 9, 30, 8);
  late InMemoryCosmos cosmos;
  late TranslationService service;

  setUp(() {
    now = DateTime.utc(2026, 9, 30, 8);
    cosmos = InMemoryCosmos.partitioned('language', [
      _lesson('en', 's1', title: 'Variables'),
      _lesson('fr', 's1', title: 'Variables (fr)'),
      _goal('en', 's1'),
      _lesson('en', 's2'),
    ]);
    service = TranslationService(container: cosmos.container, now: () => now);
  });

  group('reads', () {
    test('a language reads its own partition: lessons and goals', () async {
      final en = await service.listLanguage('en');
      expect(
        en.map((t) => t.id),
        unorderedEquals(['content_s1', 'goal_s1', 'content_s2']),
      );
      expect(en.every((t) => t.language == 'en'), isTrue);
      expect(en.firstWhere((t) => t.id == 'content_s1').title, 'Variables');

      final fr = await service.listLanguage('fr');
      expect(fr.single.title, 'Variables (fr)');
    });

    test('Dutch is the source: nothing is fetched for it', () async {
      final missing = UnprovisionedCosmos('translations');
      final svc = TranslationService(container: missing.container);

      expect(await svc.listLanguage('nl'), isEmpty);
      expect(await svc.watchLanguage('nl').toList(), [isEmpty]);
      expect(missing.requests, isEmpty);
    });

    test('watchLanguage emits the language as it is', () async {
      final first = await service.watchLanguage('en').first;
      expect(first, hasLength(3));
    });
  });

  group('writes', () {
    test('upsert stores the translation under its language, stamped, and it '
        'reads back unchanged', () async {
      final stored = await service.upsert(
        Translation.content(
          language: 'en',
          contentId: 's3',
          title: 'Lists',
          body: '<p>A list.</p>',
          sourceHash: 'abc',
        ),
      );
      expect(stored.updatedAt, now);
      expect(cosmos['en/content_s3']!['body'], '<p>A list.</p>');
      expect(cosmos['en/content_s3']!['updatedAt'], now.toIso8601String());

      final back = (await service.listLanguage('en'))
          .firstWhere((t) => t.id == 'content_s3');
      expect(back, stored);
    });

    test(
      'upsert over an existing translation replaces only that language',
      () async {
        await service.upsert(
          Translation.content(
            language: 'en',
            contentId: 's1',
            title: 'Variables, again',
            body: '<p>new</p>',
            sourceHash: 'h2',
          ),
        );
        expect(cosmos['en/content_s1']!['title'], 'Variables, again');
        expect(cosmos['fr/content_s1']!['title'], 'Variables (fr)');
      },
    );

    test('delete removes one language of one doc', () async {
      await service.delete(
        language: 'en',
        kind: TranslationKind.content,
        refId: 's1',
      );
      expect(cosmos['en/content_s1'], isNull);
      expect(cosmos['en/goal_s1'], isNotNull);
      expect(cosmos['fr/content_s1'], isNotNull);
    });

    test('Dutch cannot be written or deleted here', () async {
      expect(
        () => service.upsert(
          Translation.content(
            language: kSourceLanguage,
            contentId: 's1',
            title: 't',
            body: 'b',
            sourceHash: 'h',
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => service.delete(
          language: kSourceLanguage,
          kind: TranslationKind.goal,
          refId: 's1',
        ),
        throwsArgumentError,
      );
    });
  });

  group('moveContent', () {
    test('moves the lesson translations in every language, whole, and '
        'leaves goal translations and other lessons alone', () async {
      cosmos.docs['en/content_s1']!['addedByNewerBuild'] = 'kept';

      await service.moveContent('s1', 's9');

      expect(cosmos['en/content_s1'], isNull);
      expect(cosmos['fr/content_s1'], isNull);
      expect(cosmos['en/content_s9']!['refId'], 's9');
      expect(cosmos['en/content_s9']!['title'], 'Variables');
      expect(cosmos['en/content_s9']!['sourceHash'], 'h');
      expect(cosmos['en/content_s9']!['addedByNewerBuild'], 'kept');
      expect(cosmos['fr/content_s9']!['title'], 'Variables (fr)');
      expect(cosmos['en/goal_s1'], isNotNull, reason: 'the goal did not move');
      expect(cosmos['en/content_s2'], isNotNull);
    });

    test(
      'a translation already at the target in another language stays',
      () async {
        cosmos.upsert(_lesson('de', 's9', title: 'Alt'), partitionKey: 'de');
        await service.moveContent('s1', 's9');
        expect(cosmos['de/content_s9']!['title'], 'Alt');
        expect(cosmos['en/content_s9']!['title'], 'Variables');
      },
    );

    test('moving onto itself, or a lesson without translations, changes '
        'nothing', () async {
      final before = {...cosmos.docs.keys};
      await service.moveContent('s1', 's1');
      await service.moveContent('s-none', 's9');
      expect(cosmos.docs.keys.toSet(), before);
    });
  });

  group('without a `translations` container', () {
    late UnprovisionedCosmos missing;

    setUp(() {
      missing = UnprovisionedCosmos('translations');
      service = TranslationService(
        container: missing.container,
        now: () => now,
      );
    });

    test('the student-side read gives no translations instead of throwing, '
        'and the container is left alone for a while', () async {
      expect(await service.listLanguage('en'), isEmpty);
      final afterFirst = missing.requests.length;
      expect(afterFirst, greaterThan(0));

      expect(await service.listLanguage('en'), isEmpty);
      expect(await service.watchLanguage('en').first, isEmpty);
      expect(
        missing.requests.length,
        afterFirst,
        reason: 'within the back-off nothing is sent',
      );

      now = now.add(kTranslationsRetryAfter);
      expect(await service.listLanguage('en'), isEmpty);
      expect(missing.requests.length, greaterThan(afterFirst));
    });

    test(
      'the teacher-side writes throw a ContainerNotFound a page can name',
      () async {
        final containerNotFound = throwsA(
          isA<CosmosException>().having(
            (e) => e.isContainerNotFound,
            'isContainerNotFound',
            isTrue,
          ),
        );
        await expectLater(
          service.upsert(
            Translation.goal(
              language: 'en',
              goalId: 's1',
              title: 't',
              description: 'd',
              sourceHash: 'h',
            ),
          ),
          containerNotFound,
        );
        await expectLater(
          service.delete(
            language: 'en',
            kind: TranslationKind.goal,
            refId: 's1',
          ),
          containerNotFound,
        );
      },
    );

    test('moving a lesson finds nothing to move, and writes nothing', () async {
      await expectLater(service.moveContent('s1', 's9'), completes);
      expect(missing.writes, isEmpty);
    });
  });
}
