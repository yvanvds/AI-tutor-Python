/// Parse the optional `suspected_concepts` META field on the four feedback
/// response types into a clean tag list. Trims each entry, drops empties.
/// Returns null when the AI omitted the field, sent something other than a
/// list, or sent a list with no usable tags — handlers treat any of those
/// as "no attribution."
List<String>? parseSuspectedConcepts(Object? raw) {
  if (raw is! List) return null;
  final out = <String>[];
  for (final entry in raw) {
    if (entry is! String) continue;
    final trimmed = entry.trim();
    if (trimmed.isEmpty) continue;
    out.add(trimmed);
  }
  return out.isEmpty ? null : out;
}
