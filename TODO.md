# TODO

## AI response speed — remaining work

After the streaming + chat.completions migration the perceived wait dropped,
but a sibling project (`D:\DoThing\lib`) still feels noticeably faster.
The differences below explain the gap, in roughly descending impact order.

### 1. Audit the system prompt size

Likely the biggest single factor. Every tutor request re-sends:

- `envelopeContract` (~150 tokens, fixed — can't shrink)
- All `alwaysInclude` sections (teacher-edited, unbounded)
- The type-specific instruction block (teacher-edited, unbounded)
- Substituted `{goal}/{subgoal}/{suggestions}/{known concepts}`

A "comprehensive" set of teacher docs can easily be 2-8k tokens of system
prompt **per call**. Input-token processing is what dominates time-to-first-
token on `gpt-4o`, and prompt caching only helps after the first call within
a goal session (and doesn't survive a 5-minute idle).

DoThing's chat path sends *no system prompt at all* on the chat call
(`D:\DoThing\lib\controllers\ai\ai_chat_controller.dart` around line 288 —
just `messages`, no system role). Its planner has a system prompt but it's
a separate small call against the mini model.

**Action:**
- Add a one-line `debugPrint('system prompt: ${instructions.length} chars')`
  in `OpenaiConnector.sendRequest`/`sendRequestStream` (gated behind an assert).
- Run a typical tutoring session and look at the printed sizes.
- If the prompts are large, prune the teacher-edited `alwaysInclude` and
  per-type docs. Cut anything aspirational/decorative — every char is paid for
  on every turn.

### 2. Stop JSON-encoding assistant turns into history

Currently `OpenaiConnector.addResponse` does:
```dart
final jsonString = jsonEncode(response.toJson());
_allHistory.add({'role': 'assistant', 'content': jsonString});
```
So the conversation history the model re-receives every turn is a stack of
`{"type":"hint","prompt":"..."}`, `{"type":"code_feedback","prompt":"...",
"suggestion":"...","quality":"correct"}`, etc. After 10-20 turns this is a
measurable input-token tax that grows linearly with session length.

The model doesn't need the structured shape to follow context — it just
needs the prompt text. DoThing stores plain text and is fine.

**Action:** in `addResponse`, store only the `prompt` (or `message` for
errors) instead of the JSON-encoded `toJson()`. Smaller history, faster,
identical model behaviour.

### 3. Replace the dart_openai fork with a direct HTTP transport

Smaller win, larger refactor. The `dart_openai` fork routes through
`fetch_client` plus its own SSE parsing plus a global `OpenAI.apiKey = ...`
setter on every call. None of this is *slow* in isolation but it adds
~50-300 ms per call and each layer is one more place where buffering can
swallow stream tokens before they hit the UI.

DoThing uses `dart:io HttpClient` directly:
`D:\DoThing\lib\services\ai\openai_chat_service.dart` — open POST, push
JSON, parse SSE line-by-line. About 100 lines, no third-party dependency.

**Action:** half-day of work. Drop the `dart_openai` git pin from
`pubspec.yaml`, port `OpenaiConnector.sendRequest` / `sendRequestStream`
to a hand-rolled `HttpClient`-based transport, keep the same public
surface so `TutorService` doesn't notice. Optional, do this last.

### 4. Model — re-check the assumption

Tagged "non-negotiable" but worth one more look. Default in the code is
`gpt-4o`, which is from mid-2024 and is *older*, not just smaller, than
the current generation. DoThing's defaults are `gpt-5.4` / `gpt-5.4-mini` /
`gpt-5.4-nano` (`D:\DoThing\lib\models\ai\ai_settings.dart` line 6+).

The "older models give worse output" intuition is correct vs `gpt-4o-mini`
or earlier minis. It is **not** correct vs the current `gpt-5.x` base
(faster *and* smarter than `gpt-4o`). At minimum, swapping the default in
`config/global.Model` from `gpt-4o` to the latest `gpt-5.x` base buys
both speed and quality. The mini variant is also worth trying for
hint/feedback turns (split-tier model selection — see also
`PROJECT_OVERVIEW.md` "AI provider").
