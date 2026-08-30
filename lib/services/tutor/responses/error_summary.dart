import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';

class ErrorResponse implements ChatResponse {
  @override
  final String type;

  /// Log-facing description. What the student sees is [notice] when set
  /// (parser / factory generated errors), else this text verbatim (an
  /// `error` reply authored by the model).
  final String message;

  /// Localizable form for errors the app itself generated (#23).
  final ChatNotice? notice;

  ErrorResponse({required this.type, required this.message, this.notice});

  /// What to show in chat for this error.
  ChatNotice get chatNotice => notice ?? ChatNotice.raw(message);

  factory ErrorResponse.fromMap(Map<String, dynamic> map) {
    return ErrorResponse(
      type: map['type'] ?? 'error',
      message: map['message'] ?? 'Unknown error occurred.',
    );
  }

  @override
  Map<String, dynamic> toJson() => {'type': type, 'message': message};
}
