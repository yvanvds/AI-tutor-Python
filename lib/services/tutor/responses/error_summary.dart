import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';

class ErrorResponse implements ChatResponse {
  final String type;
  final String message;

  ErrorResponse({required this.type, required this.message});

  factory ErrorResponse.fromMap(Map<String, dynamic> map) {
    return ErrorResponse(
      type: map['type'] ?? 'error',
      message: map['message'] ?? 'Unknown error occurred.',
    );
  }

  Map<String, dynamic> toJson() => {'type': type, 'message': message};
}
