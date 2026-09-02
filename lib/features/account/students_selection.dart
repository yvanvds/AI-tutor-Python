// Pure selection helpers for the Students page bulk actions (#91). Kept out
// of the widget so the header-checkbox semantics (tri-state over the
// filtered set, filter-scoped toggle-all) are unit-testable.

/// Tri-state value for the header "select all" checkbox: `true` when every
/// row of the filtered set is selected, `false` when none is, `null`
/// (indeterminate) when only part of it is. An empty filtered set reads as
/// "none selected" so the checkbox never shows checked over zero rows.
bool? selectAllState(Set<String> selected, Iterable<String> filteredUids) {
  var total = 0;
  var hits = 0;
  for (final uid in filteredUids) {
    total++;
    if (selected.contains(uid)) hits++;
  }
  if (total == 0 || hits == 0) return false;
  if (hits == total) return true;
  return null;
}

/// The new selection after a header-checkbox toggle scoped to
/// [filteredUids]: when every filtered row is already selected they are all
/// deselected, otherwise they are all added (also from the indeterminate
/// state — matching the checkbox's false → checked visual). Selected rows
/// OUTSIDE the filtered set keep their state either way, so narrowing the
/// filter and toggling never silently drops an off-screen selection.
Set<String> toggleSelectAll(
  Set<String> selected,
  Iterable<String> filteredUids,
) {
  final filtered = filteredUids.toSet();
  final allSelected = filtered.isNotEmpty && filtered.every(selected.contains);
  if (allSelected) return selected.difference(filtered);
  return selected.union(filtered);
}
