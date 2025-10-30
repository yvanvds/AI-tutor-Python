# Build Roadmap — Single-Page Goals (Flutter + Firestore)

> Target: Windows desktop (dev), Flutter 3.29, Firebase 13.32.0, Firestore. One route: `/goals`. Autosave on blur, inline reorder, dropdown reparent, cascade delete.

## 0) Bootstrap & Sanity (can run app)

1. **Create Flutter app (if not yet) & wire Firebase** (done)

   * `flutter create ai_tutor_dashboard` → open in IDE.
   * `dart pub add firebase_core cloud_firestore flutter_hooks hooks_riverpod` (or Provider if you prefer).
   * `dart pub add uuid collection`
   * `flutterfire configure` → include Windows; commit generated `firebase_options.dart`.
   * **Run app**: render a blank `Scaffold("Goals")`.

   ✅ *Run & Verify*: App launches on Windows.

2. **Project structure**

   * Add folders: `lib/core/`, `lib/data/`, `lib/features/goals/`, `lib/widgets/`.
   * Create `lib/core/logger.dart` (simple print wrapper), `core/result.dart` (Result/Either if you like).

   ✅ *Run & Verify*: Still compiles.

---

## 1) Data model & Firestore wiring (can list roots)

3. **Goal model (lean)**

   * Fields: `id`, `title`, `description?`, `parentId?`, `order`, `optional=false`, `suggestions=[]`, `tags=[]`. Matches your spec.

4. **Repository (Firestore)**

   * `GoalsRepository` with:

     * `streamRoots()` → `parentId == null` ordered by `order`.
     * `streamChildren(parentId)` → ordered by `order`.
     * `createRoot(title)` → `order = last+1000`.
     * `createChild(parentId, title)` → `order = last+1000`.
   * Add index note: `(parentId ASC, order ASC)` (already in your plan).

5. **Seed (optional)**

   * If your Phase 1 docs already created a few nodes in Firestore, skip; otherwise add one root programmatically once.

6. **Simple UI: roots list**

   * Left column: `ListView` streaming `streamRoots()`.
   * Show: title, optional badge, child-count placeholder (0 for now), View/+ buttons disabled.

   ✅ *Run & Verify*: Roots appear and update live.

---

## 2) Children list within selected root (can browse hierarchy)

7. **Selection state**

   * Add provider/state: `selectedRootId` (nullable).
   * Clicking a root row sets selection.

8. **Children stream**

   * Below selected root, render its children via `streamChildren(selectedRootId)`.

9. **Child-count chip**

   * Compute with a lightweight count query or cached stream length per root row.

   ✅ *Run & Verify*: Select a root; children appear underneath; counts look right.

---

## 3) Details pane (read-only → editable)

10. **Details pane shell (right column)**

    * When a row (root or child) is “View” → set `selectedGoalId`, open pane; show read-only fields first.

    ✅ *Run & Verify*: Pane opens/close; no editing yet.

11. **Editable fields**

    * Inputs for: title, description (multiline), optional toggle, suggestions (multiline 1/line), tags (comma list).
    * Convert Firestore arrays ↔ textarea/string.

12. **Autosave on blur (debounced)**

    * Debounce ~500ms; only write changed fields.
    * Visual feedback: tiny spinner or “Saving…” indicator; snackbar “Saved”.
    * Handle errors: snackbar “Save failed”; keep local state until next change.

    ✅ *Run & Verify*: Edit fields, blur → data persists; refresh proves it.

---

## 4) Add & reorder (inline)

13. **Add root (“+ Add root goal”)**

    * Calls `createRoot("New goal")` → select it → open pane.

14. **Add child (+ in root row)**

    * Calls `createChild(rootId, "New sub-goal")` → select it → open pane.

15. **Up/Down (roots and children)**

    * Compute target neighbor; **swap `order`** for the two docs with a batched write.
    * Optimistic UI: move immediately; rollback on failure.
    * **Normalize** helper: when adjacent gap < 10, renumber sibling list by 1000’s, in one batch.

    ✅ *Run & Verify*: Reorder up/down for roots & children; refresh persists order.

---

## 5) Reparent (dropdown of root titles)

16. **Parent dropdown**

    * Populate with all **root** titles + “None (root)”.
    * When changed:

      * Update `parentId` (or null) and set `order = last+1000` under new parent.
      * Batch both fields in one transaction.
      * Move selection to stay on the same goal; UI list updates.

    ✅ *Run & Verify*: Move a child to another root and back; orders correct.

---

## 6) Delete (cascade)

17. **Cascade delete service**

    * `deleteSubtree(goalId)`:

      * DFS/BFS: collect goal + all descendants (query children by `parentId`).
      * Batch deletes in chunks (e.g., 300–450 ops per batch) until done.
      * Dialog confirm: “Delete this goal and all its sub-goals? This cannot be undone.” (as per your policy).

18. **UI hook**

    * Delete button in details pane; disable while running; snackbar on success/fail.

    ✅ *Run & Verify*: Delete root with children; verify all gone.

---

## 7) Polish UX (loading, errors, keyboard)

19. **Loading surfaces**

    * Inline spinner while initial streams load; dim rows during writes.
    * Snackbars: “Saved / Save failed / Order saved / Delete failed”.

20. **Keyboard**

    * Up/Down to move selection; Enter = View/open pane; Esc = close pane.
    * (Optional) Ctrl+R triggers normalization across current sibling list.

21. **Visuals**

    * Indent children; optional badge in accent color; hover highlights; focus ring for keyboard.

    ✅ *Run & Verify*: Play through the common flows; confirm consistent feedback.

---

## 8) Guardrails & small quality boosts

22. **Validation**

    * Prevent empty title: if user clears, show inline hint and don’t write empty titles.

23. **Small perf win**

    * Only stream children for the **selected** root (not for all roots at once).

24. **Logs**

    * Log write failures with goalId + fields for quick debugging.

    ✅ *Run & Verify*: Create/edit/reorder/reparent/delete across ~30–50 nodes comfortably.

---

## 9) Security & indexes cross-check (already decided)

25. **Rules sanity**

    * Ensure only your UID can write; reads private (as you specified).

26. **Index**

    * Verify `(parentId, order)` is present/used; create if Firestore prompts.

---

## 10) Done criteria (for this MVP)

* Single page `/goals` implements everything:

  * Create/edit with **autosave on blur**.
  * Inline **reorder** (roots + children) with normalization.
  * **Reparent** via root-dropdown.
  * **Cascade delete** with confirm.
  * Consistent loading/error feedback and keyboard nav.
* Data matches your **goal spec**; rules match your **privacy** stance.

---

