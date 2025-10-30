# Routes — Single-Page Layout

## Primary
- `/goals` — The only page for managing goals.

### Layout
- **Left column:** hierarchy of root goals and their children.
- **Right column:** details pane for viewing or editing the selected goal.

### Behavior
- Opening a goal (click "View") opens its details pane on the right.
- Selecting a different goal updates the details pane instantly.
- There are no sub-pages or deep links.
- The interface autosaves on blur or when fields lose focus.
- Reparenting is done directly in the details pane.
- Reordering and adding children happen inline within the same view.

### Optional developer note
If later you ever add navigation, `/goals` could stay as the root route.
