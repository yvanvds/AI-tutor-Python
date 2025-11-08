class OutputController {
  Future<void> Function(String code)? _run;
  Future<void> Function()? _stop;

  // Bound by Output when it can execute code
  void bind({
    required Future<void> Function(String code) run,
    required Future<void> Function() stop,
  }) {
    _run = run;
    _stop = stop;
  }

  // Called by the parent (Dashboard)
  Future<void> run(String code) async {
    final runner = _run;
    if (runner == null) {
      throw StateError('Output is not ready yet');
    }
    await runner(code);
  }

  Future<void> stop() async {
    final stopper = _stop;
    if (stopper == null) {
      throw StateError('Output is not ready yet');
    }
    await stopper();
  }
}
