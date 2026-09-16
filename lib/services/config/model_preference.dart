// Which OpenAI model the tutor talks to (#32).
//
// Where the name lives: the school-wide default is `GlobalConfig.Model`, one
// Cosmos doc in the `config` container. What #32 adds is a *per-device
// override* in SharedPreferences, next to the user's own OpenAI key, because
// the one person who has a reason to pick a different model is the one paying
// for the calls. (#32 also had no choice: the app had no writer for the
// global doc at all. #118 added one — `GlobalConfigService.setModel` — but
// this override stayed, because "what my own key runs on" and "what the class
// runs on" are two different decisions.)
//
// Who may change it: the Options card is shown to accounts that bring their
// own key (`!mayUseGlobalKey`), to developer builds, and to teachers
// (`isTeacherProvider`, from the Entra role) whichever key they are on (#90).
// A student on the school's bundled key cannot move the whole class onto a
// pricier model from their own machine; they see no card and the global
// default applies. Moving the *class* is a second, teacher-only card in
// Options (`_GlobalModelCard`, #118) that writes the global doc; this one is
// still only ever about the machine it is set on.
//
// What it may be: any model id (#125). The Options card used to offer a
// curated list, which went stale within weeks of every release; it is now a
// free field whose Test button asks the model for a real chat completion
// before Save unlocks, so the app holds no list of model names at all. The
// one piece of model knowledge left is `OpenaiConnector._extraParams`, which
// adds `reasoning_effort` for the gpt-5 / o-series families.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
