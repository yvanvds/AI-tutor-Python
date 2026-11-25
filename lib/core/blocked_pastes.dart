/// The pastes from outside the app that were blocked (#334): how many, and
/// how many characters they held together. The text itself is never kept.
class BlockedPastes {
  const BlockedPastes({required this.count, required this.chars});

  static const BlockedPastes none = BlockedPastes(count: 0, chars: 0);

  final int count;
  final int chars;

  /// Read back from a `turn_history` doc: `null` — unknown — unless both
  /// fields are numbers. A doc without them was written by a build from
  /// before #334, or while the switch was off; never read that as 0.
  static BlockedPastes? tryFromDoc(Map<String, dynamic> doc) {
    final count = doc['blockedPastes'];
    final chars = doc['blockedPasteChars'];
    if (count is! num || chars is! num) return null;
    return BlockedPastes(count: count.toInt(), chars: chars.toInt());
  }

  @override
  bool operator ==(Object other) =>
      other is BlockedPastes && other.count == count && other.chars == chars;

  @override
  int get hashCode => Object.hash(count, chars);

  @override
  String toString() => 'BlockedPastes($count, $chars chars)';
}

/// The blocked pastes since the last turn record, as `UsageLedger` keeps the
/// tokens: `PasteGuard` notes each one, the tutor takes them onto the next
/// record it writes — the oefening they happened on — and starts again.
class BlockedPasteLedger {
  int _count = 0;
  int _chars = 0;

  /// What was noted since the last [take], without taking it.
  BlockedPastes get pending => BlockedPastes(count: _count, chars: _chars);

  /// A blocked paste of [chars] characters.
  void note(int chars) {
    _count++;
    _chars += chars;
  }

  /// What was noted since the last take, and a fresh start.
  BlockedPastes take() {
    final out = pending;
    clear();
    return out;
  }

  void clear() {
    _count = 0;
    _chars = 0;
  }
}
