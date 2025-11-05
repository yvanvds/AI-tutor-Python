// import 'package:ai_tutor_python/data/code/code_provider.dart';
// import 'package:ai_tutor_python/services/chat_service.dart';
// import 'package:ai_tutor_python/services/timeline/code_entry.dart';
// import 'package:ai_tutor_python/services/timeline/message_entry.dart';
// import 'package:flutter/material.dart';
// import 'package:hooks_riverpod/hooks_riverpod.dart';
// import 'package:hooks_riverpod/legacy.dart';

// final timeLineProvider = ChangeNotifierProvider<TimeLine>((ref) {
//   final timeLine = TimeLine(ref: ref);
//   ref.onDispose(timeLine.dispose);
//   return timeLine;
// });

// class TimeLine extends ChangeNotifier {
//   final List<CodeEntry> _codes = [];
//   int _currentItem = 0;
//   final Ref ref;

//   // Notifiers that widgets can listen to:
//   bool get canGoPrev => _currentItem > 0;
//   bool get canGoNext => _currentItem < _codes.length - 1;
//   int get currentIndex => _currentItem;

//   TimeLine({required this.ref}) {
//     _codes.add(CodeEntry(code: ""));
//   }

//   // --- Message helpers -------------------------------------------------------

//   void addSystemMessage(String text) => _addMessage(MessageRole.system, text);

//   void addUserMessage(String text) => _addMessage(MessageRole.user, text);

//   void addAiMessage(String text) => _addMessage(MessageRole.ai, text);

//   void _addMessage(MessageRole role, String text) {
//     final msg = MessageEntry(role: role, text: text);
//     _codes.last.addMessage(msg);
//   }

//   List<MessageEntry> getCurrentMessages() => _codes[_currentItem].messages;

//   // --- Code helpers ----------------------------------------------------------

//   void startNewCode(String code) {
//     _codes.add(CodeEntry(code: code));
//     notifyListeners();
//   }

//   void updateCurrentCode(String newCode) {
//     _codes[_currentItem].code = newCode;
//   }

//   String getCurrentCode() => _codes[_currentItem].code;

//   void goPrev() {
//     if (_currentItem > 0) {
//       _currentItem--;
//       _updateNavigationState();
//       notifyListeners();
//     }
//   }

//   void goNext() {
//     if (_currentItem < _codes.length - 1) {
//       _currentItem++;
//       _updateNavigationState();
//       notifyListeners();
//     }
//   }

//   void _updateNavigationState() {
//     // set the code in the code editor
//     ref.read(codeProvider.notifier).state = _codes[_currentItem].code;

//     // set the chat messages
//     final chat = ref.read(chatServiceProvider);
//     chat.clear();
//     for (final msg in _codes[_currentItem].messages) {
//       if (msg.role == MessageRole.user) {
//         chat.addMessage(msg.text);
//       } else if (msg.role == MessageRole.ai) {
//         chat.addTutorMessage(msg.text);
//       }
//     }
//   }
// }
