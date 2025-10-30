# Confirmations — MVP

## Overview
Only destructive or potentially confusing actions require confirmation.  
All others act immediately (autosave, reorder, reparent).

---

## Actions Requiring Confirmation

| Action | Message | Buttons |
|---------|----------|----------|
| **Delete** | “Delete this goal and all its sub-goals? This action cannot be undone.” | Primary = Delete (danger), Secondary = Cancel |
| **Connection lost while saving** | “Some changes may not have been saved.” | Primary = Retry, Secondary = Dismiss |

---

## Button Label Rules
- Primary = action verb (Delete, Move, Retry).  
- Secondary = Cancel / Dismiss.  
- Never use ambiguous “OK”.

---

## UI Behavior
- Dialogs are **modal** and block background interaction.
- Escape key = Cancel.
- Enter key = Confirm primary action.
- Focus always starts on the secondary (Cancel) to avoid accidental confirmation.

---

## Snackbar vs. Dialog Guidelines

| Type | Use When | Example |
|------|-----------|----------|
| Snackbar | Feedback after quick, safe actions | “Saved”, “Reordered”, “Deleted” |
| Dialog | Confirmation before destructive / unrecoverable actions | “Delete all sub-goals?” |

---

## Visual Consistency
- Dialog titles use app accent color or warning red for destructive flows.
- Animation: fade in/out 150 ms.
- Desktop-first; no mobile adjustments needed.
