import 'package:flutter/material.dart';
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/splash/splash_service.dart';
import 'package:lottie/lottie.dart';

class GoalSplashOverlay extends StatelessWidget {
  const GoalSplashOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final splashService = DataService.splash;

    return ValueListenableBuilder<GoalSplashState?>(
      valueListenable: splashService.state,
      builder: (context, splash, _) {
        if (splash == null) return const SizedBox.shrink();

        return IgnorePointer(
          ignoring:
              true, // so user can’t accidentally interact behind if you prefer blocking set to false
          child: AnimatedOpacity(
            opacity: 1,
            duration: const Duration(milliseconds: 250),
            child: Stack(
              children: [
                // Dim background
                Positioned.fill(
                  child: Container(color: Colors.black.withOpacity(0.6)),
                ),
                // Center card
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
                          color: Colors.black.withOpacity(0.4),
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
                              splash.title,
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
                              padding: const EdgeInsets.symmetric(
                                vertical: 20.0,
                              ),
                              child: Text(
                                splash.description,
                                style: Theme.of(context).textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Text(
                              splash.message,
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
      },
    );
  }
}
