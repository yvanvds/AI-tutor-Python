# UX System — MVP (Single-Page Desktop)

## Loading
- Small inline spinner for the list area during fetches.
- Greyed-out rows for pending autosaves or reorders.

## Feedback
| Action | Feedback |
|--------|-----------|
| Field edit (autosave) | Snackbar “Saved” |
| Failed save | Snackbar “Save failed” |
| Reorder | Snackbar “Order saved / failed” |
| Delete | Dialog + snackbar on success/failure |
| Reparent | Snackbar “Parent updated” |

## Dialogs
- Only for destructive actions (delete).
- Blocking until user confirms/cancels.

## Snackbars
- Auto-dismiss after ~2 s.
- Stack vertically if multiple appear.
- Contain a brief action verb (“Saved”, “Deleted”).

## Keyboard Support
- Up/Down → navigate list.
- Enter → open details pane.
- Esc → close details pane.
- Ctrl+R → renormalize order (optional dev shortcut).

## Desktop-Only Design
- Full-screen layout optimized for large viewport.
- No touch gestures or mobile responsiveness needed.

## Error Handling
- Non-critical errors: transient snackbar.
- Critical failures (e.g., Firestore unavailable): modal dialog “Connection lost”.
