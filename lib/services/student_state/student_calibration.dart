// Per-student difficulty calibration substructure embedded on the account
// doc per `docs/STUDENT_MODEL.md` "Account doc (extended)".

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';

class CalibrationAnswer {
  final AnswerQuality quality;
  final QuestionDifficulty difficulty;
  final DateTime at;
  const CalibrationAnswer({
    required this.quality,
    required this.difficulty,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'quality': quality.name,
        'difficulty': difficulty.name,
        'at': at.toUtc().toIso8601String(),
      };

  factory CalibrationAnswer.fromJson(Map<String, dynamic> map) {
    return CalibrationAnswer(
      quality: _quality(map['quality']),
      difficulty: _difficulty(map['difficulty']),
      at: _date(map['at']),
    );
  }

  static AnswerQuality _quality(Object? raw) {
    if (raw is! String) return AnswerQuality.wrong;
    for (final q in AnswerQuality.values) {
      if (q.name == raw) return q;
    }
    return AnswerQuality.wrong;
  }

  static QuestionDifficulty _difficulty(Object? raw) {
    if (raw is! String) return QuestionDifficulty.medium;
    for (final d in QuestionDifficulty.values) {
      if (d.name == raw) return d;
    }
    return QuestionDifficulty.medium;
  }

  static DateTime _date(Object? raw) {
    if (raw is! String) return DateTime.utc(1970);
    return DateTime.tryParse(raw) ?? DateTime.utc(1970);
  }
}

class StudentCalibration {
  /// Per STUDENT_MODEL "Starting value": new students start at medium.
  static const QuestionDifficulty defaultDifficulty = QuestionDifficulty.medium;

  final QuestionDifficulty difficulty;
  final List<CalibrationAnswer> recentAnswers;
  final List<String> recentQuestionTypes;

  const StudentCalibration({
    required this.difficulty,
    this.recentAnswers = const [],
    this.recentQuestionTypes = const [],
  });

  factory StudentCalibration.fresh() => const StudentCalibration(
        difficulty: defaultDifficulty,
      );

  StudentCalibration copyWith({
    QuestionDifficulty? difficulty,
    List<CalibrationAnswer>? recentAnswers,
    List<String>? recentQuestionTypes,
  }) {
    return StudentCalibration(
      difficulty: difficulty ?? this.difficulty,
      recentAnswers: recentAnswers ?? this.recentAnswers,
      recentQuestionTypes: recentQuestionTypes ?? this.recentQuestionTypes,
    );
  }

  Map<String, dynamic> toJson() => {
        'difficulty': difficulty.name,
        'recentAnswers': recentAnswers.map((a) => a.toJson()).toList(),
        'recentQuestionTypes': recentQuestionTypes,
      };

  factory StudentCalibration.fromJson(Map<String, dynamic> map) {
    final diffRaw = map['difficulty'];
    QuestionDifficulty diff = defaultDifficulty;
    if (diffRaw is String) {
      for (final d in QuestionDifficulty.values) {
        if (d.name == diffRaw) {
          diff = d;
          break;
        }
      }
    }
    final answers = <CalibrationAnswer>[];
    final rawAnswers = map['recentAnswers'];
    if (rawAnswers is List) {
      for (final entry in rawAnswers) {
        if (entry is Map) {
          answers.add(CalibrationAnswer.fromJson(
            entry.cast<String, dynamic>(),
          ));
        }
      }
    }
    final types = <String>[];
    final rawTypes = map['recentQuestionTypes'];
    if (rawTypes is List) {
      for (final entry in rawTypes) {
        if (entry is String) types.add(entry);
      }
    }
    return StudentCalibration(
      difficulty: diff,
      recentAnswers: answers,
      recentQuestionTypes: types,
    );
  }

  /// Append a fresh calibration answer to the window, evicting the oldest
  /// when over capacity.
  StudentCalibration withAppendedAnswer(CalibrationAnswer answer) {
    final next = List<CalibrationAnswer>.from(recentAnswers)..add(answer);
    while (next.length > PolicyConstants.calibrationWindow) {
      next.removeAt(0);
    }
    return copyWith(recentAnswers: next);
  }

  /// Append a question type to the cross-LO ring buffer.
  StudentCalibration withAppendedQuestionType(String typeName) {
    final next = List<String>.from(recentQuestionTypes)..add(typeName);
    while (next.length > PolicyConstants.recentQuestionTypesWindow) {
      next.removeAt(0);
    }
    return copyWith(recentQuestionTypes: next);
  }
}
