# Delete Policy

## Trigger
- Delete button in the details pane.

## Confirmation Dialog
> Delete this goal and all its sub-goals?  
> This action cannot be undone.

Buttons:
- **Delete** (danger)
- **Cancel**

## Behavior
- On confirmation:
  - Client collects all descendant IDs recursively.
  - Performs a batched delete (subtree).
- On success: snackbar “Goal deleted”.
- On failure: snackbar “Delete failed”; subtree remains.

## Cascade Delete
- Always recursive: deleting a goal removes all its descendants.
- There is no trash/undo in MVP.

## Safety Note
Large deletes (many descendants) may take a few seconds; show inline spinner in the pane while processing.
