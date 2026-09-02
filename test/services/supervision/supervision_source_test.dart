// The production binding of the supervision seam (#100) until Anchor ships:
// no registry, every turn is home work.

import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/services/supervision/supervision_source.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NoSupervisionSource answers home for anyone at any time', () async {
    const source = NoSupervisionSource();
    expect(
      await source.provenanceFor(uid: 'u1', at: DateTime.utc(2026, 9, 2, 9)),
      EvidenceProvenance.home,
    );
    expect(
      await source.provenanceFor(uid: 'u2', at: DateTime.utc(2026, 9, 2, 21)),
      EvidenceProvenance.home,
    );
  });

  test('the app binds NoSupervisionSource by default', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(supervisionSourceProvider),
      isA<NoSupervisionSource>(),
    );
  });
}
