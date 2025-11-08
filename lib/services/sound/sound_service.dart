import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class SoundService {
  Future<void> correctAnswer() async {
    await _playAsset('sounds/note.mp3', volume: 0.5);
  }

  Future<void> askQuestion() async {
    await _playAsset('sounds/question.mp3', volume: 0.5);
  }

  /// Plays the goal-reached sound
  Future<void> playGoalReached() async {
    await _playAsset('sounds/goal_reached.mp3');
  }

  Future<void> guidingComplete() async {
    await _playAsset('sounds/chime.mp3');
  }

  /// General-purpose method for later use
  Future<void> _playAsset(String path, {double volume = 1.0}) async {
    try {
      final player = AudioPlayer();
      await player.setVolume(volume);
      await player.play(AssetSource(path));
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Could not play asset sound: $e');
      }
    }
  }
}
