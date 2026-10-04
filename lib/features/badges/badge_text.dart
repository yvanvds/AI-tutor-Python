// A badge's name and what it is for, in the app language (#220).

import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/badges/badge_catalog.dart';

/// The name of [badge]. A "Kenner van …" badge names its hoofddoel:
/// [goalTitle], already in the app language.
String badgeName(
  AppLocalizations l,
  BadgeDefinition badge, {
  String? goalTitle,
}) {
  if (badge.goalId != null) return l.badge_expert_name(goalTitle ?? '');
  return switch (badge.id) {
    'effort' => l.badge_effort_name,
    'homeWork' => l.badge_homeWork_name,
    'lessonWeeks' => l.badge_lessonWeeks_name,
    'hardCorrect' => l.badge_hardCorrect_name,
    'streak' => l.badge_streak_name,
    'gapFiller' => l.badge_gapFiller_name,
    'fluentPython' => l.badge_fluentPython_name,
    'writer' => l.badge_writer_name,
    'allRounder' => l.badge_allRounder_name,
    'knowledge' => l.badge_knowledge_name,
    'milestones' => l.badge_milestones_name,
    'elephantMemory' => l.badge_elephantMemory_name,
    'stillSharp' => l.badge_stillSharp_name,
    'oldFriend' => l.badge_oldFriend_name,
    'comeback' => l.badge_comeback_name,
    'wrongToRight' => l.badge_wrongToRight_name,
    'hintHit' => l.badge_hintHit_name,
    'persevere' => l.badge_persevere_name,
    'tough' => l.badge_tough_name,
    'helloWorld' => l.badge_helloWorld_name,
    'fortyTwo' => l.badge_fortyTwo_name,
    'offByOne' => l.badge_offByOne_name,
    'earlyBird' => l.badge_earlyBird_name,
    'nightOwl' => l.badge_nightOwl_name,
    'weekendWarrior' => l.badge_weekendWarrior_name,
    'fridayHero' => l.badge_fridayHero_name,
    'piHour' => l.badge_piHour_name,
    'piDay' => l.badge_piDay_name,
    'spookyCode' => l.badge_spookyCode_name,
    'rubberDuck' => l.badge_rubberDuck_name,
    'ctrlZ' => l.badge_ctrlZ_name,
    'bugHunter' => l.badge_bugHunter_name,
    'rome' => l.badge_rome_name,
    _ => badge.id,
  };
}

/// What [badge] counts, or — for a single badge — what earned it.
String badgeDescription(
  AppLocalizations l,
  BadgeDefinition badge, {
  String? goalTitle,
}) {
  if (badge.goalId != null) return l.badge_expert_description(goalTitle ?? '');
  return switch (badge.id) {
    'effort' => l.badge_effort_description,
    'homeWork' => l.badge_homeWork_description,
    'lessonWeeks' => l.badge_lessonWeeks_description,
    'hardCorrect' => l.badge_hardCorrect_description,
    'streak' => l.badge_streak_description,
    'gapFiller' => l.badge_gapFiller_description,
    'fluentPython' => l.badge_fluentPython_description,
    'writer' => l.badge_writer_description,
    'allRounder' => l.badge_allRounder_description,
    'knowledge' => l.badge_knowledge_description,
    'milestones' => l.badge_milestones_description,
    'elephantMemory' => l.badge_elephantMemory_description,
    'stillSharp' => l.badge_stillSharp_description,
    'oldFriend' => l.badge_oldFriend_description,
    'comeback' => l.badge_comeback_description,
    'wrongToRight' => l.badge_wrongToRight_description,
    'hintHit' => l.badge_hintHit_description,
    'persevere' => l.badge_persevere_description,
    'tough' => l.badge_tough_description,
    'helloWorld' => l.badge_helloWorld_description,
    'fortyTwo' => l.badge_fortyTwo_description,
    'offByOne' => l.badge_offByOne_description,
    'earlyBird' => l.badge_earlyBird_description,
    'nightOwl' => l.badge_nightOwl_description,
    'weekendWarrior' => l.badge_weekendWarrior_description,
    'fridayHero' => l.badge_fridayHero_description,
    'piHour' => l.badge_piHour_description,
    'piDay' => l.badge_piDay_description,
    'spookyCode' => l.badge_spookyCode_description,
    'rubberDuck' => l.badge_rubberDuck_description,
    'ctrlZ' => l.badge_ctrlZ_description,
    'bugHunter' => l.badge_bugHunter_description,
    'rome' => l.badge_rome_description,
    _ => '',
  };
}
