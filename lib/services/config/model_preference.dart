// Which OpenAI model the tutor talks to (#32).
//
// Where the name lives: the school-wide default stays where it always was —
// `GlobalConfig.Model`, one Cosmos doc the teacher maintains, read-only from
// inside the app. What #32 adds is a *per-device override* in
// SharedPreferences, next to the user's own OpenAI key. That direction was
// chosen because the app has no writer for the global config doc at all, and
// because the one person who has a reason to pick a different model is the
// one paying for the calls.
//
// Who may change it: the Options card is shown to accounts that bring their
// own key (`!mayUseGlobalKey`), to developer builds, and to teachers
// (`isTeacherProvider`, from the Entra role) whichever key they are on (#90).
// A student on the school's bundled key cannot move the whole class onto a
// pricier model from their own machine; they see no card and the global
// default applies. A teacher's pick is still this per-device override, not a
// write to the global doc.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Models offered in the Options panel, cheapest-first within each family.
///
/// A short curated list rather than a live catalogue: `/v1/models` returns
/// every embedding and audio model too, and the tutor only works with chat
/// completions. `OpenaiConnector` sends `reasoning_effort` to the gpt-5 and
/// o-series entries automatically.
const List<String> kSelectableModels = <String>[
  'gpt-4o-mini',
  'gpt-4o',
  'gpt-4.1-mini',
  'gpt-4.1',
  'gpt-5-mini',
  'gpt-5',
];

/// Per-device model override, or `null` to follow the school-wide default
/// from `GlobalConfig`.
class ModelPreference extends Notifier<String?> {
  static const String _prefsKey = 'openai_model';

  @override
  String? build() {
    _hydrate();
    return null;
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    state = raw;
  }

  /// Stores [model], or clears the override when it is `null`.
  Future<void> setModel(String? model) async {
    final prefs = await SharedPreferences.getInstance();
    if (model == null || model.isEmpty) {
      await prefs.remove(_prefsKey);
      state = null;
      return;
    }
    await prefs.setString(_prefsKey, model);
    state = model;
  }
}

final modelPreferenceProvider = NotifierProvider<ModelPreference, String?>(
  ModelPreference.new,
);
