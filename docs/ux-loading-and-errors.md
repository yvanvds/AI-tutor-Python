# Loading and Error Surfaces — Single-Page MVP

## General Principles
- Keep the interface responsive: list and details pane always visible.
- Show only lightweight indicators; no blocking modals except for destructive actions.
- All async operations (load, save, reorder, delete, reparent) give immediate visual feedback.

---

## Loading States

### Initial Data Load
- **List area:** inline spinner centered vertically while fetching goals.
- Once loaded, fade in rows with a short (150 ms) transition.

### Autosave / Write In-Progress
- The edited field’s border or background shows a brief highlight (e.g. accent tint or subtle shimmer).
- If multiple writes happen rapidly, show only one global spinner in the upper-right corner.

### Reorder / Delete / Reparent
- Temporarily disable affected buttons while the operation is pending.
- Rows involved in the action are dimmed slightly (opacity 0.7).

---

## Error Handling

### Non-Critical Errors
- Example: “Save failed”, “Reorder failed”.
- **Snackbar** at bottom-right (auto-dismiss 2 s).
- User can continue working; autosave will retry automatically on the next change.

### Critical Errors
- Example: Firestore connection lost, authentication expired.
- **Dialog** overlay:  
  Title = “Connection lost”,  
  Message = “Changes will resume once reconnected.”  
  Button = “Retry now”.

### Logging
- Each write error logs to console with goal ID and field list for debugging.
- (Optional) keep a simple in-memory error queue for retries during the session.

---

## Visual Hints

| State | Indicator |
|-------|------------|
| Loading data | Spinner (center) |
| Saving | Thin progress bar or spinner top-right |
| Save success | Green snackbar “Saved” |
| Save fail | Red snackbar “Save failed” |
| Delete success | Snackbar “Deleted” |
| Delete fail | Snackbar “Delete failed” |
| Connection lost | Modal dialog |

---

## Performance Notes
- Use optimistic UI for most actions.  
  - Updates appear instantly.  
  - Reverts only on write failure.
- No skeleton screens needed — dataset is small (< 100 nodes).

