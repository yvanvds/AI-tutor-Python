import 'package:hooks_riverpod/legacy.dart';

final codeProvider = StateProvider<String>((ref) {
  return '# Write your Python code here\n';
});
