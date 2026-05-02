# TODO

## Progression
A student can now muddle through on easy and still complete the subgoal. Maybe the should only complete if after answering some more difficult questions?

## python packages
We should be able to use matplotlib, pandas, numpy, turtle at least.

## GoalSplashOverlay
Visible for quite a long time. Shorten or enable use to click away.

## Migrate from `get_it` + `ValueNotifier` to Riverpod

The current pattern is coherent and works, but I use Riverpod in newer apps and the context-switch tax adds up. Riverpod also makes lifetime discipline structural rather than manual (the dead `AccountService.dispose()` and unwired `LocalApiKeyStorage` are symptoms of the current pattern not enforcing this), replaces the `MultiValueListenableBuilder` workaround with native multi-watch, and makes the conductor → progress → goals dependency web self-documenting via explicit provider graphs. Path-of-least-resistance fits: services become providers, `ValueNotifier`s become `Notifier`/`AsyncNotifier`, polling streams map onto `StreamProvider`, `DataService.x` static getters are replaced with `ref.read/watch`.

Sequencing: do this *after* the Python runner swap is in (don't muddy unrelated changes), and ideally after a round of test coverage on the conductor and progress flows since that's where regressions would hurt students rather than developers. Migrate in a single focused pass — half-migrated state is worse than either end. Pick a quiet window rather than during active classroom use, so any regression has breathing room to be caught and fixed.


## Fix errors




