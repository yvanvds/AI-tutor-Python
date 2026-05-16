---
name: lesson-authoring
description: Generate the lesson HTML ("Lesinhoud") for a subgoal in an existing goal JSON file. Use this skill when the teacher wants to draft, regenerate, or revise the explanatory lesson a student reads before starting exercises — phrases like "write the lesson for the variabelen subgoal", "generate lesinhoud for eenvoudige-python-scripts", "draft lessons for goal X", or "this lesson is too long, redo it". The skill reads a `goals/<slug>.json` file, picks one subgoal at a time, and emits a self-contained `lessons/<subgoal-id>.html` file the teacher can upload via the app's Lesinhoud panel.
---

# Lesson authoring

This skill is the teacher's authoring partner for **lesson HTML** — the
short Dutch explanation a student reads on the Lesinhoud panel *before*
they start practising a subgoal. The exercises themselves are generated
at runtime by the conductor from the LOs; the lesson's job is only to
bring the student up to the starting line.

The teacher knows their domain (Python, the classroom, their students).
The skill's job is to produce HTML that is correct against the app's
renderer, uses only concepts the student is allowed to know at this
point, matches the desired tone, and covers every LO without overreach.
The teacher's authority is final on every pedagogical question.

## Project files this skill depends on

These live in the project knowledge. Read them when needed; don't
operate without them.

- `goals/<slug>.json` — the authored curriculum. The skill's input.
  Each subgoal has `description`, `teachingTips`, and `objectives` (LOs)
  — together these define what the lesson must teach.
- `OVERVIEW.md` — auto-generated map of all goals and subgoals in
  curriculum order. The skill reads this to enforce the prerequisite
  rule: a lesson may only assume knowledge from earlier subgoals (in the
  current goal) and earlier goals (in the module).
- `CURRICULUM_MODEL.md` — the data model. Context only; the skill does
  not modify any JSON, only emits HTML.
- `LO_AUTHORING_RUBRIC.md` — context on what LOs look like and how
  `teachingTips` are written. Useful when interpreting the source JSON.

If `lessons/` does not exist yet, create it on first use.

## What gets generated

One HTML file per **subgoal** (not per goal, not per LO). Filename
matches the subgoal id exactly: `lessons/<subgoal-id>.html`.

The file is a **full HTML document** with the lesson stylesheet inlined,
so the teacher can double-click it and preview the result in any
browser. The app's Lesinhoud upload strips everything outside
`<body>...</body>` before storing, so the `<html>`/`<head>` wrapper is
free for previewing and costs nothing in the app.

### Document skeleton (use exactly this shape)

```html
<!doctype html>
<html lang="nl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{{Subgoal title}}</title>
<style>
{{full contents of assets/lesson/lesson.css, inlined verbatim}}
</style>
</head>
<body class="lesson">
{{lesson body — see "Body content rules" below}}
</body>
</html>
```

Always inline the **full** stylesheet, not a stripped-down copy. The
canonical CSS lives at `assets/lesson/lesson.css` in the Flutter project
knowledge; read it on first generation and reuse it across files in the
same session.

## Body content rules

### Allowed HTML

The renderer is a WebView using only `lesson.css`. Stick to tags the
stylesheet styles deliberately:

- Headings: `<h2>`, `<h3>` (skip `<h1>` — the app already shows the
  subgoal title above the lesson; an `<h1>` duplicates it).
- Paragraphs: `<p>`.
- Inline: `<code>`, `<strong>`, `<em>`, `<small>`, `<a>` (links only when
  there is a real reason — usually there isn't).
- Lists: `<ul>`, `<ol>`, `<li>`.
- Code blocks: `<pre><code>...</code></pre>`.
- Blockquote: `<blockquote>` (rarely; usually a callout is better).
- Callouts: `<div class="callout">`, `<div class="callout tip">`,
  `<div class="callout warn">`. Inside a callout, use `<p>` for the text.
- Table: `<table><thead><tr><th>…</th></tr></thead><tbody><tr><td>…
  </td></tr></tbody></table>` — only when prose would be worse.
- Horizontal rule: `<hr>` — rare; usually two `<h3>`s do the job.

### Forbidden

- No `<script>`, no inline event handlers (`onclick=` etc.). The
  WebView would execute them, but lessons must be inert text.
- No `<img>`. There is no image hosting set up for lessons, and the
  app doesn't resolve relative paths.
- No `<iframe>`, no `<form>`, no `<input>`. Lessons don't take input —
  exercises do.
- No `<style>` or `style="…"` inside the body. The body is rendered
  *inside* the global stylesheet; per-element overrides drift from the
  design system and make later restyling painful.
- No external CSS or JS links of any kind.
- No emoji or decorative unicode (the stylesheet already adds icons to
  callouts via `::before`).

### Code blocks

Show small, runnable Python snippets. Format expected output
explicitly, on the same code-block style but as a separate block, so
the student sees the cause/effect pairing:

```html
<pre><code>naam = "Mira"
print("Hallo", naam)</code></pre>
<p>Uitvoer:</p>
<pre><code>Hallo Mira</code></pre>
```

Indentation in `<pre><code>` is preserved verbatim — write Python
with 4-space indent, no leading whitespace before `print(...)` at
column 0. Don't escape Python code as `&lt;` etc. unless the literal
character `<` appears (it usually doesn't in early Python).

### Callouts — use sparingly

The stylesheet styles three callout flavors. Don't sprinkle them
throughout; one or two per lesson at most. Anchor them on the
subgoal's `teachingTips` — those describe real misconceptions and
deserve flagging.

- `<div class="callout tip"><p>…</p></div>` — a small, useful piece of
  context the student should keep in mind.
- `<div class="callout warn"><p>…</p></div>` — a common mistake or
  surprising behavior. Pull these straight from `teachingTips` where
  the tip names a misconception.
- `<div class="callout"><p>…</p></div>` (no modifier) — neutral
  information; almost never the right choice over plain `<p>`.

## Voice and language

- **Dutch.** All visible text. Code identifiers can stay in English
  where idiomatic (`name`, `age`) but examples written for Dutch
  students should prefer Dutch names where natural (`naam`, `leeftijd`).
- **Second person, informal:** "je", "jij", "jouw". Not "u". The
  audience is a ~16-year-old in their first programming exposure.
- **Friendly, not childish.** No exclamation marks at the end of every
  sentence. No "Cool!", "Super!", "Lekker bezig!". No emoji. Treat
  the student as someone learning a real skill, not a toddler. Warmth
  shows in clarity and patience, not exclamation density.
- **Concrete over abstract.** *"Je geeft een waarde een naam met `=`"*
  beats *"variabelen koppelen identifiers aan waarden in geheugen"*.
- **One idea per paragraph.** If a paragraph contains two `omdat`s
  joined by a comma, split it.
- **No meta-talk.** Don't write *"In deze les leer je over variabelen"*
  or *"We gaan nu kijken naar…"*. The student knows they're reading a
  lesson on this topic — the panel header says so. Start with the
  thing.
- **No exercise prompts.** Don't write *"Probeer dit zelf eens"* or
  *"Wat denk je dat dit doet?"*. Exercises happen in the conductor;
  the lesson is read-only preparation.

## Lesson structure

A good lesson reads in 2-4 minutes and covers every LO without making
the student feel they're being marched through a checklist.

A reliable shape:

1. **One opening sentence** that states what the subgoal lets the
   student do — derived from the subgoal `description` but rewritten so
   it doesn't read like an LO. *Not* "Je kan met print() strings tonen";
   rather *"Met `print()` toon je iets op het scherm — getallen,
   tekst, of allebei tegelijk."*
2. **Concept-by-concept exposition.** Walk the LOs in their JSON
   order, since that order was authored deliberately. For each
   concept: one or two sentences of explanation, then a small worked
   example with code and expected output.
3. **Optional callout** when a `teachingTip` names a misconception
   that's easier to flag than to weave into prose.
4. **One closing sentence** that signals readiness — *not* a summary,
   *not* a "now try the exercises", just a brief landing. *"Daarmee
   kan je een eerste eigen scriptje typen en kijken wat er
   uitkomt."*

### Length

Target **300-600 words of Dutch lesson text** (excluding code blocks).
Below 300 you're probably under-teaching one of the LOs. Above 600
you're probably re-explaining something an earlier subgoal already
covered, or you've drifted into exercise territory.

### Coverage

Every LO in `objectives` must be reachable from the lesson — meaning
a student who has read carefully has seen the concept the LO probes.
"Reachable" is weaker than "drilled". `recall` LOs may need only a
sentence; `apply` LOs need at least one worked example of the thing
being applied; `predict` LOs benefit from a code + output pairing
that mirrors what the runtime tracing question will show; `reason`
LOs need at least one sentence of *why*, not just *what*.

Coverage is not a checklist printed in the lesson. The student should
not see the LO ids. The skill verifies coverage internally during
the self-critique pass.

## Prerequisite discipline

The lesson may use:

- Anything introduced in earlier subgoals of the **same** goal.
- Anything introduced in earlier goals of the **same** module.
- Anything outside the curriculum that the curriculum has explicitly
  noted is assumed (look for "treated as known from outside" notes in
  the goal `description`).

The lesson may **not** introduce concepts that belong to later
subgoals or later goals — even informally, even "just as a teaser".
Forward references undermine the curriculum's ordering and surface
later as students asking about things the conductor has not yet
opened up.

When in doubt, check `OVERVIEW.md`. If a concept appears only in a
later subgoal, either rephrase to avoid it or surface the conflict
to the teacher (*"this lesson naturally wants to mention `if`, but
that's in a later goal — should I rephrase, or are you happy to lean
on intuition?"*). Don't silently ship a forward reference.

## The flow

### Step 1: Pick the goal file and read it

The teacher names a goal file (*"do the lessons for
`eenvoudige-python-scripts`"*) or a single subgoal (*"redo the lesson
for `variabelen`"*). Read the JSON. Read `OVERVIEW.md` so you know
what's introduced earlier and what's introduced later.

If the teacher named the goal but not a specific subgoal, list the
subgoals in order and ask which one to start with. **Default: one
subgoal at a time.** Generating five at once produces five generic
lessons; generating one at a time invites the teacher to set the
tone, which then carries to the rest.

### Step 2: Read the stylesheet once per session

Read `assets/lesson/lesson.css` from the project. Hold the full text
ready — every lesson file will inline it verbatim. Don't rewrite,
trim, or "improve" the CSS; the app's WebView relies on the exact
classes and variables it defines.

### Step 3: Draft the lesson body

Working from the subgoal's `description`, `teachingTips`, and
`objectives`:

- Walk the LOs in their authored order and decide which become a full
  worked example, which fold into a sentence, and which deserve a
  callout. (Heuristic: `apply` and `predict` LOs almost always get a
  worked example; `recall` folds into a sentence; `reason` gets a
  sentence of "why" — sometimes a callout, depending on the
  `teachingTip` content.)
- Draft the body in HTML, following "Body content rules" and "Voice
  and language" above.
- Keep code snippets small — three to six lines each. Multiple small
  snippets beat one long one for first-exposure students.

### Step 4: Self-critique pass

Before emitting, run this checklist. Report each finding to the
teacher with the LO/section it concerns and a proposed fix. The skill
never refuses to emit — the teacher confirms or amends, then it
writes.

| # | Check                                                          |
|---|----------------------------------------------------------------|
| 1 | Every LO in `objectives` is reachable from the lesson text     |
| 2 | No forward reference to later subgoals or goals                |
| 3 | No `<script>`, `<img>`, `<form>`, `<iframe>`, inline `style="…"`, or external links |
| 4 | Only tags the stylesheet styles deliberately are used          |
| 5 | All visible text is Dutch; tone is friendly, not childish      |
| 6 | No meta-talk ("In deze les…", "We gaan nu…") or exercise prompts |
| 7 | Body text length is roughly 300-600 words (excluding code)     |
| 8 | At least one code snippet per `apply` and `predict` LO         |
| 9 | Callouts used sparingly (0-2 per lesson) and tied to a real misconception from `teachingTips` |
|10 | Code snippets use only concepts available at this curriculum point |
|11 | No `<h1>` (panel header already shows the subgoal title)       |
|12 | Document skeleton matches the "shape" exactly; CSS inlined verbatim |

Items 1-4 are correctness issues — flag prominently. Items 5-10 are
quality issues. Items 11-12 are mechanical.

### Step 5: Emit the file

Write to `lessons/<subgoal-id>.html`. Use the exact subgoal id from
the JSON; don't transliterate or rename. Overwrites are expected
(regenerating a lesson should replace the previous file).

Confirm to the teacher: *"Lesson for `<subgoal-id>` written to
`lessons/<subgoal-id>.html`. Open it in a browser to preview, then
upload via the Lesinhoud panel."*

### Step 6: Offer the next subgoal

If the teacher started from a goal-level request (*"do the lessons
for X"*), offer the next subgoal in `order`. *"Next would be
`<next-subgoal-id>` — proceed?"* If they started from a single
subgoal, stop and wait.

## Editing an existing lesson

When the teacher asks for a revision (*"this is too long"*, *"the
print example is unclear"*, *"add a callout about the comma bug"*):

1. Read the existing `lessons/<subgoal-id>.html`.
2. Read the subgoal JSON again — coverage and prerequisite rules still
   apply.
3. Apply the requested change. Don't take the opportunity to silently
   rewrite the rest of the lesson — change what was asked, leave the
   rest. Teachers iterate on lessons they're attached to.
4. Re-run the self-critique pass on the changed sections.
5. Overwrite the file.

## Hard rules

- **The lesson is read-only preparation, not an exercise.** No
  prompts, no "try it yourself", no quiz questions, no input fields.
  Exercises belong to the conductor.
- **No forward references.** Use only concepts authored in earlier
  subgoals and earlier goals. When unsure, check `OVERVIEW.md`.
- **No tags or attributes the stylesheet doesn't expect.** The renderer
  has no fallback styling; off-spec HTML looks broken or invisible.
- **Inline the full `lesson.css` verbatim in every file.** No trimming,
  no "minimal" copy. Standalone browser preview must match the in-app
  appearance.
- **Dutch, second person, friendly without exclamation density or
  emoji.** This is the audience-facing voice; deviations drag the
  reading down.
- **One file per subgoal, named exactly `<subgoal-id>.html`.** The
  filename is the contract with the app's import path.
- **The skill writes only `lessons/*.html`.** It does not modify goal
  JSON, the overview, or the stylesheet.

## What this skill does not do

- **Does not author or edit goal JSON.** That's `goal-authoring`'s
  job. If the lesson reveals a hole in the LOs (an obvious concept the
  student needs, no LO covering it), surface it to the teacher and
  suggest they switch over to `goal-authoring` to fix the goal first.
- **Does not upload to the app.** It writes files to disk; the teacher
  uploads them via the Lesinhoud panel.
- **Does not regenerate `OVERVIEW.md`.** Only `goal-authoring` touches
  the overview.
- **Does not generate runtime exercises, quizzes, or hints.** Those
  are produced live by the conductor against the LOs.
- **Does not author images, diagrams, or media.** Text and code only.
- **Does not manage modules or cross-goal structure.** Module-level
  shape is `goal-authoring`'s concern.
