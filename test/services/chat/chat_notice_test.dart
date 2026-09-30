// Issue #211 — a notice about a goal (warm-up, recheck) carries the goal's
// id next to its Dutch title, through the chat message's metadata, so the
// pill can name the goal in the app language when it renders.

import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const warmUp = ChatNotice(
    ChatNoticeKind.warmUpReview,
    args: ['Printen'],
    goalId: 's1',
  );

  test('the goal id survives the round trip through the metadata', () {
    final json = warmUp.toJson();
    expect(json, {
      'kind': 'warmUpReview',
      'args': ['Printen'],
      'goalId': 's1',
    });
    expect(ChatNotice.fromJson(json), warmUp);
    expect(ChatNotice.fromJson(json)!.goalId, 's1');
  });

  test('a notice without a goal writes no goal id and reads none', () {
    const plain = ChatNotice(ChatNoticeKind.noGoalsLeft);
    expect(plain.toJson(), {'kind': 'noGoalsLeft'});
    expect(ChatNotice.fromJson(plain.toJson())!.goalId, isNull);
    expect(
      ChatNotice.fromJson({'kind': 'recheck', 'goalId': 42})!.goalId,
      isNull,
    );
  });

  test('the goal id is part of equality', () {
    expect(
      warmUp,
      isNot(const ChatNotice(ChatNoticeKind.warmUpReview, args: ['Printen'])),
    );
  });

  test('withGoalTitle puts the title in args[0] and keeps the rest', () {
    final shown = warmUp.withGoalTitle('Printing');
    expect(shown.kind, ChatNoticeKind.warmUpReview);
    expect(shown.args, ['Printing']);
    expect(shown.goalId, 's1');
  });
}
