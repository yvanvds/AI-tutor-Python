# Global UX Guidelines — MVP

## Design Philosophy
- Desktop-first, keyboard-friendly, minimal chrome.
- User should always see both hierarchy and details.
- Every action gives immediate, concise feedback.

---

## Keyboard Shortcuts
| Key | Action |
|-----|---------|
| ↑ / ↓ | Move selection |
| Enter | Open details pane |
| Esc | Close details pane |
| Ctrl + S | Force immediate save (optional trigger of autosave flush) |
| Ctrl + R | Normalize order (dev shortcut) |

---

## Focus & Accessibility
- On opening details pane → focus the **title** field.
- On closing pane → return focus to the previously selected row.
- All buttons reachable via Tab order.

---

## Colors & Motion
- Accent color reused for optional badges, highlights, and progress indicators.
- Use subtle transitions (150 ms fade/slide) only for context changes (pane open/close).

---

## Snackbar Placement
- Bottom-right corner.
- Max 3 visible at once; stack vertically.
- Each auto-dismisses after 2 seconds.

---

## Dialog Placement
- Centered on viewport.
- Dimmed background (opacity 0.3).
- Keyboard: Esc = cancel, Enter = confirm.

---

## Responsiveness
- Target resolution: ≥ 1366 × 768.
- Layout fixed-width; no mobile scaling.
- Overflowing goal list scrolls independently of details pane.

---

## Error Recovery Pattern
If Firestore write fails:
1. Snackbar “Save failed”.
2. Local data remains; retry on next change.
3. If offline persists > 30 s → modal dialog “Connection lost”.

---

## Micro-Animations
- Spinner rotates at 1 rev/s.
- Snackbar slides up / fades in simultaneously.
- Dialog fades in 150 ms, scales 1.05 → 1.

---

## Tone & Wording
- Use clear verbs: “Add”, “Edit”, “Delete”.
- Avoid passive voice or technical jargon.
- Keep snackbars ≤ 3 words when possible.
