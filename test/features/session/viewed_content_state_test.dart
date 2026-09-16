// #132 — which theory page is on screen, and whether a question typed now
// is about it. The theory view publishes what it draws; the tutor and the
// composer read `askAboutPageProvider`, which is true only in the theory
// view with a page in it. A view that leaves can only take down its own
// page: with the mode switcher's cross-fade the leaving view and the
// arriving one overlap, and the leaving one's `hide` must not clear what
// the arriving one just showed.

import 'package:ai_tutor_python/features/session/viewed_content_state.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer pc;

  setUp(() {
    pc = ProviderContainer();
  });

  tearDown(() => pc.dispose());

  ViewedContentNotifier viewed() => pc.read(viewedContentIdProvider.notifier);
  String? id() => pc.read(viewedContentIdProvider);
  bool asks() => pc.read(askAboutPageProvider);
  void mode(SessionMode m) => pc.read(modeProvider.notifier).state = m;

  test('nothing is on screen until a view shows a page', () {
    expect(id(), isNull);
    expect(asks(), isFalse);
  });

  test('show publishes the page; a placeholder is null', () {
    final view = Object();
    viewed().show(view, 's1');
    expect(id(), 's1');
    viewed().show(view, null);
    expect(id(), isNull);
    viewed().show(view, 's0');
    expect(id(), 's0');
  });

  test('the owner can hide its page; a stranger cannot', () {
    final view = Object();
    viewed().show(view, 's1');
    viewed().hide(Object());
    expect(id(), 's1', reason: 'only the view that showed it takes it down');
    viewed().hide(view);
    expect(id(), isNull);
  });

  test('a leaving view does not clear the page the arriving one showed, '
      'whichever order their show and hide land in', () {
    final leaving = Object();
    final arriving = Object();
    viewed().show(leaving, 's1');

    // Cross-fade: the arriving view builds (and publishes) before the
    // leaving one is disposed — even the same page.
    viewed().show(arriving, 's1');
    viewed().hide(leaving);
    expect(id(), 's1');

    // The other order: the leaving one is gone first.
    viewed().hide(arriving);
    expect(id(), isNull);
    viewed().show(Object(), 's2');
    expect(id(), 's2');
  });

  test('a question is about the page only in the theory view with a page '
      'on screen', () {
    final view = Object();
    mode(SessionMode.explain);
    expect(asks(), isFalse, reason: 'no page yet');

    viewed().show(view, 's1');
    expect(asks(), isTrue);

    mode(SessionMode.practice);
    expect(
      asks(),
      isFalse,
      reason: 'practice: the tutor\'s question lives here',
    );

    mode(SessionMode.playground);
    expect(asks(), isFalse);

    mode(SessionMode.explain);
    expect(asks(), isTrue, reason: 'the page is still published');

    viewed().show(view, null);
    expect(asks(), isFalse, reason: 'a subgoal without a lesson');

    viewed().show(view, 's1');
    viewed().hide(view);
    expect(asks(), isFalse, reason: 'the view is gone');
  });
}
