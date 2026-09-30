// Reads and writes of the `translations` container (#206; `/language`
// partition — see `CosmosPaths.translations` and `translation.dart`).
//
// Two kinds of caller, two error contracts, as for the question bank (#185):
//
//   - The student's app reads one language: [watchLanguage], polled like the
//     other services, one single-partition query per poll, and nothing at
//     all for Dutch. A missing container is logged and then left alone for
//     [kTranslationsRetryAfter]; until then the language reads as having no
//     translations, so every lesson and goal text falls back to Dutch.
//     Other failures are absorbed by `safeCosmosStream` like everywhere
//     else: the last good value stays.
//   - The teacher's writes — [upsert], [delete], and [moveContent] for
//     `ContentService.reassign` — throw, so a page can say what went wrong,
//     in particular that the container does not exist yet
//     ([CosmosException.isContainerNotFound]). The one exception is
//     [moveContent] without a container: there is nothing to move then.

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long the student's app leaves `translations` alone after finding the
/// container missing: long enough not to spend two requests on every poll,
/// short enough that creating the container is picked up without a restart.
const Duration kTranslationsRetryAfter = Duration(minutes: 10);

class TranslationService {
  TranslationService({CosmosContainer? container, DateTime Function()? now})
    : _containerOverride = container,
      _now = now ?? (() => DateTime.now().toUtc());

  final CosmosContainer? _containerOverride;
  final DateTime Function() _now;

  CosmosContainer get _container =>
      _containerOverride ?? CosmosPaths.translations();

  /// Until when the reads skip the container after a `ContainerNotFound`.
  DateTime? _unavailableUntil;

  // ---- Student side: tolerant reads ---------------------------------------

  /// Every translation into [language], re-fetched every
  /// `kCosmosPollInterval`. For [kSourceLanguage] it emits one empty list and
  /// fetches nothing: Dutch is in `content` and `goals`.
  Stream<List<Translation>> watchLanguage(String language) {
    if (language == kSourceLanguage) {
      return Stream<List<Translation>>.value(const []);
    }
    return safeCosmosStream(pollingStream(() => listLanguage(language)));
  }

  /// One fetch of [watchLanguage]: a query within the partition [language].
  /// Empty for [kSourceLanguage], and — without a request — while the
  /// container is known to be missing. A missing container does not throw;
  /// other failures do.
  Future<List<Translation>> listLanguage(String language) async {
    if (language == kSourceLanguage || !_available) return const [];
    final List<Map<String, dynamic>> docs;
    try {
      docs = await safeCosmos(
        () => _container.query('SELECT * FROM c', partitionKey: language),
      );
    } on CosmosException catch (e) {
      if (!e.isContainerNotFound) rethrow;
      _pause(e);
      return const [];
    }
    return [
      for (final doc in docs)
        if (Translation.tryFromCosmos(doc) case final t?)
          // Re-applied client-side: a doc filed under the wrong partition
          // must not show up in another language.
          if (t.language == language) t,
    ];
  }

  bool get _available {
    final until = _unavailableUntil;
    return until == null || !_now().isBefore(until);
  }

  void _pause(CosmosException e) {
    _unavailableUntil = _now().add(kTranslationsRetryAfter);
    debugPrint(
      'TranslationService: no `translations` container — create it (README '
      'step 3). Lessons and goal texts show in Dutch; the container is not '
      'tried again for ${kTranslationsRetryAfter.inMinutes} minutes. $e',
    );
  }

  // ---- Teacher side: writes that throw ------------------------------------

  /// Stores [translation], stamped with the current time, over any earlier
  /// translation of the same doc into the same language. Returns what was
  /// stored. Only translation code writes this container, so nothing else
  /// can wipe what this writes.
  Future<Translation> upsert(Translation translation) async {
    _checkNotSource(translation.language);
    final stamped = translation.copyWith(updatedAt: _now());
    await safeCosmos(
      () => _container.upsert(stamped.toMap(), partitionKey: stamped.language),
    );
    return stamped;
  }

  /// Removes the translation of [refId] into [language]. The Dutch source is
  /// not touched. A translation that does not exist is not an error.
  Future<void> delete({
    required String language,
    required TranslationKind kind,
    required String refId,
  }) async {
    _checkNotSource(language);
    await safeCosmos(
      () => _container.delete(
        Translation.docId(kind, refId),
        partitionKey: language,
      ),
    );
  }

  /// Moves the translations of the lesson [fromContentId] to [toContentId],
  /// in every language: `content_${from}` becomes `content_${to}`, as
  /// `ContentService.reassign` moves the lesson itself. Each doc is copied
  /// whole — `sourceHash`, `updatedAt` and fields a newer build added
  /// included — and then deleted under its old id. A translation already at
  /// [toContentId] in a language [fromContentId] has none in stays; its
  /// `sourceHash` no longer matches the lesson, so it reads as stale.
  ///
  /// The one query that crosses partitions; teacher-only and rare. Without
  /// a `translations` container there is nothing to move and this returns;
  /// any other failure throws, and calling it again finishes the move.
  Future<void> moveContent(String fromContentId, String toContentId) async {
    if (fromContentId == toContentId) return;
    final fromId = Translation.contentDocId(fromContentId);
    final List<Map<String, dynamic>> docs;
    try {
      docs = await safeCosmos(
        () => _container.query(
          'SELECT * FROM c WHERE c.id = @id',
          parameters: {'@id': fromId},
          crossPartition: true,
        ),
      );
    } on CosmosException catch (e) {
      if (!e.isContainerNotFound) rethrow;
      debugPrint(
        'TranslationService: no `translations` container, so no '
        'translations of $fromContentId to move. $e',
      );
      return;
    }
    for (final doc in docs) {
      final language = doc['language'];
      if (doc['id'] != fromId || language is! String) continue;
      final moved = Map<String, dynamic>.of(doc)
        // Cosmos owns `_rid`, `_etag`, `_ts`…: not echoed back.
        ..removeWhere((k, _) => k.startsWith('_'))
        ..['id'] = Translation.contentDocId(toContentId)
        ..['refId'] = toContentId;
      await safeCosmos(() => _container.upsert(moved, partitionKey: language));
      await safeCosmos(() => _container.delete(fromId, partitionKey: language));
    }
  }

  static void _checkNotSource(String language) {
    if (language == kSourceLanguage) {
      throw ArgumentError.value(
        language,
        'language',
        'Dutch is the source language: it lives in `content` and `goals`, '
            'not in `translations`',
      );
    }
  }
}

final translationServiceProvider = Provider<TranslationService>(
  (ref) => TranslationService(),
);
