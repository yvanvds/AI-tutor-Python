# How do you get your grade?

*Goes with version 1.1.1 of the grade formula. The app computes with
formula 1.1: that number is also in My reports.*

## What counts for your grade?

For each report, your teacher picks the learning objectives you should
master by then, and an expected level: easy, medium or hard. A student who
just passes can do the **core learning objectives**. The others are
**extension learning objectives**.

What counts per learning objective: did you demonstrate it, and at what
level? All core ones demonstrated at the expected level give at least
50 out of 100. Extension ones and hard questions take you higher.

## How do I compute my grade?

```
M = 50 · k  +  50 · k · (0.6 · u + 0.4 · d)
```

- **M** is your grade out of 100, before rounding.
- **k** is the share of core learning objectives you demonstrated at the
  expected level or higher: all = 1, half = 0.5.
- **u** is the share of extension ones you demonstrated.
- **d** is the share of all your demonstrated ones on which you also
  answered a hard question well.
- **0.6** and **0.4** say how much u and d weigh.

The first part goes up to 50. The second takes you from 50 to 100, but is
multiplied by k: without the core, no top score.

**Example.** You demonstrated 8 of the 10 core learning objectives at the
expected level: k = 0.8. Of the 4 extension ones you demonstrated 2:
u = 0.5. On 3 of your 10 demonstrated ones (8 + 2) you also answered a
hard question well: d = 0.3.

```
M = 50 · 0.8 + 50 · 0.8 · (0.6 · 0.5 + 0.4 · 0.3)
  = 40 + 40 · 0.42
  = 40 + 16.8 = 56.8   →   your grade is 57
```

The full formula writes C(k), w_u and w_d. Today those are k, 0.6 and 0.4,
still provisional.

## When have I demonstrated a learning objective?

When the tutor is sure enough that you can do it:

- you answered at least two questions about it fully right;
- at least one of them was not a multiple-choice question;
- at least one good answer came at your level or higher;
- your answers about it are mostly right, especially the latest.

Two or three right answers are usually enough. The Learning path shows
each learning objective as "demonstrated" or "not yet demonstrated".

## Can I lose what I demonstrated?

No. Demonstrated stays demonstrated. After a later mistake on it, the tutor
may ask about it again, but your grade doesn't drop. Working on never
lowers your grade.

## What if I make mistakes?

Mistakes are part of learning. With every new answer, older answers count
a little less, so the latest weigh the most. Make mistakes first and then
get it, and you still demonstrate it. If you are stuck, you may move on and
it comes back later.

## Do hard questions count more?

Yes. A right answer to a hard question shows more than to an easy one. A
mistake on a hard question weighs less, though. So a higher level doesn't
make demonstrating harder.

The tutor finds your level by itself: when it goes well, the questions get
harder; when it often doesn't, easier. At the top you see how hard your
exercise is.

## Does class work count differently from homework?

An answer in class counts a little more: × 1.25. That holds from 10 minutes
before to 10 minutes after a lesson of your class, wherever you are.
Homework counts normally, never less.

## Does old material come back?

Yes. A session can start with a **review question** about something you
demonstrated long ago. In between, a **check question** may come about an
earlier learning objective you haven't demonstrated yet, so you can still
show it. The app announces these questions.

## What do I see, and when?

While you work, you see your progress, not a grade. Your grade comes at the
report moment, when your teacher releases it in **My reports**, with an
explanation. Under "How this grade was computed" you find M, k, u and d,
and the day of the calculation: what you had demonstrated by then counts.

## Who decides on my grade?

The formula proposes a grade. The AI only writes the explanation with it,
never the number. Your teacher reads everything, can adjust the grade for
what the app doesn't see, and signs off. A grade that is already on your
report never changes.

## What doesn't work?

- **Clicking multiple-choice answers until one is right.** A right choice
  counts only half, and without a right answer to another kind of question
  you demonstrate nothing.
- **Failing on purpose to get easier questions.** The core only counts at
  the expected level.
- **Letting someone tell you the answers.** Your answers in class weigh
  more, and your teacher sees it when you do much better at home than in
  class.
- **Talking the AI round.** The explanation with your grade doesn't change
  the number.

## Where is everything, exactly?

Below this text is the button to the full grade formula, in Dutch, with
every rule down to the decimal.
