import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/version.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

const int kBufferCapacity = 200;
const int kSchemaVersion = 1;

class TurnEvent {
  final int atMs;
  final String name;
  final Map<String, dynamic>? data;

  const TurnEvent({required this.atMs, required this.name, this.data});

  Map<String, dynamic> toJson() => {
    'atMs': atMs,
    'name': name,
    if (data != null) 'data': data,
  };
}

class TurnRecord {
  final int turnId;
  final String sessionId;
  final DateTime startedAt;
  DateTime? endedAt;

  final String requestType;
  final String? currentExerciseTypeAtStart;
  final String tutorStateAtStart;
  final String? selectedRootGoalId;
  final String? selectedChildGoalId;
  final String? preferredRootGoalId;
  final String? preferredChildGoalId;
  final bool streamable;
  final String previousInputsMode;

  String? userInput;
  String? instructionsDocId;
  String? instructions;

  String? rawOutput;
  String? parsedType;
  Map<String, dynamic>? parsedResponse;

  final List<TurnEvent> events = [];
  String? error;

  TurnRecord({
    required this.turnId,
    required this.sessionId,
    required this.startedAt,
    required this.requestType,
    required this.currentExerciseTypeAtStart,
    required this.tutorStateAtStart,
    required this.selectedRootGoalId,
    required this.selectedChildGoalId,
    required this.preferredRootGoalId,
    required this.preferredChildGoalId,
    required this.streamable,
    required this.previousInputsMode,
  });

  Map<String, dynamic> toJson() {
    final ended = endedAt;
    return {
      'turnId': turnId,
      'sessionId': sessionId,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'endedAt': ended?.toUtc().toIso8601String(),
      'latencyMs': ended?.difference(startedAt).inMilliseconds,
      'requestType': requestType,
      'currentExerciseTypeAtStart': currentExerciseTypeAtStart,
      'tutorStateAtStart': tutorStateAtStart,
      'selectedRootGoalId': selectedRootGoalId,
      'selectedChildGoalId': selectedChildGoalId,
      'preferredRootGoalId': preferredRootGoalId,
      'preferredChildGoalId': preferredChildGoalId,
      'streamable': streamable,
      'previousInputsMode': previousInputsMode,
      'userInput': userInput,
      'instructionsDocId': instructionsDocId,
      'instructions': instructions,
      'rawOutput': rawOutput,
      'parsedType': parsedType,
      'parsedResponse': parsedResponse,
      'events': events.map((e) => e.toJson()).toList(),
      'error': error,
    };
  }
}

class DebugSessionRecorder {
  static const Uuid _uuid = Uuid();

  final List<TurnRecord> _buffer = [];
  TurnRecord? _current;
  int _nextTurnId = 1;

  String _sessionId = _uuid.v4();
  DateTime _sessionStartedAt = DateTime.now().toUtc();
  String? _uid;
  String? _email;
  String? _modelName;

  @visibleForTesting
  List<TurnRecord> get bufferForTest => List.unmodifiable(_buffer);

  @visibleForTesting
  TurnRecord? get currentForTest => _current;

  void resetSession({String? uid, String? email, String? modelName}) {
    try {
      _buffer.clear();
      _current = null;
      _nextTurnId = 1;
      _sessionId = _uuid.v4();
      _sessionStartedAt = DateTime.now().toUtc();
      _uid = uid;
      _email = email;
      _modelName = modelName;
    } catch (e) {
      debugPrint('DebugRecorder.resetSession: $e');
    }
  }

  void beginTurn({
    required String requestType,
    required String? currentExerciseTypeAtStart,
    required String tutorStateAtStart,
    required String? selectedRootGoalId,
    required String? selectedChildGoalId,
    required String? preferredRootGoalId,
    required String? preferredChildGoalId,
    required bool streamable,
    required String previousInputsMode,
  }) {
    try {
      if (_current != null) {
        _finalizeCurrent(error: 'beginTurn called with open turn');
      }
      _current = TurnRecord(
        turnId: _nextTurnId++,
        sessionId: _sessionId,
        startedAt: DateTime.now().toUtc(),
        requestType: requestType,
        currentExerciseTypeAtStart: currentExerciseTypeAtStart,
        tutorStateAtStart: tutorStateAtStart,
        selectedRootGoalId: selectedRootGoalId,
        selectedChildGoalId: selectedChildGoalId,
        preferredRootGoalId: preferredRootGoalId,
        preferredChildGoalId: preferredChildGoalId,
        streamable: streamable,
        previousInputsMode: previousInputsMode,
      );
    } catch (e) {
      debugPrint('DebugRecorder.beginTurn: $e');
    }
  }

  void recordRequestPayload({
    required String userInput,
    required String instructions,
    required String instructionsDocId,
  }) {
    try {
      final t = _current;
      if (t == null) return;
      t.userInput = userInput;
      t.instructions = instructions;
      t.instructionsDocId = instructionsDocId;
    } catch (e) {
      debugPrint('DebugRecorder.recordRequestPayload: $e');
    }
  }

  void recordEvent(String name, [Map<String, dynamic>? data]) {
    try {
      final t = _current;
      if (t == null) return;
      final atMs = DateTime.now().toUtc().difference(t.startedAt).inMilliseconds;
      t.events.add(TurnEvent(atMs: atMs, name: name, data: data));
    } catch (e) {
      debugPrint('DebugRecorder.recordEvent: $e');
    }
  }

  void recordRawOutput(String text) {
    try {
      final t = _current;
      if (t == null) return;
      t.rawOutput = text;
    } catch (e) {
      debugPrint('DebugRecorder.recordRawOutput: $e');
    }
  }

  void recordParsedResponse(ChatResponse parsed) {
    try {
      final t = _current;
      if (t == null) return;
      t.parsedType = parsed.type;
      try {
        t.parsedResponse = parsed.toJson();
      } catch (e) {
        t.parsedResponse = {'error': e.toString()};
      }
    } catch (e) {
      debugPrint('DebugRecorder.recordParsedResponse: $e');
    }
  }

  void recordStreamFailure(String message) {
    try {
      recordEvent('stream.failed', {'message': message});
    } catch (e) {
      debugPrint('DebugRecorder.recordStreamFailure: $e');
    }
  }

  void endTurn({String? error}) {
    try {
      _finalizeCurrent(error: error);
    } catch (e) {
      debugPrint('DebugRecorder.endTurn: $e');
    }
  }

  void _finalizeCurrent({String? error}) {
    final t = _current;
    if (t == null) return;
    t.endedAt = DateTime.now().toUtc();
    if (error != null) t.error = error;
    _buffer.add(t);
    while (_buffer.length > kBufferCapacity) {
      _buffer.removeAt(0);
    }
    _current = null;
  }

  Map<String, dynamic> exportJson() {
    try {
      return {
        'schema': kSchemaVersion,
        'sessionId': _sessionId,
        'sessionStartedAt': _sessionStartedAt.toIso8601String(),
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'appVersion': kAppVersion,
        'modelName': _modelName,
        'uid': _uid,
        'email': _email,
        'turns': _buffer.map((t) => t.toJson()).toList(),
      };
    } catch (e) {
      debugPrint('DebugRecorder.exportJson: $e');
      return {'schema': kSchemaVersion, 'error': e.toString()};
    }
  }
}

final debugServiceProvider = Provider<DebugSessionRecorder>(
  (_) => DebugSessionRecorder(),
);
