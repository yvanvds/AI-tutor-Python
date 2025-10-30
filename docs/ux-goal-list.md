# Goals — Single-Page Master–Detail UI Spec

## Overall Layout
- Two-column design:
  - **Left:** list of all root goals, and children of the selected root.
  - **Right:** details pane (visible when a goal is selected).

### Top Bar
- "+ Add root goal" button → creates a new root goal at the end of the list.

---

## Goal Row (root level)
**Shown fields**
- `title`
- Optional badge labeled “optional” (accent color)
- Chip showing number of direct children (e.g., “3”)

**Buttons / Actions**
- **View** — opens the details pane for that goal.
- **+** — adds a new child under this goal (appears last).
- **Up / Down** — moves the goal among root siblings (order changes).

**Click behavior**
- Clicking the row (not buttons) selects it as the current context,
  showing its children underneath and updating the details pane.

---

## Child Row
**Shown fields**
- `title`
- Optional badge (“optional”)

**Buttons / Actions**
- **View** — opens the details pane for that child.
- **Up / Down** — reorders among its siblings.

**Indentation**
- Slight visual indent (≈ 8–12 px) to distinguish from roots.

---

## Details Pane
**Appears when a goal is selected.**

**Fields (all autosave on blur)**
- `title` — required text input.
- `description` — multiline text.
- `optional` — toggle (boolean).
- `suggestions` — multiline text area, **one suggestion per line**.
- `tags` — comma-separated text input.
- `parent` — dropdown list of all **root goal titles** (nullable).  
  Changing it reparents the goal:
  - `parentId` set to the chosen goal’s ID (or `null` for root).
  - `order` assigned as the last sibling’s order + 1000.

**Buttons**
- **Delete** — removes the goal and its entire subtree.  
  Confirmation dialog: “Delete this goal and all its sub-goals?”
- (No Save button — implicit autosave handles all edits.)

**Autosave behavior**
- Saves after a short debounce (≈ 400–600 ms) when any field loses focus.
- Only changed fields are written.
- Snackbar shows “Saved” briefly after a successful write.

---

## Sort Order
- Always ascending by `order`.
- Roots and children each have independent order sequences.
- Gapped integers (1000 steps); renumber if gaps shrink below 10.

---

## Empty States
- No goals → “Add your first goal.”
- No children → “This goal has no sub-goals. Add one.”

---

## Visual & Interaction Details
- Optional badge color = accent theme color.
- Hover highlight on list rows.
- Keyboard:
  - **Up/Down arrows** move selection within list.
  - **Enter** opens details pane.
  - **Esc** closes the details pane.
- Loading: small spinner in list area while data fetches.
- Errors: snackbar (“Save failed”, “Delete failed”).
- Dialogs: used for destructive actions only (delete).

---

## Behavior Summary
- Everything happens on one page.
- Autosave replaces explicit Save.
- Desktop-first design: full-screen, keyboard-friendly.
- Simple, predictable interactions — no hidden routes, no extra views.
