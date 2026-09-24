// Issue #183 — what an LLM call cost, read off OpenAI's `usage` block,
// added up per turn record and written on it.

import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/token_usage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TokenUsage.fromOpenAi', () {
    test('reads the cached share from prompt_tokens_details', () {
      final usage = TokenUsage.fromOpenAi({
        'prompt_tokens': 2006,
        'completion_tokens': 300,
        'total_tokens': 2306,
        'prompt_tokens_details': {'cached_tokens': 1920, 'audio_tokens': 0},
        'completion_tokens_details': {'reasoning_tokens': 128},
      });
      expect(
        usage,
        const TokenUsage(
          promptTokens: 2006,
          cachedTokens: 1920,
          completionTokens: 300,
        ),
      );
      expect(usage!.uncachedPromptTokens, 86);
    });

    test('without prompt_tokens_details the cached share is 0', () {
      final usage = TokenUsage.fromOpenAi({
        'prompt_tokens': 9,
        'completion_tokens': 1,
        'total_tokens': 10,
      });
      expect(
        usage,
        const TokenUsage(promptTokens: 9, cachedTokens: 0, completionTokens: 1),
      );
      expect(usage!.uncachedPromptTokens, 9);
    });

    test('details without cached_tokens also read as 0', () {
      final usage = TokenUsage.fromOpenAi({
        'prompt_tokens': 50,
        'completion_tokens': 5,
        'prompt_tokens_details': {'audio_tokens': 0},
      });
      expect(usage?.cachedTokens, 0);
    });

    test('anything that is not a usage block is null', () {
      expect(TokenUsage.fromOpenAi(null), isNull, reason: 'usage: null');
      expect(TokenUsage.fromOpenAi('12'), isNull);
      expect(TokenUsage.fromOpenAi({'prompt_tokens': 3}), isNull);
      expect(
        TokenUsage.fromOpenAi({'prompt_tokens': 'x', 'completion_tokens': 1}),
        isNull,
      );
    });
  });

  test('TokenUsage adds up, and round-trips through its doc shape', () {
    const a = TokenUsage(
      promptTokens: 100,
      cachedTokens: 40,
      completionTokens: 10,
    );
    const b = TokenUsage(promptTokens: 7, completionTokens: 3);
    expect(
      a + b,
      const TokenUsage(
        promptTokens: 107,
        cachedTokens: 40,
        completionTokens: 13,
      ),
    );
    expect(a.toJson(), {
      'promptTokens': 100,
      'cachedTokens': 40,
      'completionTokens': 10,
    });
    expect(TokenUsage.fromJson(a.toJson()), a);
    expect(
      TokenUsage.fromJson({'promptTokens': 5}),
      const TokenUsage(promptTokens: 5),
      reason: 'a missing count adds nothing',
    );
    expect(TokenUsage.fromJson(null), TokenUsage.zero);
  });

  test('every request type falls under one kind of call', () {
    final kinds = {
      for (final t in ChatRequestType.values) t: UsageCallKind.of(t),
    };
    expect(kinds[ChatRequestType.completeCodeQuestion], UsageCallKind.question);
    expect(kinds[ChatRequestType.mcQuestion], UsageCallKind.question);
    expect(kinds[ChatRequestType.submitCode], UsageCallKind.grading);
    expect(kinds[ChatRequestType.mcqAnswer], UsageCallKind.grading);
    expect(kinds[ChatRequestType.socraticFeedback], UsageCallKind.grading);
    expect(kinds[ChatRequestType.explainAnswer], UsageCallKind.grading);
    expect(kinds[ChatRequestType.followUpAnswer], UsageCallKind.followUp);
    expect(kinds[ChatRequestType.requestHint], UsageCallKind.hint);
    expect(kinds[ChatRequestType.studentQuestion], UsageCallKind.dialogue);
    expect(kinds[ChatRequestType.contentQuestion], UsageCallKind.dialogue);
    expect(kinds[ChatRequestType.status], UsageCallKind.status);
  });

  group('UsageLedger', () {
    const q = CallUsage(
      model: 'gpt-5-mini',
      tokens: TokenUsage(
        promptTokens: 1200,
        cachedTokens: 1024,
        completionTokens: 150,
      ),
    );
    const g = CallUsage(
      model: 'gpt-5-mini',
      tokens: TokenUsage(
        promptTokens: 1500,
        cachedTokens: 1024,
        completionTokens: 300,
      ),
    );

    test('adds the calls up per kind, and a take starts over', () {
      final ledger = UsageLedger()
        ..add(UsageCallKind.question, q)
        ..add(UsageCallKind.grading, g)
        ..add(UsageCallKind.grading, g);

      final usage = ledger.take()!;
      expect(usage.model, 'gpt-5-mini');
      expect(usage.byCall[UsageCallKind.question], q.tokens);
      expect(usage.byCall[UsageCallKind.grading], g.tokens + g.tokens);
      expect(
        usage.total,
        const TokenUsage(
          promptTokens: 4200,
          cachedTokens: 3072,
          completionTokens: 750,
        ),
      );
      expect(ledger.isEmpty, isTrue);
      expect(ledger.take(), isNull, reason: 'nothing since the last take');
    });

    test('keeps the model of the last call', () {
      final ledger = UsageLedger()
        ..add(UsageCallKind.question, q)
        ..add(
          UsageCallKind.grading,
          const CallUsage(model: 'gpt-4o', tokens: TokenUsage.zero),
        );
      expect(ledger.take()!.model, 'gpt-4o');
    });
  });

  group('TurnUsage doc shape', () {
    const usage = TurnUsage(
      model: 'gpt-5-mini',
      byCall: {
        UsageCallKind.question: TokenUsage(
          promptTokens: 1200,
          cachedTokens: 1024,
          completionTokens: 150,
        ),
        UsageCallKind.hint: TokenUsage(promptTokens: 400, completionTokens: 40),
      },
    );

    test('the sum sits at the top, the split under byCall', () {
      expect(usage.toJson(), {
        'model': 'gpt-5-mini',
        'promptTokens': 1600,
        'cachedTokens': 1024,
        'completionTokens': 190,
        'byCall': {
          'question': {
            'promptTokens': 1200,
            'cachedTokens': 1024,
            'completionTokens': 150,
          },
          'hint': {
            'promptTokens': 400,
            'cachedTokens': 0,
            'completionTokens': 40,
          },
        },
      });
    });

    test('reads back what it wrote', () {
      expect(TurnUsage.tryFromJson(usage.toJson()), usage);
    });

    test('a doc without the block reads as null; an unknown kind is '
        'dropped', () {
      expect(TurnUsage.tryFromJson(null), isNull);
      final back = TurnUsage.tryFromJson({
        'promptTokens': 10,
        'completionTokens': 1,
        'byCall': {
          'question': {'promptTokens': 10, 'completionTokens': 1},
          'teleport': {'promptTokens': 99, 'completionTokens': 99},
        },
      })!;
      expect(back.model, isNull);
      expect(back.byCall.keys, [UsageCallKind.question]);
      expect(
        back.total,
        const TokenUsage(promptTokens: 10, completionTokens: 1),
      );
    });
  });
}
