import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class GoalSplashState {
  final String title;
  final String goalTitle;
  final String description;
  final String message;

  const GoalSplashState({
    required this.title,
    required this.goalTitle,
    required this.description,
    required this.message,
  });
}

class SplashService {
  SplashService({void Function(GoalSplashState?)? onStateChanged})
      : _onStateChanged = onStateChanged;

  final void Function(GoalSplashState?)? _onStateChanged;
  GoalSplashState? _current;

  final _random = Random();

  /// Call this from TutorService when a goal is reached.
  void showGoalReached({
    required String goalTitle,
    required String description,
    Duration duration = const Duration(seconds: 10),
  }) {
    final splash = GoalSplashState(
      title: 'Goal reached!',
      goalTitle: goalTitle,
      description: description,
      message: randomPhrase(),
    );
    _current = splash;
    _onStateChanged?.call(splash);

    Future.delayed(duration, () {
      if (_current?.goalTitle == goalTitle) {
        _current = null;
        _onStateChanged?.call(null);
      }
    });
  }

  void hide() {
    _current = null;
    _onStateChanged?.call(null);
  }

  /// 25 hilariously over-the-top Dutch encouragements
  static const List<String> _phrases = [
    "LEGENDARISCH! Je code zal eeuwenlang worden bezongen!",
    "Wauw! Zelfs je toetsenbord klapt voor je!",
    "Kijk uit, de AI wordt jaloers op je!",
    "Je hebt zojuist de informaticagod ontroerd.",
    "BAM! Nog één overwinning voor de Hall of Fame!",
    "Je toetsen maken rook — zo snel programmeer jij!",
    "Briljant! Zelfs Stack Overflow heeft geen woorden.",
    "De bugpolitiek heeft vandaag verloren!",
    "Wat een meesterwerk! Rembrandt, maar dan in Python.",
    "Je hebt net het internet verbeterd. Graag gedaan!",
    "Overheid belt: ze willen je algoritme aankopen.",
    "Applaus! De bits en bytes staan recht voor je!",
    "De compiler glimlacht. Dat gebeurt zelden.",
    "Je code is zo zuiver dat je er door kan kijken.",
    "De matrix heeft je opgemerkt… en knikt goedkeurend.",
    "De muis fluistert: 'ik ben niet waardig'.",
    "Zelfs je laptop wil nu een handtekening van je.",
    "Een nieuw record! De pixels juichen!",
    "Je hebt de grenzen van menselijk begrip overschreden.",
    "Wiskundigen huilen van ontroering.",
    "Python zelf fluistert: 'thank you, master'.",
    "Dit is geen succes meer. Dit is folklore.",
    "NASA belt: 'kun je bij ons komen debuggen?'",
    "De AI-tutor heeft besloten jou voortaan te tutoren.",
    "Stop! Je bent te goed. Geef de rest een kans.",
  ];

  String randomPhrase() => _phrases[_random.nextInt(_phrases.length)];
}

final splashStateProvider = StateProvider<GoalSplashState?>((_) => null);

final splashServiceProvider = Provider<SplashService>((ref) {
  return SplashService(
    onStateChanged: (s) => ref.read(splashStateProvider.notifier).state = s,
  );
});
