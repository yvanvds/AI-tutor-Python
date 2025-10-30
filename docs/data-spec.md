  # goals
  
   * `title` (required)
   * `description` (optional plaintext)
   * `parentId` (nullable; root = null)
   * `order` (int; gapped increments, e.g., 1000)
   * `optional` (bool; default false)
   * `suggestions` (string list; default empty)
   * `tags` (string list; default empty)

behavior notes:

   * Cascade delete
   * Reparent allowed
   * Reorder within siblings
   * Autosave on blur (debounced)

indexes:
   * goals: (parentId ASC, order ASC)
