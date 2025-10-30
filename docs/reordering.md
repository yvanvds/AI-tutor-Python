# Reordering Policy (Single-Page)

## Scope
- Reordering happens within the same sibling group (roots or children of one parent).

## Interaction
- Each row has **Up** and **Down** buttons.
- Clicking moves the goal one slot up/down in that sibling list.

## Implementation
- When user clicks:
  1. Swap the `order` values of the affected goals (locally).
  2. Update UI immediately (optimistic).
  3. Commit both updates in one batched Firestore write.

## Order Scheme
- Integers spaced by 1000 (1000, 2000, 3000,…).
- If any two consecutive orders differ < 10, renumber the entire sibling list using fresh 1000-step increments.
- Normalization is done client-side after a reorder; write all adjusted `order` fields in one batch.

## Autosave Interaction
Reordering writes are explicit actions and not throttled by the autosave debounce.

## Feedback
- Inline spinner or row highlight during write.
- Snackbar “Order saved” on success; “Reorder failed” on error.
