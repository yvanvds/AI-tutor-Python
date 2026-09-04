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
  String get settings_language_label => 'Taal';

  @override
  String get settings_language_system => 'Systeem';

  @override
  String get settings_language_english => 'English';

  @override
  String get settings_language_dutch => 'Nederlands';

  @override
  String get sidebar_signOut_tooltip => 'Afmelden';

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
  String get sidebar_section_milestones => 'Mijlpalen';

  @override
  String get sidebar_section_options => 'Opties';

  @override
  String get milestones_page_title => 'Mijlpalen';

  @override
  String get milestones_page_subtitle =>
      'Welke doelen tegen welk rapportmoment gekend horen te zijn, en welke daarvan de 50 openen.';

  @override
  String get milestones_list_empty => 'Nog geen mijlpalen.';

  @override
  String get milestones_button_new => 'Nieuwe mijlpaal';

  @override
  String get milestones_button_save => 'Opslaan';

  @override
  String get milestones_button_delete => 'Verwijderen';

  @override
  String get milestones_placeholder =>
      'Kies links een mijlpaal, of maak een nieuwe.';

  @override
  String get milestones_field_title => 'Titel';

  @override
  String get milestones_field_periodStart =>
      'Start van de periode (JJJJ-MM-DD)';

  @override
  String get milestones_field_dueAt => 'Rapportdatum (JJJJ-MM-DD)';

  @override
  String get milestones_field_pickDate => 'Kies een datum';

  @override
  String get milestones_field_expectedDifficulty =>
      'Verwacht niveau voor de kern';

  @override
  String get milestones_difficulty_easy => 'makkelijk';

  @override
  String get milestones_difficulty_medium => 'gemiddeld';

  @override
  String get milestones_difficulty_hard => 'moeilijk';

  @override
  String get milestones_goals_heading => 'Doelen in deze mijlpaal';

  @override
  String get milestones_goals_hint =>
      'Vink een subdoel aan om zijn leerdoelen op te nemen. Duid dan per leerdoel aan of een nét geslaagde leerling het beheerst (kern) of niet (uitbreiding).';

  @override
  String get milestones_lo_core => 'kern';

  @override
  String get milestones_lo_extension => 'uitbreiding';

  @override
  String get milestones_validation_title => 'Geef de mijlpaal een titel.';

  @override
  String get milestones_validation_date => 'Gebruik de vorm JJJJ-MM-DD.';

  @override
  String get milestones_validation_order =>
      'De rapportdatum moet na de start van de periode liggen.';

  @override
  String get milestones_validation_goals => 'Neem minstens één subdoel op.';

  @override
  String get milestones_saved => 'Mijlpaal opgeslagen.';

  @override
  String get milestones_deleted => 'Mijlpaal verwijderd.';

  @override
  String get milestones_delete_dialog_title => 'Mijlpaal verwijderen';

  @override
  String milestones_delete_dialog_message(String title) {
    return '\"$title\" verwijderen? Puntvoorstellen die er al tegen berekend zijn, blijven staan.';
  }

  @override
  String get milestones_delete_dialog_cancel => 'Annuleren';

  @override
  String get milestones_delete_dialog_confirm => 'Verwijderen';

  @override
  String milestones_summary(int core, int extension) {
    return '$core kern-, $extension uitbreidingsleerdoelen';
  }

  @override
  String get drawer_grade_title => 'Puntvoorstel';

  @override
  String get drawer_grade_noMilestones =>
      'Nog geen mijlpalen — maak er een onder Mijlpalen.';

  @override
  String get drawer_grade_milestone_label => 'Mijlpaal';

  @override
  String get drawer_grade_button_compute => 'Voorstel berekenen';

  @override
  String get drawer_grade_button_recompute => 'Opnieuw berekenen';

  @override
  String get drawer_grade_button_justify => 'Verantwoording schrijven';

  @override
  String get drawer_grade_button_signOff => 'Aftekenen';

  @override
  String get drawer_grade_button_busy => 'Bezig…';

  @override
  String get drawer_grade_proposal_label => 'Voorstel';

  @override
  String drawer_grade_masteryEnd(String value) {
    return 'Beheersing nu: $value';
  }

  @override
  String drawer_grade_masteryStart(String value) {
    return 'Beheersing bij start periode: $value';
  }

  @override
  String get drawer_grade_startSource_snapshot =>
      'Start periode: exacte momentopname per leerdoel';

  @override
  String drawer_grade_startSource_snapshotLate(int count) {
    return 'Start periode: momentopname per leerdoel, $count leerdoelen al geschreven toen ze genomen werd';
  }

  @override
  String get drawer_grade_startSource_history =>
      'Start periode: schatting uit de voortgangshistoriek (geen momentopname voor deze periode)';

  @override
  String drawer_grade_growth(String value) {
    return 'Groei: $value';
  }

  @override
  String drawer_grade_core(int counted, int total) {
    return 'Kern op niveau: $counted / $total';
  }

  @override
  String drawer_grade_extension(int counted, int total) {
    return 'Uitbreiding beheerst: $counted / $total';
  }

  @override
  String drawer_grade_hard(int counted, int total) {
    return 'Aangetoond op moeilijk: $counted / $total beheerst';
  }

  @override
  String drawer_grade_reliability(
    int stale,
    int never,
    int supervised,
    int home,
  ) {
    return 'Verouderd: $stale leerdoelen (nooit bevraagd: $never). Beurten deze periode: $supervised onder toezicht, $home thuis.';
  }

  @override
  String drawer_grade_formulaVersion(String version, String ts) {
    return 'Formule v$version, berekend $ts';
  }

  @override
  String get drawer_grade_justification_title => 'Verantwoording';

  @override
  String drawer_grade_justification_failed(String error) {
    return 'De verantwoording kon niet geschreven worden: $error';
  }

  @override
  String get drawer_grade_adjusted_label => 'Punt voor het rapport';

  @override
  String get drawer_grade_adjusted_invalid =>
      'Geef een geheel getal van 0 tot 100.';

  @override
  String get drawer_grade_note_label => 'Reden voor aanpassing (optioneel)';

  @override
  String drawer_grade_signed(String ts, int grade) {
    return 'Afgetekend $ts: $grade/100';
  }

  @override
  String drawer_grade_signed_note(String note) {
    return 'Opmerking: $note';
  }

  @override
  String drawer_grade_failed(String error) {
    return 'Het voorstel kon niet berekend worden: $error';
  }

  @override
  String get options_page_title => 'Opties';

  @override
  String get options_page_subtitle =>
      'Instellingen, onderhoud en bugmeldingen.';

  @override
  String get options_language_title => 'Taal';

  @override
  String get options_language_subtitle =>
      'Wordt meteen toegepast; \"Systeem\" volgt het besturingssysteem.';

  @override
  String get options_theme_title => 'Weergave';

  @override
  String get options_theme_subtitle =>
      'Licht of donker, opgeslagen op dit toestel. \"Systeem\" volgt het besturingssysteem.';

  @override
  String get options_theme_system => 'Systeem volgen';

  @override
  String get options_theme_light => 'Licht';

  @override
  String get options_theme_dark => 'Donker';

  @override
  String get options_model_title => 'AI-model';

  @override
  String get options_model_subtitle =>
      'Welk OpenAI-model de tutor bevraagt. Geldt alleen voor dit toestel; een groter model is trager en duurder.';

  @override
  String options_model_followGlobal(String model) {
    return 'Standaard van de school ($model)';
  }

  @override
  String get options_progress_title => 'Voortgang';

  @override
  String get options_progress_subtitle =>
      'Voortgang wissen wist ook wat de tutor over je kennis weet. Dit kan niet ongedaan gemaakt worden.';

  @override
  String get options_progress_resetAll_button => 'Alle voortgang wissen';

  @override
  String get options_progress_resetAll_dialog_title => 'Alle voortgang wissen?';

  @override
  String get options_progress_resetAll_dialog_message =>
      'Dit verwijdert alle voortgang, leergeschiedenis en tutorinschattingen van je account en zet de moeilijkheidsgraad terug op gemiddeld. Dit kan niet ongedaan gemaakt worden.';

  @override
  String get options_progress_resetAll_dialog_confirm => 'Alles wissen';

  @override
  String get options_progress_resetAll_done => 'Alle voortgang is gewist.';

  @override
  String get options_progress_resetGoal_button => 'Eén doel wissen…';

  @override
  String get options_progress_resetGoal_dialog_title =>
      'Voortgang van een doel wissen';

  @override
  String get options_progress_resetGoal_dialog_message =>
      'Kies een doel of subdoel. Een doel wissen wist al zijn subdoelen.';

  @override
  String get options_progress_resetGoal_dialog_empty =>
      'Er zijn nog geen doelen.';

  @override
  String options_progress_resetGoal_dialog_loadError(String error) {
    return 'Doelen laden mislukt: $error';
  }

  @override
  String options_progress_resetGoal_confirm_title(String title) {
    return '\"$title\" wissen?';
  }

  @override
  String get options_progress_resetGoal_confirm_message_subgoal =>
      'Voortgang, leergeschiedenis en tutorinschattingen voor dit subdoel worden verwijderd. Dit kan niet ongedaan gemaakt worden.';

  @override
  String get options_progress_resetGoal_confirm_message_root =>
      'Voortgang, leergeschiedenis en tutorinschattingen voor elk subdoel van dit doel worden verwijderd. Dit kan niet ongedaan gemaakt worden.';

  @override
  String get options_progress_resetGoal_confirm_button => 'Wissen';

  @override
  String options_progress_resetGoal_done(String title) {
    return 'Voortgang van \"$title\" is gewist.';
  }

  @override
  String options_progress_resetFailed(String error) {
    return 'Wissen mislukt: $error';
  }

  @override
  String get options_dialog_cancel => 'Annuleren';

  @override
  String get options_transfer_title => 'Voortgang exporteren / importeren';

  @override
  String get options_transfer_subtitle =>
      'Bewaar je leergeschiedenis in een bestand, of laad ze in dit account — handig als je naar een ander account overstapt.';

  @override
  String get options_transfer_export_button => 'Voortgang exporteren…';

  @override
  String get options_transfer_import_button => 'Voortgang importeren…';

  @override
  String options_transfer_exported(String path) {
    return 'Voortgang opgeslagen in $path';
  }

  @override
  String options_transfer_exportFailed(String error) {
    return 'Exporteren mislukt: $error';
  }

  @override
  String get options_transfer_import_dialog_title => 'Je voortgang vervangen?';

  @override
  String options_transfer_import_dialog_message(String file) {
    return '\"$file\" importeren verwijdert de voortgang, leergeschiedenis en tutorinschattingen die dit account nu heeft en vervangt ze door de inhoud van het bestand. Dit kan niet ongedaan gemaakt worden.';
  }

  @override
  String get options_transfer_import_dialog_confirm =>
      'Importeren en vervangen';

  @override
  String options_transfer_imported(int goals, int samples, int beliefs) {
    return '$goals doelen, $samples geschiedenisitems en $beliefs kennisinschattingen geïmporteerd.';
  }

  @override
  String options_transfer_importFailed(String error) {
    return 'Importeren mislukt: $error';
  }

  @override
  String get options_apiKey_title => 'OpenAI API-sleutel';

  @override
  String get options_apiKey_subtitle =>
      'Je eigen sleutel, opgeslagen op dit toestel. Als je ze verwijdert, kom je terug op het sleutelscherm.';

  @override
  String get options_apiKey_status_present =>
      'Er is een sleutel opgeslagen op dit toestel.';

  @override
  String get options_apiKey_status_missing =>
      'Geen sleutel opgeslagen op dit toestel.';

  @override
  String get options_apiKey_change_button => 'Sleutel wijzigen';

  @override
  String get options_apiKey_remove_button => 'Sleutel verwijderen';

  @override
  String get options_apiKey_dialog_title => 'API-sleutel wijzigen';

  @override
  String get options_apiKey_dialog_field => 'Nieuwe API-sleutel';

  @override
  String get options_apiKey_dialog_save => 'Opslaan';

  @override
  String get options_apiKey_saved => 'API-sleutel bijgewerkt.';

  @override
  String get options_apiKey_remove_dialog_title => 'API-sleutel verwijderen?';

  @override
  String get options_apiKey_remove_dialog_message =>
      'Zonder sleutel kan de tutor niet antwoorden. Je wordt meteen om een nieuwe sleutel gevraagd.';

  @override
  String get options_apiKey_remove_dialog_confirm => 'Verwijderen';

  @override
  String get options_apiKey_removed => 'API-sleutel verwijderd.';

  @override
  String get options_bugReport_title => 'Bugmeldingen';

  @override
  String get options_bugReport_subtitle =>
      'Maak rechtstreeks vanuit de app een issue aan op GitHub, met de debuggegevens van een recente tutorbeurt erbij.';

  @override
  String get options_bugReport_github_notConnected =>
      'Niet verbonden met GitHub.';

  @override
  String options_bugReport_github_connectedAs(String login) {
    return 'Verbonden met GitHub als $login.';
  }

  @override
  String get options_bugReport_github_connect_button => 'GitHub verbinden';

  @override
  String get options_bugReport_github_disconnect_button =>
      'Verbinding verbreken';

  @override
  String get options_bugReport_github_notConfigured =>
      'Deze build kan niet aanmelden bij GitHub: ze is gebouwd zonder GitHub OAuth-client-id, dus bugmeldingen kunnen enkel met de hand op github.com.';

  @override
  String options_bugReport_github_device_explainer(String repo) {
    return 'Typ deze code op GitHub zodat de app issues mag aanmaken op $repo. Er wordt niets bewaard tot je het goedkeurt.';
  }

  @override
  String options_bugReport_github_device_instruction(String url) {
    return 'Geef de code in op $url';
  }

  @override
  String get options_bugReport_github_device_waiting =>
      'Wachten tot je het goedkeurt op GitHub…';

  @override
  String get options_bugReport_github_device_openBrowser => 'GitHub openen';

  @override
  String get options_bugReport_github_device_copyCode => 'Code kopiëren';

  @override
  String get options_bugReport_github_device_codeCopied =>
      'Code naar het klembord gekopieerd.';

  @override
  String get options_bugReport_github_device_cancel => 'Annuleren';

  @override
  String options_bugReport_github_device_browserFailed(String url) {
    return 'Kon geen browser openen. Ga zelf naar $url.';
  }

  @override
  String get options_bugReport_github_device_expired =>
      'De code verliep voor ze werd goedgekeurd. Probeer opnieuw.';

  @override
  String get options_bugReport_github_device_denied =>
      'De aanvraag werd geweigerd op GitHub, er is niets verbonden.';

  @override
  String options_bugReport_github_connectFailed(String error) {
    return 'Verbinden mislukt: $error';
  }

  @override
  String get options_bugReport_report_button => 'Bug melden…';

  @override
  String get options_bugReport_dialog_title => 'Bug melden';

  @override
  String get options_bugReport_dialog_titleField => 'Titel';

  @override
  String get options_bugReport_dialog_titleRequired => 'Geef een titel op.';

  @override
  String get options_bugReport_dialog_descriptionField => 'Wat ging er mis?';

  @override
  String get options_bugReport_dialog_turnField => 'Tutorbeurt bijvoegen';

  @override
  String get options_bugReport_dialog_turnNone => 'Geen beurt';

  @override
  String options_bugReport_dialog_turnLabel(int id, String type) {
    return '#$id $type';
  }

  @override
  String get options_bugReport_dialog_submit => 'Issue plaatsen';

  @override
  String options_bugReport_posted(String url) {
    return 'Issue geplaatst: $url';
  }

  @override
  String options_bugReport_postFailed(String error) {
    return 'Plaatsen mislukt: $error';
  }

  @override
  String get options_developer_title => 'Ontwikkelaarstools';

  @override
  String get options_developer_subtitle =>
      'Enkel zichtbaar in ontwikkelaarsbuilds.';

  @override
  String get options_developer_levelUp_button => 'Level-up-overlay tonen';

  @override
  String get options_developer_triggerQuestion_title => 'Vraag starten';

  @override
  String get options_developer_difficulty_label => 'Moeilijkheid:';

  @override
  String get options_developer_recentTurns_title => 'Recente beurten';

  @override
  String get options_developer_recentTurns_copyAll => 'Alles kopiëren';

  @override
  String options_developer_recentTurns_copied(int count) {
    return '$count beurten naar het klembord gekopieerd.';
  }

  @override
  String get options_developer_recentTurns_empty =>
      'Nog geen beurten opgenomen.';

  @override
  String options_developer_turnDetail_title(int id) {
    return 'Beurt #$id';
  }

  @override
  String get options_developer_turnDetail_close => 'Sluiten';

  @override
  String get options_about_title => 'Over';

  @override
  String options_about_version(String version) {
    return 'Versie $version';
  }

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
  String get update_status_idle => 'Er is nog niet gecontroleerd op updates.';

  @override
  String get update_status_checking => 'Er wordt gecontroleerd op updates…';

  @override
  String get update_status_upToDate => 'Je hebt de nieuwste versie.';

  @override
  String update_status_available(String version) {
    return 'Versie $version is beschikbaar.';
  }

  @override
  String update_status_downloading(String version) {
    return 'Versie $version wordt gedownload…';
  }

  @override
  String update_status_applying(String version) {
    return 'Het installatieprogramma start. De app sluit zichzelf en komt terug als versie $version.';
  }

  @override
  String update_status_failed(String reason) {
    return 'De update is niet gelukt: $reason';
  }

  @override
  String get update_action_apply => 'Bijwerken';

  @override
  String update_action_applyVersion(String version) {
    return 'Bijwerken naar $version';
  }

  @override
  String get update_action_later => 'Later';

  @override
  String get update_action_check => 'Controleren op updates';

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
  String get session_explain_next_button => 'Volgende';

  @override
  String get session_explain_completeXp => '+10 XP bij voltooien';

  @override
  String get session_explain_tryItYourself => 'Probeer het zelf';

  @override
  String get session_playground_pill => 'playground';

  @override
  String get session_playground_subtitle => 'Geen doel — alleen jij en Python.';

  @override
  String get session_playground_open_button => 'Openen';

  @override
  String get session_playground_open_tooltip => 'Opgeslagen code openen';

  @override
  String get session_playground_save_button => 'Opslaan';

  @override
  String get session_playground_save_tooltip => 'Deze code opslaan';

  @override
  String get session_playground_dialog_cancel => 'Annuleren';

  @override
  String get session_playground_saveDialog_title => 'Code opslaan';

  @override
  String get session_playground_saveDialog_nameLabel => 'Bestandsnaam';

  @override
  String get session_playground_saveDialog_invalidName =>
      'Gebruik letters, cijfers, spaties, - of _ (max. 60 tekens).';

  @override
  String get session_playground_saveDialog_confirm => 'Opslaan';

  @override
  String session_playground_overwriteDialog_title(String name) {
    return '\"$name\" overschrijven?';
  }

  @override
  String get session_playground_overwriteDialog_message =>
      'Er bestaat al een bestand met deze naam.';

  @override
  String get session_playground_overwriteDialog_confirm => 'Overschrijven';

  @override
  String get session_playground_openDialog_title => 'Opgeslagen code openen';

  @override
  String get session_playground_openDialog_empty =>
      'Nog geen opgeslagen bestanden.';

  @override
  String get session_playground_openDialog_delete_tooltip => 'Verwijderen';

  @override
  String session_playground_openDialog_conflict(String names) {
    return 'Ook op een andere computer gewijzigd. De versie van deze computer is apart bewaard als: $names';
  }

  @override
  String session_playground_deleteDialog_title(String name) {
    return '\"$name\" verwijderen?';
  }

  @override
  String get session_playground_deleteDialog_message =>
      'Dit kan niet ongedaan gemaakt worden.';

  @override
  String get session_playground_deleteDialog_confirm => 'Verwijderen';

  @override
  String get session_playground_discardDialog_title =>
      'Huidige code vervangen?';

  @override
  String get session_playground_discardDialog_message =>
      'Je niet-opgeslagen wijzigingen gaan verloren.';

  @override
  String get session_playground_discardDialog_confirm => 'Vervangen';

  @override
  String session_playground_snack_saved(String name) {
    return 'Opgeslagen als \"$name\".';
  }

  @override
  String session_playground_snack_saveFailed(String error) {
    return 'Opslaan mislukt: $error';
  }

  @override
  String session_playground_snack_openFailed(String error) {
    return 'Openen mislukt: $error';
  }

  @override
  String session_playground_snack_tooLarge(int max) {
    return 'Deze code is te groot om op te slaan (meer dan $max KB).';
  }

  @override
  String session_playground_snack_tooManyFiles(int max) {
    return 'Je hebt al $max opgeslagen bestanden, dat is het maximum. Verwijder er eerst een.';
  }

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
  String get session_output_meta_turtleWindow =>
      'Er staat een turtle-venster open. Sluit het, of druk op Stop, om de uitvoering te beëindigen.';

  @override
  String get session_output_meta_stopped => 'Gestopt.';

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
    return 'Het bestand bevat $rootCount hoofd­doel(en) en $total node(s) in totaal.\n\n• Toevoegen: voeg toe met de id\'s uit het bestand. Stopt als er een id al bestaat.\n• Vervangen: werkt de overeenkomstige set(s) bij per id (bestaande lesinhoud-koppelingen blijven) en verwijdert enkel doelen binnen die sets die niet in het bestand staan. Andere sets blijven onaangeroerd.\n• Alles vervangen: verwijdert elk doel dat niet in het bestand staat, over alle sets heen.';
  }

  @override
  String get goals_import_action_cancel => 'Annuleer';

  @override
  String get goals_import_action_add => 'Toevoegen';

  @override
  String get goals_import_action_replace => 'Vervangen';

  @override
  String get goals_import_action_replaceAll => 'Alles vervangen';

  @override
  String get goals_import_action_continue => 'Ga verder';

  @override
  String get goals_import_unmatched_title => 'Geen overeenkomstige set';

  @override
  String goals_import_unmatched_message(String rootTitle) {
    return 'De set \"$rootTitle\" uit het bestand komt met geen enkele bestaande set overeen. Kies wat ermee moet gebeuren.';
  }

  @override
  String get goals_import_unmatched_addAsNew => 'Toevoegen als nieuwe set';

  @override
  String goals_import_unmatched_replaceOption(String rootTitle) {
    return 'Vervang \"$rootTitle\"';
  }

  @override
  String get goals_import_preview_title => 'Vervangen bevestigen';

  @override
  String goals_import_preview_replaceLine(
    String rootTitle,
    int count,
    int removed,
  ) {
    return 'Vervangt \"$rootTitle\" ($count doel(en) in bestand, $removed worden verwijderd)';
  }

  @override
  String goals_import_preview_newSetLine(String rootTitle) {
    return 'Voegt nieuwe set \"$rootTitle\" toe';
  }

  @override
  String get goals_import_previewAll_title => 'Alle sets vervangen';

  @override
  String goals_import_previewAll_message(int removed) {
    return 'Dit verwijdert elk doel dat niet in het bestand staat, over alle sets heen: $removed doel(en) worden verwijderd.';
  }

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
  String get goals_editor_teachingTips_empty => 'Nog geen lestips.';

  @override
  String get goals_editor_teachingTips_add => 'Toevoegen';

  @override
  String get goals_editor_teachingTips_edit => 'Tip bewerken';

  @override
  String get goals_editor_teachingTips_delete => 'Tip verwijderen';

  @override
  String get goals_editor_teachingTips_save => 'Opslaan';

  @override
  String get goals_editor_teachingTips_cancel => 'Annuleer';

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
  String get lesson_run_output_label => 'Uitvoer';

  @override
  String get lesson_run_button => 'Uitvoeren';

  @override
  String get lesson_run_running => 'Aan het uitvoeren…';

  @override
  String get lesson_run_unavailable =>
      'Het voorbeeld kan alleen in de app worden uitgevoerd.';

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
  String get accounts_classFilter_all => 'Alle klassen';

  @override
  String get accounts_classFilter_none => 'Geen klas';

  @override
  String get accounts_column_email => 'E-MAIL';

  @override
  String get accounts_column_name => 'NAAM';

  @override
  String get accounts_column_class => 'KLAS';

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
  String get accounts_class_dialog_title => 'Klas toewijzen';

  @override
  String get accounts_class_dialog_hint => 'Klasnaam (leeg laten om te wissen)';

  @override
  String get accounts_class_dialog_cancel => 'Annuleer';

  @override
  String get accounts_class_dialog_save => 'Opslaan';

  @override
  String accounts_class_saveFailed(String error) {
    return 'Klas opslaan mislukt: $error';
  }

  @override
  String accounts_bulk_selectedCount(int count) {
    return '$count geselecteerd';
  }

  @override
  String get accounts_bulk_assignClass => 'Klas toewijzen';

  @override
  String get accounts_bulk_clearSelection => 'Selectie wissen';

  @override
  String accounts_bulk_assignSuccess(int count) {
    return 'Klas bijgewerkt voor $count leerlingen';
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

  @override
  String get common_undo => 'Ongedaan maken';

  @override
  String get crash_permissionDenied =>
      'Geen toegang bij het lezen van gegevens.';

  @override
  String get auth_browser_signedIn_title => 'Aangemeld';

  @override
  String get auth_browser_signedIn_body =>
      'Je kunt dit tabblad sluiten en teruggaan naar de app.';

  @override
  String get auth_browser_failed_title => 'Aanmelden mislukt';

  @override
  String get auth_browser_failed_noCode => 'Geen autorisatiecode ontvangen.';

  @override
  String get auth_browser_failed_stateMismatch =>
      'State komt niet overeen — mogelijk CSRF, probeer het opnieuw.';

  @override
  String levelUp_caption(int xp) {
    return '+$xp XP · CONCEPT ONTGRENDELD';
  }

  @override
  String levelUp_level(int level) {
    return 'Level $level';
  }

  @override
  String get levelUp_subtitle_generic =>
      'Je hebt het volgende concept onder de knie.';

  @override
  String levelUp_subtitle_concept(String concept) {
    return 'Je hebt $concept onder de knie.';
  }

  @override
  String get levelUp_button_continue => 'Verder leren';

  @override
  String get splash_title => 'Doel bereikt!';

  @override
  String get splash_phrase_01 =>
      'LEGENDARISCH! Je code zal eeuwenlang worden bezongen!';

  @override
  String get splash_phrase_02 => 'Wauw! Zelfs je toetsenbord klapt voor je!';

  @override
  String get splash_phrase_03 => 'Kijk uit, de AI wordt jaloers op je!';

  @override
  String get splash_phrase_04 => 'Je hebt zojuist de informaticagod ontroerd.';

  @override
  String get splash_phrase_05 =>
      'BAM! Nog één overwinning voor de Hall of Fame!';

  @override
  String get splash_phrase_06 =>
      'Je toetsen maken rook — zo snel programmeer jij!';

  @override
  String get splash_phrase_07 =>
      'Briljant! Zelfs Stack Overflow heeft geen woorden.';

  @override
  String get splash_phrase_08 => 'De bugpolitie heeft vandaag verloren!';

  @override
  String get splash_phrase_09 =>
      'Wat een meesterwerk! Rembrandt, maar dan in Python.';

  @override
  String get splash_phrase_10 =>
      'Je hebt net het internet verbeterd. Graag gedaan!';

  @override
  String get splash_phrase_11 =>
      'Overheid belt: ze willen je algoritme aankopen.';

  @override
  String get splash_phrase_12 =>
      'Applaus! De bits en bytes staan recht voor je!';

  @override
  String get splash_phrase_13 => 'De compiler glimlacht. Dat gebeurt zelden.';

  @override
  String get splash_phrase_14 =>
      'Je code is zo zuiver dat je er door kan kijken.';

  @override
  String get splash_phrase_15 =>
      'De matrix heeft je opgemerkt… en knikt goedkeurend.';

  @override
  String get splash_phrase_16 => 'De muis fluistert: \'ik ben niet waardig\'.';

  @override
  String get splash_phrase_17 =>
      'Zelfs je laptop wil nu een handtekening van je.';

  @override
  String get splash_phrase_18 => 'Een nieuw record! De pixels juichen!';

  @override
  String get splash_phrase_19 =>
      'Je hebt de grenzen van menselijk begrip overschreden.';

  @override
  String get splash_phrase_20 => 'Wiskundigen huilen van ontroering.';

  @override
  String get splash_phrase_21 =>
      'Python zelf fluistert: \'thank you, master\'.';

  @override
  String get splash_phrase_22 => 'Dit is geen succes meer. Dit is folklore.';

  @override
  String get splash_phrase_23 =>
      'NASA belt: \'kun je bij ons komen debuggen?\'';

  @override
  String get splash_phrase_24 =>
      'De AI-tutor heeft besloten jou voortaan te tutoren.';

  @override
  String get splash_phrase_25 =>
      'Stop! Je bent te goed. Geef de rest een kans.';

  @override
  String get chat_role_explanation => 'uitleg';

  @override
  String get chat_role_example => 'voorbeeld';

  @override
  String get chat_role_question => 'denkvraag';

  @override
  String get chat_role_correct => 'goed';

  @override
  String get session_writeCode_template => '# Schrijf hier je code';

  @override
  String get difficulty_easy => 'makkelijk';

  @override
  String get difficulty_medium => 'gemiddeld';

  @override
  String get difficulty_hard => 'moeilijk';

  @override
  String chat_notice_tutorFailed(String detail) {
    return 'Er ging iets mis bij de tutor: $detail';
  }

  @override
  String chat_notice_sessionStartFailed(String detail) {
    return 'De sessie kon niet starten: $detail';
  }

  @override
  String get chat_notice_databaseUnavailable =>
      'De verbinding met de database is even weg. Probeer het zo opnieuw.';

  @override
  String get chat_notice_tutorTimeout => 'De tutor reageerde niet op tijd.';

  @override
  String get chat_notice_tutorUnreachable => 'Geen verbinding met de tutor.';

  @override
  String get chat_notice_replyTruncated =>
      'Het antwoord van de tutor werd afgebroken.';

  @override
  String get chat_notice_noPreviousRequest =>
      'Geen vorige aanvraag om opnieuw te proberen.';

  @override
  String get chat_notice_emptyResponse => 'Lege respons van de tutor.';

  @override
  String chat_notice_unparseableResponse(String raw) {
    return 'Kon respons niet verwerken: $raw';
  }

  @override
  String chat_notice_unknownResponseType(String type) {
    return 'Onbekend antwoordtype: $type';
  }

  @override
  String get chat_notice_unknownResponse => 'Onbekend antwoord ontvangen.';

  @override
  String get chat_notice_exerciseWithoutBlank =>
      'In die oefening viel niets meer in te vullen. Ik haal een nieuwe op.';

  @override
  String get chat_notice_subgoalDeletedRedirect =>
      'Je vorige onderwerp is verwijderd door je leerkracht. Ga verder met het volgende.';

  @override
  String get chat_notice_subgoalSaturated =>
      'Je hebt dit subdoel al goed onder de knie. Klaar om verder te gaan?';

  @override
  String get chat_notice_noGoalsLeft =>
      'Er zijn geen doelen meer om aan te werken. Gefeliciteerd!';

  @override
  String get chat_notice_emptyObjectives =>
      'Dit subdoel is nog niet helemaal klaar — vraag je leerkracht om het af te ronden, of kies een ander subdoel.';

  @override
  String get chat_notice_preparingExercise =>
      'Je volgende oefening wordt voorbereid...';

  @override
  String get chat_notice_feedbackDegraded =>
      'Er is iets mis met de feedback. Probeer het over een paar minuten opnieuw.';

  @override
  String chat_notice_newGoalSelected(String title) {
    return 'Nieuw doel geselecteerd: $title';
  }

  @override
  String chat_notice_warmUpReview(String title) {
    return 'Eerst even opwarmen: één opfrisvraag over $title.';
  }

  @override
  String chat_notice_difficultyChanged(String from, String to) {
    return 'Moeilijkheid aangepast: $from -> $to';
  }

  @override
  String get chat_notice_submitViaEditor =>
      'Pas je code aan in de editor links en druk op Run om je oplossing in te sturen.';
}
