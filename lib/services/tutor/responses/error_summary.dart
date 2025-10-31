class ErrorResponse {
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
