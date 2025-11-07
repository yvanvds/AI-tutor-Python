import 'package:ai_tutor_python/services/output/output_controller.dart';

class OutputService {
  final OutputController _controller = OutputController();
  OutputController get controller => _controller;

  Future<void> run(String code) async {
    return _controller.run(code);
  }

  Future<void> stop() async {
    return _controller.stop();
  }
}
