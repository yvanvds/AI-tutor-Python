// #267: the stand-alone mode has no teacher, so the two chat notices that
// send the student to one say something else there. Every other notice, and
// both of these in school mode, read as they always have.

import 'package:ai_tutor_python/l10n/chat_notice_text.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final locale in const [Locale('en'), Locale('nl')]) {
    group(locale.languageCode, () {
      final l = lookupAppLocalizations(locale);

      test('school mode: the notices about the teacher stay as they were', () {
        expect(
          l.chatNotice(const ChatNotice(ChatNoticeKind.subgoalDeletedRedirect)),
          l.chat_notice_subgoalDeletedRedirect,
        );
        expect(
          l.chatNotice(const ChatNotice(ChatNoticeKind.emptyObjectives)),
          l.chat_notice_emptyObjectives,
        );
      });

      test('stand-alone: no teacher named', () {
        for (final kind in ChatNoticeKind.values) {
          // Only ever shown on the school's key; a stand-alone account has
          // no `mayUseGlobalKey`, so it is always on its own key.
          if (kind == ChatNoticeKind.schoolKeyInvalid ||
              kind == ChatNoticeKind.schoolKeyMissing) {
            continue;
          }
          final notice = ChatNotice(kind, args: const ['x', 'y']);
          final text = l.chatNotice(notice, standalone: true);
          expect(
            text.toLowerCase(),
            isNot(anyOf(contains('teacher'), contains('leerkracht'))),
            reason: kind.name,
          );
          // A notice that never names the teacher reads the same in both.
          if (kind != ChatNoticeKind.subgoalDeletedRedirect &&
              kind != ChatNoticeKind.emptyObjectives) {
            expect(text, l.chatNotice(notice), reason: kind.name);
          }
        }
        expect(
          l.chatNotice(
            const ChatNotice(ChatNoticeKind.emptyObjectives),
            standalone: true,
          ),
          l.chat_notice_emptyObjectives_standalone,
        );
      });

      test('stand-alone: a cause is resolved the same way', () {
        final wrapped = ChatNotice(
          ChatNoticeKind.tutorFailed,
          cause: const ChatNotice(ChatNoticeKind.subgoalDeletedRedirect),
        );
        expect(
          l.chatNotice(wrapped, standalone: true),
          l.chat_notice_tutorFailed(
            l.chat_notice_subgoalDeletedRedirect_standalone,
          ),
        );
      });
    });
  }
}
