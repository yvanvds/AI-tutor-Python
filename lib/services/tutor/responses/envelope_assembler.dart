/// Incrementally parses the `<TEXT>...</TEXT><META>{...}</META>` envelope
/// the model emits. Built for streaming: feed [add] arbitrary chunks (which
/// may split a tag in half) and it returns the new student-visible text
/// fragment to display. After the stream ends, call [close] to flush; then
/// read [text] and [metaRaw].
///
/// If the model never emits the open tag, the assembler stays in [_State.preamble]
/// and [text] / [metaRaw] are both empty — callers should treat that as an
/// envelope-miss and fall back to legacy JSON parsing.
class EnvelopeAssembler {
  static const String _openText = '<TEXT>';
  static const String _closeText = '</TEXT>';
  static const String _openMeta = '<META>';
  static const String _closeMeta = '</META>';

  final StringBuffer _raw = StringBuffer();
  final StringBuffer _text = StringBuffer();
  final StringBuffer _meta = StringBuffer();
  int _pos = 0;
  _State _state = _State.preamble;

  /// Append [chunk] to the input. Returns the new TEXT fragment (may be
  /// empty if the chunk is still in the preamble or inside META).
  String add(String chunk) {
    _raw.write(chunk);
    return _drain();
  }

  /// Flush remaining buffered input. Call once when the upstream stream
  /// ends. Returns any final TEXT fragment that was held back as potential
  /// tag-prefix lookbehind.
  String close() {
    final delta = _drain();
    final s = _raw.toString();
    String tail = '';
    switch (_state) {
      case _State.inText:
        tail = s.substring(_pos);
        _text.write(tail);
        _state = _State.afterText;
        break;
      case _State.inMeta:
        _meta.write(s.substring(_pos));
        _state = _State.done;
        break;
      case _State.preamble:
      case _State.afterText:
      case _State.done:
        break;
    }
    _pos = s.length;
    return delta + tail;
  }

  String get text => _text.toString();
  String get metaRaw => _meta.toString();
  bool get sawOpenTag => _state != _State.preamble;
  bool get isDone => _state == _State.done;

  String _drain() {
    final s = _raw.toString();
    final delta = StringBuffer();

    while (_pos < s.length) {
      switch (_state) {
        case _State.preamble:
          {
            final idx = s.indexOf(_openText, _pos);
            if (idx == -1) {
              _pos = _safeStop(s.length, _openText.length);
              return delta.toString();
            }
            _pos = idx + _openText.length;
            if (_pos < s.length && s[_pos] == '\n') _pos++;
            _state = _State.inText;
            break;
          }
        case _State.inText:
          {
            final idx = s.indexOf(_closeText, _pos);
            if (idx == -1) {
              final stop = _safeStop(s.length, _closeText.length);
              if (stop > _pos) {
                final emit = s.substring(_pos, stop);
                _text.write(emit);
                delta.write(emit);
                _pos = stop;
              }
              return delta.toString();
            }
            var emit = s.substring(_pos, idx);
            if (emit.endsWith('\n')) {
              emit = emit.substring(0, emit.length - 1);
            }
            if (emit.isNotEmpty) {
              _text.write(emit);
              delta.write(emit);
            }
            _pos = idx + _closeText.length;
            _state = _State.afterText;
            break;
          }
        case _State.afterText:
          {
            final idx = s.indexOf(_openMeta, _pos);
            if (idx == -1) {
              _pos = _safeStop(s.length, _openMeta.length);
              return delta.toString();
            }
            _pos = idx + _openMeta.length;
            if (_pos < s.length && s[_pos] == '\n') _pos++;
            _state = _State.inMeta;
            break;
          }
        case _State.inMeta:
          {
            final idx = s.indexOf(_closeMeta, _pos);
            if (idx == -1) {
              final stop = _safeStop(s.length, _closeMeta.length);
              if (stop > _pos) {
                _meta.write(s.substring(_pos, stop));
                _pos = stop;
              }
              return delta.toString();
            }
            _meta.write(s.substring(_pos, idx));
            _pos = idx + _closeMeta.length;
            _state = _State.done;
            return delta.toString();
          }
        case _State.done:
          _pos = s.length;
          return delta.toString();
      }
    }
    return delta.toString();
  }

  /// Last safe position to advance to while leaving (tagLen-1) bytes of
  /// lookbehind, in case the next chunk completes a split tag.
  int _safeStop(int end, int tagLen) {
    final stop = end - (tagLen - 1);
    return stop > _pos ? stop : _pos;
  }
}

enum _State { preamble, inText, afterText, inMeta, done }
