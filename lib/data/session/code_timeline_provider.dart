// lib/data/session/code_timeline_provider.dart
import 'package:ai_tutor_python/data/session/code_entry.dart';
import 'package:ai_tutor_python/data/session/message_entry.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:uuid/uuid.dart';

@immutable
class CodeTimelineState {
  final List<CodeEntry> codes;
  final List<MessageEntry> messages;
  final int activeIndex; // index into codes

  const CodeTimelineState({
    required this.codes,
    required this.messages,
    required this.activeIndex,
  });

  const CodeTimelineState.initial()
    : codes = const [],
      messages = const [],
      activeIndex = -1;

  bool get hasCodes => codes.isNotEmpty;
  int get totalCodes => codes.length;
  bool get canGoPrev => hasCodes && activeIndex > 0;
  bool get canGoNext => hasCodes && activeIndex < codes.length - 1;

  CodeTimelineState copyWith({
    List<CodeEntry>? codes,
    List<MessageEntry>? messages,
    int? activeIndex,
  }) => CodeTimelineState(
    codes: codes ?? this.codes,
    messages: messages ?? this.messages,
    activeIndex: activeIndex ?? this.activeIndex,
  );

  Map<String, dynamic> toJson() => {
    'codes': codes.map((e) => e.toJson()).toList(),
    'messages': messages.map((e) => e.toJson()).toList(),
    'activeIndex': activeIndex,
  };

  factory CodeTimelineState.fromJson(Map<String, dynamic> json) =>
      CodeTimelineState(
        codes: (json['codes'] as List<dynamic>)
            .map((e) => CodeEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        messages: (json['messages'] as List<dynamic>)
            .map((e) => MessageEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        activeIndex: json['activeIndex'] as int,
      );
}

class CodeTimeline extends Notifier<CodeTimelineState> {
  final _uuid = const Uuid();

  @override
  CodeTimelineState build() => CodeTimelineState.initial();

  // --- Message helpers -------------------------------------------------------

  void addSystemMessage(String text) => _addMessage(MessageRole.system, text);

  void addUserMessage(String text) => _addMessage(MessageRole.user, text);

  void addAiMessage(String text) => _addMessage(MessageRole.ai, text);

  void _addMessage(MessageRole role, String text) {
    final msg = MessageEntry(
      id: _uuid.v4(),
      role: role,
      text: text,
      createdAt: DateTime.now(),
    );
    final newMessages = List<MessageEntry>.from(state.messages)..add(msg);
    state = state.copyWith(messages: newMessages);
  }

  // --- Code helpers ----------------------------------------------------------

  /// Starts a new code page and makes it active.
  /// Links it to the *current* message count so subsequent messages belong here.
  String startNewCode(String code) {
    final id = _uuid.v4();
    final firstMessageIndex = state.messages.length;
    final entry = CodeEntry(
      id: id,
      code: code,
      firstMessageIndex: firstMessageIndex,
    );
    final newCodes = List<CodeEntry>.from(state.codes)..add(entry);
    debugPrint('There are now ${newCodes.length} code entries.');
    state = state.copyWith(codes: newCodes, activeIndex: newCodes.length - 1);
    return id;
  }

  /// Updates the *last* code page (useful when the student submits changes).
  /// If there is no code yet, this behaves like startNewCode.
  void updateLastCode(String newCode) {
    if (state.codes.isEmpty) {
      startNewCode(newCode);
      return;
    }
    final lastIdx = state.codes.length - 1;
    final updated = state.codes[lastIdx].copyWith(code: newCode);
    final newCodes = List<CodeEntry>.from(state.codes)..[lastIdx] = updated;
    state = state.copyWith(codes: newCodes);
  }

  /// Sets the active code by *index*. Use for prev/next buttons.
  void setActiveIndex(int index) {
    if (index < 0 || index >= state.codes.length) return;
    state = state.copyWith(activeIndex: index);
  }

  /// Sets the active code by *id*.
  void setActiveId(String codeId) {
    final index = state.codes.indexWhere((c) => c.id == codeId);
    if (index != -1) setActiveIndex(index);
  }

  void goPrev() {
    if (state.canGoPrev) setActiveIndex(state.activeIndex - 1);
  }

  void goNext() {
    if (state.canGoNext) setActiveIndex(state.activeIndex + 1);
  }

  /// Handy for button states.
  bool get canGoPrev => state.canGoPrev;
  bool get canGoNext => state.canGoNext;
  int get totalCodes => state.totalCodes;
  int get activeIndex => state.activeIndex;

  CodeEntry? get activeCode =>
      (state.activeIndex >= 0 && state.activeIndex < state.codes.length)
      ? state.codes[state.activeIndex]
      : null;

  /// Returns the messages that belong to the active code page.
  List<MessageEntry> get activeMessages {
    final idx = state.activeIndex;
    if (idx < 0 || idx >= state.codes.length) return const [];
    return messagesForCodeIndex(idx);
  }

  /// Slices messages that belong to code at [index].
  List<MessageEntry> messagesForCodeIndex(int index) {
    final codes = state.codes;
    final messages = state.messages;

    if (index < 0 || index >= codes.length) return const [];

    final start = codes[index].firstMessageIndex;
    final end = (index == codes.length - 1)
        ? messages.length
        : codes[index + 1].firstMessageIndex;

    if (start < 0 || start > messages.length) return const [];
    final safeEnd = end.clamp(start, messages.length);
    return messages.sublist(start, safeEnd);
  }

  /// Replace everything (useful if you later persist/restore).
  void loadFromJson(Map<String, dynamic> json) {
    state = CodeTimelineState.fromJson(json);
  }

  Map<String, dynamic> toJson() => state.toJson();

  void reset() {
    state = CodeTimelineState.initial();
  }
}

/// Riverpod provider for the timeline.
final codeTimelineProvider = NotifierProvider<CodeTimeline, CodeTimelineState>(
  CodeTimeline.new,
);

/// Convenience selectors for UI widgets:

/// Currently active code entry (or null).
final activeCodeProvider = Provider<CodeEntry?>((ref) {
  final st = ref.watch(codeTimelineProvider);
  final idx = st.activeIndex;
  return (idx >= 0 && idx < st.codes.length) ? st.codes[idx] : null;
});

/// Messages that belong to the currently active code entry.
final activeMessagesProvider = Provider<List<MessageEntry>>((ref) {
  final timeline = ref.watch(codeTimelineProvider.notifier);
  return timeline.activeMessages;
});

/// Button state helpers.
final canGoPrevProvider = Provider<bool>((ref) {
  final st = ref.watch(codeTimelineProvider);
  return st.canGoPrev;
});
final canGoNextProvider = Provider<bool>((ref) {
  final st = ref.watch(codeTimelineProvider);
  return st.canGoNext;
});
final totalCodesProvider = Provider<int>((ref) {
  final st = ref.watch(codeTimelineProvider);
  return st.totalCodes;
});
