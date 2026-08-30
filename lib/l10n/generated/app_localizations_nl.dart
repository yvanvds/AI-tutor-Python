// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Dutch Flemish (`nl`).
class AppLocalizationsNl extends AppLocalizations {
  AppLocalizationsNl([String locale = 'nl']) : super(locale);

  @override
  String get appTitle => 'Python Cursus';

  @override
  String get settings_menuTitle => 'Instellingen';

  @override
  String get settings_language_label => 'Taal';

  @override
  String get settings_language_system => 'Systeem';

  @override
  String get settings_language_english => 'English';

  @override
  String get settings_language_dutch => 'Nederlands';

  @override
  String get sidebar_settings_tooltip => 'Instellingen';

  @override
  String get sidebar_signOut_tooltip => 'Afmelden';

  @override
  String get sidebar_debug_tooltip => 'Debug';

  @override
  String get sidebar_teacherHeader => 'Docent';

  @override
  String get sidebar_section_session => 'Sessie';

  @override
  String get sidebar_section_map => 'Leerpad';

  @override
  String get sidebar_section_goals => 'Doelen';

  @override
  String get sidebar_section_lessonContent => 'Lesinhoud';

  @override
  String get sidebar_section_instructions => 'Instructies';

  @override
  String get sidebar_section_students => 'Studenten';

  @override
  String get session_mode_explain => 'Uitleg';

  @override
  String get session_mode_practice => 'Oefenen';

  @override
  String get session_mode_playground => 'Playground';

  @override
  String topBar_greeting(String name) {
    return 'Hoi $name,';
  }

  @override
  String get topBar_subline_default => 'aan de slag';

  @override
  String topBar_subline_withTopic(String topic) {
    return 'aan de slag met $topic';
  }

  @override
  String get topBar_streak_days => 'dagen';

  @override
  String topBar_xp_level(int level) {
    return 'Level $level';
  }

  @override
  String get auth_signIn_appBarTitle => 'Aanmelden';

  @override
  String get auth_signIn_prompt =>
      'Meld je aan met je school-Microsoft-account om verder te gaan.';

  @override
  String auth_signIn_errorPrefix(String error) {
    return 'Aanmelden mislukt: $error';
  }

  @override
  String get auth_signIn_button_idle => 'Aanmelden met schoolaccount';

  @override
  String get auth_signIn_button_busy => 'Bezig met aanmelden…';

  @override
  String get auth_localKey_appBarTitle => 'Geef je API-sleutel op';

  @override
  String get auth_localKey_explainer =>
      'Je account is nog niet goedgekeurd voor gebruik van de globale sleutel.\n\nJe kunt wachten tot je account is goedgekeurd, of je eigen OpenAI-API-sleutel opgeven om meteen verder te kunnen. Je sleutel wordt lokaal op dit toestel opgeslagen en alleen door deze app gebruikt.';

  @override
  String get auth_localKey_field_label => 'API-sleutel';

  @override
  String get auth_localKey_field_helper =>
      'We bewaren deze sleutel lokaal voor deze gebruiker op dit toestel.';

  @override
  String get auth_localKey_tooltip_showKey => 'Sleutel tonen';

  @override
  String get auth_localKey_tooltip_hideKey => 'Sleutel verbergen';

  @override
  String get auth_localKey_tooltip_paste => 'Plakken';

  @override
  String get auth_localKey_button_save => 'Sleutel opslaan';

  @override
  String get auth_localKey_validation_empty => 'Geef een API-sleutel op.';

  @override
  String get auth_localKey_saved => 'API-sleutel lokaal opgeslagen.';

  @override
  String auth_localKey_saveFailed(String error) {
    return 'Opslaan mislukt: $error';
  }

  @override
  String get auth_localKey_footnote =>
      'Opmerking: je kunt deze sleutel later wijzigen of verwijderen in Instellingen.';

  @override
  String get crash_title => 'Er ging iets mis';

  @override
  String get crash_defaultMessage =>
      'Dit kan gebeuren na wijzigingen aan rechten of regels.\nProbeer de app te resetten. Je wordt afgemeld en de caches worden gewist.';

  @override
  String get crash_resetButton => 'App resetten (rechten herstellen)';

  @override
  String get update_dialog_title => 'Update beschikbaar';

  @override
  String update_dialog_message(String version) {
    return 'Er is een nieuwere versie ($version) van de applicatie beschikbaar. De update wordt nu geïnstalleerd. Je kunt de app over enkele momenten opnieuw openen.';
  }

  @override
  String get update_dialog_ok => 'OK';

  @override
  String get session_explain_placeholder_noSubgoal =>
      'Kies een subdoel in Leerpad om de uitleg te bekijken.';

  @override
  String get session_explain_loading => 'Lesinhoud laden…';

  @override
  String get session_explain_missingContent =>
      'Nog geen lesinhoud beschikbaar voor dit subdoel.';

  @override
  String get session_explain_defaultPillLabel => 'Concept';

  @override
  String get session_explain_prev_button => 'Vorige';

  @override
  String get session_explain_completeXp => '+10 XP bij voltooien';

  @override
  String get session_explain_tryItYourself => 'Probeer het zelf';

  @override
  String get session_playground_pill => 'playground';

  @override
  String get session_playground_subtitle => 'Geen doel — alleen jij en Python.';

  @override
  String get session_quiz_pill => 'Quizvraag';

  @override
  String get session_quiz_next_button => 'Volgende →';

  @override
  String get session_output_state_idle => 'Geen output';

  @override
  String get session_output_state_running => 'Aan het uitvoeren…';

  @override
  String get session_output_state_ok => 'Klaar';

  @override
  String session_output_state_error_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fouten',
      one: '1 fout',
    );
    return '$_temp0';
  }

  @override
  String get session_output_header_label => 'Output';

  @override
  String get session_output_emptyState_runHint =>
      'Druk op Run om je code uit te voeren.';

  @override
  String get session_runControls_tooltip_resetOutput => 'Output resetten';

  @override
  String get session_runControls_tooltip_askHint => 'Vraag een hint';

  @override
  String get session_runControls_tooltip_sendToTutor => 'Stuur naar tutor';

  @override
  String get session_runControls_chatMessage_needHint =>
      'Ik heb een hint nodig.';

  @override
  String get session_runControls_chatMessage_hereIsCode => 'Hier is mijn code.';

  @override
  String get session_runControls_button_run => 'Run';

  @override
  String get session_runControls_button_stop => 'Stop';

  @override
  String get session_objectiveBanner_pill => 'Huidig doel';

  @override
  String get chat_tutorName => 'Tutor';

  @override
  String get chat_userName_you => 'Jij';

  @override
  String get chat_loading_thinking => 'Tutor denkt na…';

  @override
  String get chat_header_presence_online => 'online';

  @override
  String get chat_header_presence_helpsWith => ' · helpt je met ';

  @override
  String get chat_header_restart_tooltip => 'Sessie herstarten';

  @override
  String get chat_composer_idle_hint => 'Typ je vraag of antwoord…';

  @override
  String get chat_composer_idle_kbd_send => 'verstuur';

  @override
  String get chat_composer_idle_kbd_newline => 'nieuwe regel';

  @override
  String get chat_composer_idle_tip_prefix => 'tip: typ ';

  @override
  String get chat_composer_idle_tip_suffix => ' om een hint te vragen';

  @override
  String get chat_composer_idle_hintMessage => 'Ik heb een hint nodig';

  @override
  String get chat_composer_thinking_label => 'Tutor denkt na…';

  @override
  String get chat_composer_continue_prompt => 'Klaar voor het volgende stuk?';

  @override
  String get chat_composer_continue_button => 'Ga verder';

  @override
  String get chat_composer_mcqDisabled_label =>
      'Klik op een antwoord hierboven';

  @override
  String get goals_header_title => 'Doelen';

  @override
  String get goals_action_export => 'Doelen exporteren';

  @override
  String get goals_action_import => 'Doelen importeren';

  @override
  String get goals_snack_noGoalsToExport => 'Geen doelen om te exporteren';

  @override
  String goals_snack_exportedTo(String path) {
    return 'Geëxporteerd naar $path';
  }

  @override
  String goals_snack_exportFailed(String error) {
    return 'Exporteren mislukt: $error';
  }

  @override
  String get goals_snack_fileEmpty => 'Bestand bevatte geen doelen';

  @override
  String goals_snack_addAborted(int count, String sample) {
    return 'Toevoegen afgebroken: $count id(\'s) bestaan al (bv. $sample). Gebruik Vervangen of verwijder eerst de duplicaten.';
  }

  @override
  String goals_snack_imported(int count) {
    return '$count doel(en) geïmporteerd';
  }

  @override
  String goals_snack_importedWithRemoved(int count, int removed) {
    return '$count doel(en) geïmporteerd ($removed verwijderd die niet in het bestand stonden)';
  }

  @override
  String goals_snack_importFailed(String error) {
    return 'Importeren mislukt: $error';
  }

  @override
  String get goals_snack_couldNotRead =>
      'Kon het geselecteerde bestand niet lezen';

  @override
  String get goals_snack_invalidFile => 'Ongeldig doelenbestand';

  @override
  String get goals_import_dialog_title => 'Doelen importeren';

  @override
  String goals_import_dialog_message(int rootCount, int total) {
    return 'Het bestand bevat $rootCount hoofd­doel(en) en $total node(s) in totaal.\n\n• Toevoegen: voeg toe met de id\'s uit het bestand. Stopt als er een id al bestaat.\n• Vervangen: upsert per id (bestaande lesinhoud-koppelingen blijven) en verwijdert alle doelen die niet in het bestand staan.';
  }

  @override
  String get goals_import_action_cancel => 'Annuleer';

  @override
  String get goals_import_action_add => 'Toevoegen';

  @override
  String get goals_import_action_replace => 'Vervangen';

  @override
  String get goals_import_filePicker_title =>
      'Kies doelen-JSON om te importeren';

  @override
  String get goals_editor_title => 'Doel bewerken';

  @override
  String get goals_editor_tooltip_delete => 'Verwijderen';

  @override
  String get goals_editor_tooltip_close => 'Sluiten';

  @override
  String get goals_editor_field_title => 'Titel';

  @override
  String get goals_editor_untitled => 'Naamloos';

  @override
  String get goals_editor_field_description =>
      'Beschrijf dit doel voor de leerlingen.';

  @override
  String get goals_editor_switch_optional => 'Optioneel';

  @override
  String get goals_editor_switch_concept => 'Concept-doel';

  @override
  String get goals_editor_switch_concept_subtitle =>
      'Dit subdoel beheersen triggert de level-up-overlay.';

  @override
  String get goals_editor_teachingTips_label => 'Lestips';

  @override
  String get goals_editor_teachingTips_hint =>
      'Typ een lestip en druk op Enter';

  @override
  String get goals_editor_lesinhoud_label => 'Lesinhoud';

  @override
  String get goals_editor_lesinhoud_linked => 'Lesinhoud gekoppeld';

  @override
  String get goals_editor_lesinhoud_none => '(geen lesinhoud)';

  @override
  String get goals_editor_lesinhoud_edit => 'Bewerken';

  @override
  String get goals_editor_lesinhoud_create => 'Maken';

  @override
  String get goals_editor_delete_dialog_title => 'Doel verwijderen';

  @override
  String goals_editor_delete_dialog_message_single(String title) {
    return '\"$title\" verwijderen?';
  }

  @override
  String goals_editor_delete_dialog_message_withDescendants(
    String title,
    int count,
  ) {
    return '\"$title\" en zijn $count subdoel(en) verwijderen?';
  }

  @override
  String get goals_editor_delete_action_cancel => 'Annuleer';

  @override
  String get goals_editor_delete_action_confirm => 'Verwijderen';

  @override
  String goals_editor_deleted_single(String title) {
    return '\"$title\" verwijderd.';
  }

  @override
  String goals_editor_deleted_withDescendants(String title, int count) {
    return '\"$title\" verwijderd (+$count).';
  }

  @override
  String goals_pane_error(String error) {
    return 'Fout: $error';
  }

  @override
  String get goals_pane_noData => 'Geen gegevens';

  @override
  String goals_pane_reordered(String title) {
    return 'Volgorde van \"$title\" gewijzigd.';
  }

  @override
  String get goals_childPane_empty_pickRoot =>
      'Kies een hoofddoel om de subdoelen te zien.';

  @override
  String get goals_childPane_addHint => 'Subdoel toevoegen… (Enter)';

  @override
  String get goals_childPane_empty_addOne =>
      'Nog geen subdoelen. Voeg er hierboven een toe.';

  @override
  String get goals_rootPane_addHint => 'Hoofddoel toevoegen… (Enter)';

  @override
  String get goals_rootPane_empty_addOne =>
      'Nog geen doelen. Voeg er hierboven een toe.';

  @override
  String get goals_parentField_label => 'Bovenliggend doel';

  @override
  String get goals_parentField_noParent => '(geen bovenliggend doel)';

  @override
  String goals_parentField_loadFailed(String error) {
    return 'Bovenliggende doelen laden mislukt: $error';
  }

  @override
  String goals_editorPanel_loadError(String error) {
    return 'Documenten laden mislukt: $error';
  }

  @override
  String get goals_editorPanel_noGoalSelected => 'Geen doel geselecteerd.';

  @override
  String get lesson_toolbar_title => 'Lesinhoud';

  @override
  String get lesson_toolbar_upload => 'Upload .html';

  @override
  String get lesson_toolbar_save => 'Opslaan';

  @override
  String get lesson_toolbar_save_dirty => 'Opslaan *';

  @override
  String get lesson_snack_saved => 'Opgeslagen';

  @override
  String get lesson_snack_couldNotRead => 'Kon bestand niet lezen.';

  @override
  String lesson_loadError(String error) {
    return 'Fout bij laden: $error';
  }

  @override
  String get lesson_unlink_dialog_title => 'Lesinhoud loskoppelen?';

  @override
  String get lesson_unlink_dialog_message =>
      'Het content-document blijft bestaan, maar dit subdoel verwijst er niet meer naar.';

  @override
  String get lesson_unlink_dialog_cancel => 'Annuleren';

  @override
  String get lesson_unlink_dialog_confirm => 'Loskoppelen';

  @override
  String get lesson_editor_empty_pickSubgoal =>
      'Kies een subdoel om de lesinhoud te bewerken.';

  @override
  String get lesson_editor_field_title => 'Titel';

  @override
  String get lesson_editor_button_unlink => 'Loskoppelen';

  @override
  String get lesson_preview_empty =>
      'Voorbeeld verschijnt hier zodra je HTML toevoegt.';

  @override
  String get lesson_subgoal_noContent => '(geen lesinhoud)';

  @override
  String get lesson_default_moduleTitle => 'Python basics';

  @override
  String get lesson_orphans_header => 'Verweesde lesinhoud';

  @override
  String get lesson_orphans_hint =>
      'Aan geen enkel subdoel gekoppeld. Klik om opnieuw te koppelen.';

  @override
  String get lesson_reassign_dialog_title => 'Lesinhoud opnieuw koppelen';

  @override
  String lesson_reassign_dialog_message(String title) {
    return 'Kies het subdoel waar \"$title\" bij hoort.';
  }

  @override
  String get lesson_reassign_dialog_cancel => 'Annuleren';

  @override
  String get lesson_reassign_dialog_noSubgoals =>
      'Er zijn geen subdoelen om aan te koppelen.';

  @override
  String get lesson_reassign_overwrite_title =>
      'Bestaande lesinhoud vervangen?';

  @override
  String lesson_reassign_overwrite_message(String target, String title) {
    return '\"$target\" heeft al lesinhoud. Die wordt vervangen door \"$title\".';
  }

  @override
  String get lesson_reassign_overwrite_cancel => 'Annuleren';

  @override
  String get lesson_reassign_overwrite_confirm => 'Vervangen';

  @override
  String lesson_snack_reassigned(String target) {
    return 'Lesinhoud gekoppeld aan \"$target\".';
  }

  @override
  String get instructions_toolbar_title => 'Instructies';

  @override
  String get instructions_toolbar_tooltip_new => 'Nieuw document';

  @override
  String get instructions_toolbar_tooltip_delete => 'Document verwijderen';

  @override
  String get instructions_toolbar_tooltip_export =>
      'Alles exporteren naar Markdown';

  @override
  String get instructions_toolbar_tooltip_import => 'Importeren uit Markdown';

  @override
  String get instructions_toolbar_save => 'Opslaan';

  @override
  String get instructions_toolbar_save_dirty => 'Opslaan *';

  @override
  String get instructions_dialog_common_cancel => 'Annuleer';

  @override
  String get instructions_dialog_common_ok => 'OK';

  @override
  String get instructions_dialog_common_delete => 'Verwijderen';

  @override
  String get instructions_dialog_common_add => 'Toevoegen';

  @override
  String get instructions_dialog_common_replace => 'Vervangen';

  @override
  String get instructions_dialog_newDoc_title => 'Nieuw document';

  @override
  String get instructions_dialog_newDoc_label =>
      'Document-id (bv. system_prompt)';

  @override
  String get instructions_dialog_renameDoc_title => 'Document hernoemen';

  @override
  String get instructions_dialog_renameDoc_label => 'Nieuwe document-id';

  @override
  String get instructions_dialog_renameSection_title => 'Sectie hernoemen';

  @override
  String get instructions_dialog_renameSection_label => 'Nieuwe sectie-sleutel';

  @override
  String get instructions_dialog_addSection_title => 'Sectie toevoegen';

  @override
  String get instructions_dialog_addSection_label =>
      'Sectie-sleutel (bv. current_context)';

  @override
  String instructions_confirm_deleteDoc_title(String id) {
    return '\"$id\" verwijderen?';
  }

  @override
  String get instructions_confirm_deleteDoc_body =>
      'Dit verwijdert het document definitief.';

  @override
  String instructions_confirm_deleteSection_title(String key) {
    return '\"$key\" verwijderen?';
  }

  @override
  String get instructions_confirm_deleteSection_body =>
      'Dit verwijdert de sectie uit het document.';

  @override
  String get instructions_import_dialog_title => 'Instructies importeren';

  @override
  String instructions_import_dialog_message(int docCount) {
    return 'Het bestand bevat $docCount document(en).\n\n• Toevoegen: voegt alleen secties toe die nog niet bestaan; bestaande waarden blijven.\n• Vervangen: overschrijft secties van elk geïmporteerd document met de inhoud uit het bestand. Documenten die niet in het bestand staan, blijven ongewijzigd.';
  }

  @override
  String get instructions_filePicker_title =>
      'Kies Markdown-bestand om te importeren';

  @override
  String get instructions_snack_documentDeleted => 'Document verwijderd';

  @override
  String get instructions_snack_saved => 'Opgeslagen';

  @override
  String instructions_snack_sectionExists(String key) {
    return 'Sectie \"$key\" bestaat al';
  }

  @override
  String instructions_snack_sectionExistsRename(String key) {
    return 'Er bestaat al een sectie met de naam \"$key\"';
  }

  @override
  String instructions_snack_renamed(String target) {
    return 'Hernoemd naar \"$target\"';
  }

  @override
  String get instructions_snack_noDocsToExport =>
      'Geen documenten om te exporteren';

  @override
  String instructions_snack_exportedTo(String path) {
    return 'Geëxporteerd naar $path';
  }

  @override
  String instructions_snack_exportFailed(String error) {
    return 'Exporteren mislukt: $error';
  }

  @override
  String get instructions_snack_noDocsInFile =>
      'Geen documenten gevonden in het bestand';

  @override
  String instructions_snack_importFailed(String error) {
    return 'Importeren mislukt: $error';
  }

  @override
  String get instructions_snack_couldNotRead =>
      'Kon het geselecteerde bestand niet lezen';

  @override
  String get instructions_snack_replace_nothing =>
      'Niets gewijzigd (bestand kwam overeen met bestaande inhoud)';

  @override
  String get instructions_snack_add_nothing =>
      'Niets geïmporteerd (alle secties bestonden al)';

  @override
  String instructions_snack_imported_prefix(int count) {
    return '$count sectie(s) geïmporteerd';
  }

  @override
  String instructions_snack_stats_newDocs(int count) {
    return '$count nieuwe document(en)';
  }

  @override
  String instructions_snack_stats_updated(int count) {
    return '$count bijgewerkt';
  }

  @override
  String instructions_snack_stats_replaced(int count) {
    return '$count vervangen';
  }

  @override
  String instructions_snack_stats_addedSections(int count) {
    return '$count toegevoegde sectie(s)';
  }

  @override
  String instructions_snack_stats_replacedSections(int count) {
    return '$count vervangen sectie(s)';
  }

  @override
  String instructions_body_loadError(String error) {
    return 'Documenten laden mislukt: $error';
  }

  @override
  String get instructions_sectionsList_add => 'Sectie toevoegen';

  @override
  String get instructions_sectionsList_delete => 'Verwijderen';

  @override
  String get instructions_docList_header => 'Documenten';

  @override
  String get instructions_docHeader_noDoc => 'Geen document geselecteerd';

  @override
  String get instructions_docHeader_renameTooltip => 'Document hernoemen';

  @override
  String get instructions_sectionHeader_noSection => 'Geen sectie geselecteerd';

  @override
  String get instructions_sectionHeader_renameTooltip => 'Sectie hernoemen';

  @override
  String get accounts_page_title => 'Studenten';

  @override
  String get accounts_page_subtitle =>
      'Beheer accounts en volg de voortgang van je studenten.';

  @override
  String accounts_loadError(String error) {
    return 'Accounts laden mislukt:\n$error';
  }

  @override
  String get accounts_search_hint => 'Zoek op naam of e-mail…';

  @override
  String accounts_pageSize_label(int n) {
    return '$n per pagina';
  }

  @override
  String get accounts_column_email => 'E-MAIL';

  @override
  String get accounts_column_name => 'NAAM';

  @override
  String get accounts_column_streak => 'STREAK';

  @override
  String get accounts_column_currentGoal => 'HUIDIG DOEL';

  @override
  String get accounts_column_progress => 'VOORTGANG';

  @override
  String get accounts_column_status => 'STATUS';

  @override
  String get accounts_column_key => 'SLEUTEL';

  @override
  String get accounts_column_actions => 'ACTIES';

  @override
  String accounts_email_lastActive(String ts) {
    return 'laatst actief: $ts';
  }

  @override
  String get accounts_tooltip_deleteAccount => 'Account verwijderen';

  @override
  String get accounts_tooltip_firstPage => 'Eerste pagina';

  @override
  String get accounts_tooltip_previousPage => 'Vorige pagina';

  @override
  String get accounts_tooltip_nextPage => 'Volgende pagina';

  @override
  String get accounts_tooltip_lastPage => 'Laatste pagina';

  @override
  String accounts_pagination_showing(int start, int end, int total) {
    return '$start–$end van $total weergegeven';
  }

  @override
  String accounts_pagination_pageOf(int page, int total) {
    return 'Pagina $page / $total';
  }

  @override
  String get accounts_delete_dialog_title => 'Account verwijderen';

  @override
  String accounts_delete_dialog_message(String email) {
    return 'Dit verwijdert het accountprofiel voor:\n\n$email\n\nDit verwijdert de gebruiker NIET uit de schoolaccount-directory. Doorgaan?';
  }

  @override
  String get accounts_delete_dialog_cancel => 'Annuleer';

  @override
  String get accounts_delete_dialog_confirm => 'Verwijderen';

  @override
  String accounts_delete_success(String email) {
    return 'Account verwijderd: $email';
  }

  @override
  String accounts_delete_failed(String error) {
    return 'Verwijderen mislukt: $error';
  }

  @override
  String get accounts_status_tooltip_active => 'Recent vooruitgang geboekt.';

  @override
  String get accounts_status_tooltip_idle =>
      'Geen vooruitgang in de laatste 7 dagen.';

  @override
  String get accounts_badge_unackTooltip => 'Onbevestigde signaaleventjes';

  @override
  String get drawer_close_tooltip => 'Sluiten';

  @override
  String get drawer_section_goals => 'Doelen';

  @override
  String drawer_statusSummary_active_with_goal(String title) {
    return 'Recent actief op \"$title\".';
  }

  @override
  String get drawer_statusSummary_active_noGoal => 'Recent actief.';

  @override
  String get drawer_statusSummary_idle => 'Geen recente activiteit.';

  @override
  String get drawer_signals_title => 'Signaaleventjes';

  @override
  String get drawer_signals_button_busy => 'Bezig…';

  @override
  String drawer_signals_button_acknowledge(int count) {
    return 'Bevestigen ($count)';
  }

  @override
  String get drawer_signals_empty => 'Geen events';

  @override
  String drawer_signals_ackFailed(String error) {
    return 'Bevestigen faalde: $error';
  }

  @override
  String get drawer_signals_kind_stuckLoAdvance =>
      'Vastgelopen LO bij overgang';

  @override
  String get drawer_signals_kind_singleLoDeadlock => 'Single-LO impasse';

  @override
  String get drawer_signals_kind_repeatedDemotions => 'Herhaalde demotion';

  @override
  String get drawer_signals_kind_sustainedLlmFailure => 'Aanhoudende LLM-fout';

  @override
  String get drawer_signals_kind_cascadeHalt => 'Cascade-halt (audit)';

  @override
  String get drawer_signals_kind_emptyObjectivesBlock =>
      'Subdoel zonder LO\'s (audit)';

  @override
  String get drawer_signals_kind_subgoalDeletedRedirect =>
      'Subdoel verwijderd (audit)';

  @override
  String get drawer_statusReports_title => 'Statusrapporten';

  @override
  String get drawer_statusReports_loadError =>
      'Kon de statusrapporten niet laden.';

  @override
  String get drawer_statusReports_empty => 'Nog geen statusrapporten.';

  @override
  String get drawer_history_title => 'Voortgang in de tijd';

  @override
  String get drawer_history_loadError => 'Kon de geschiedenis niet laden.';

  @override
  String get drawer_history_empty => 'Nog geen geschiedenis.';

  @override
  String get drawer_history_card_empty => 'Nog geen geschiedenis';

  @override
  String get drawer_history_legend_average => 'gemiddelde';

  @override
  String get progress_loadError => 'Kon de doelen niet laden.';

  @override
  String get progress_empty => 'Er zijn nog geen doelen beschikbaar.';

  @override
  String get leerpad_header_title => 'Leerpad';

  @override
  String get leerpad_header_subtitle_default => 'Python — beginnersreis';

  @override
  String get leerpad_card_completed => 'voltooid';

  @override
  String get leerpad_card_button_continue => 'Verder';

  @override
  String get goalTile_button_faster => 'Ga sneller';

  @override
  String get goalTile_button_workOn => 'Werk hieraan';
}
