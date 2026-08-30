import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/splash/splash_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';

/// Localized encouragement for `GoalSplashState.phraseIndex`.
String splashPhrase(AppLocalizations l, int index) {
  final phrases = <String Function(AppLocalizations)>[
    (l) => l.splash_phrase_01,
    (l) => l.splash_phrase_02,
    (l) => l.splash_phrase_03,
    (l) => l.splash_phrase_04,
    (l) => l.splash_phrase_05,
    (l) => l.splash_phrase_06,
    (l) => l.splash_phrase_07,
    (l) => l.splash_phrase_08,
    (l) => l.splash_phrase_09,
    (l) => l.splash_phrase_10,
    (l) => l.splash_phrase_11,
    (l) => l.splash_phrase_12,
    (l) => l.splash_phrase_13,
    (l) => l.splash_phrase_14,
    (l) => l.splash_phrase_15,
    (l) => l.splash_phrase_16,
    (l) => l.splash_phrase_17,
    (l) => l.splash_phrase_18,
    (l) => l.splash_phrase_19,
    (l) => l.splash_phrase_20,
    (l) => l.splash_phrase_21,
    (l) => l.splash_phrase_22,
    (l) => l.splash_phrase_23,
    (l) => l.splash_phrase_24,
    (l) => l.splash_phrase_25,
  ];
  assert(phrases.length == SplashService.phraseCount);
  return phrases[index % phrases.length](l);
}

class GoalSplashOverlay extends ConsumerWidget {
  const GoalSplashOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final splash = ref.watch(splashStateProvider);
    if (splash == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(splashServiceProvider).hide(),
      child: AnimatedOpacity(
        opacity: 1,
        duration: const Duration(milliseconds: 250),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: 0.6)),
            ),
            Center(
              child: Container(
                width: 600,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 24,
                ),
                margin: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 24,
                      spreadRadius: 4,
                      offset: const Offset(0, 12),
                      color: Colors.black.withValues(alpha: 0.4),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Lottie.asset(
                      'assets/images/Confetti.json',
                      fit: BoxFit.cover,
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.emoji_events, size: 64),
                        const SizedBox(height: 16),
                        Text(
                          l.splash_title,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          splash.goalTitle,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20.0),
                          child: Text(
                            splash.description,
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Text(
                          splashPhrase(l, splash.phraseIndex),
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
