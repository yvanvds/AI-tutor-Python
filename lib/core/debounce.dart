import 'dart:async';

// A simple debouncer that runs the given action after [delay] has passed
// since the last call to [run].
class Debouncer {
  Debouncer(this.delay);
  final Duration delay;
  Timer? _t;

  // Schedule [action] to run after [delay].
  void run(void Function() action) {
    _t?.cancel();
    _t = Timer(delay, action);
  }

  // Cancel any scheduled action.
  void dispose() => _t?.cancel();
}
