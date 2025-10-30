# Reparenting Policy

## UI
- Controlled by the **Parent** dropdown in the details pane.
- Options: all root-level goals + “None” (for root).
- Selection always visible, even for root nodes.

## Behavior
On change:
1. Compute the new `parentId` (or null).
2. Fetch last sibling under that parent.
3. Assign new `order` = last + 1000.
4. Batch-write both updates (`parentId`, `order`).

## Side Effects
- The goal immediately appears under its new parent in the left-hand list.
- Autosave logic applies (same debounce).
- If the new parent is later deleted, this goal and its descendants are removed with it (cascade rule).

## Confirmation
No separate confirmation required; changes are reversible via another dropdown selection.

## Limitations
- You can only select **root goals** as parents; nested reparenting deeper than one level is not supported in this phase.
