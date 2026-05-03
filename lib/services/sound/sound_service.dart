import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SoundService {
  final AudioPlayer _player = AudioPlayer();

  Future<void> correctAnswer() async {
    await _playAsset('sounds/note.mp3', volume: 0.5);
  }

  Future<void> askQuestion() async {
    await _playAsset('sounds/question.mp3', volume: 0.5);
  }

  Future<void> playGoalReached() async {
    await _playAsset('sounds/goal_reached.mp3');
  }

  Future<void> guidingComplete() async {
    await _playAsset('sounds/chime.mp3');
  }

  Future<void> dispose() async {
    await _player.dispose();
  }

  Future<void> _playAsset(String path, {double volume = 1.0}) async {
    try {
      await _player.stop();
      await _player.setVolume(volume);
      await _player.play(AssetSource(path));
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Could not play asset sound: $e');
      }
    }
  }
}

final soundServiceProvider = Provider<SoundService>((ref) {
  final s = SoundService();
  ref.onDispose(() => unawaited(s.dispose()));
  return s;
});
