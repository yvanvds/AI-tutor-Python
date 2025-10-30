# Goal Editor — Details Pane (Single-Page Version)

## Purpose
The details pane is the only editing surface in the app.  
All edits happen here and are **autosaved**; there are no modal editors or separate pages.

---

## Autosave Policy
- Trigger: when any field loses focus (`blur`) or after a short debounce (~500 ms) if typing stops.
- Firestore writes:
  - Only changed fields are written.
  - Batched together if multiple fields change within one debounce window.
- Feedback:
  - Snackbar → “Saved” on success.
  - Snackbar → “Save failed” on error (no blocking dialog).

---

## Validation
- `title` is required (min length > 0).
- All other fields optional.
- Empty `suggestions` or `tags` arrays are stored as `[]`.

---

## Fields
| Field | Type | Notes |
|-------|------|-------|
| `title` | text | required |
| `description` | multiline text | optional |
| `optional` | toggle | default false |
| `suggestions` | multiline text | one suggestion per line |
| `tags` | text | comma-separated |
| `parent` | dropdown | lists all **root goals** (plus “None” for root) |

When `parent` changes:
- Set `parentId` → new parent (or null).
- Compute new `order` = last sibling’s order + 1000.
- Write both updates in a single transaction.

---

## Delete Button
- Label: **Delete goal**
- Confirmation dialog:
  > Delete this goal and all its sub-goals?  
  > This action cannot be undone.
- On confirm: trigger cascade delete (see `delete.md`).

---

## Unsaved Edits Handling
Because autosave is implicit, there is **no explicit save/discard** prompt.  
If Firestore write fails, the snackbar error persists until the user changes something again.
