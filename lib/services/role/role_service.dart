import 'package:ai_tutor_python/services/data_service.dart';
import 'package:flutter/widgets.dart';

/// Tracks whether the signed-in user is a teacher.
///
/// Step 3 of the migration: roles are no longer stored as Firestore docs —
/// they ride on the Entra access token's `roles` app-role claim. The
/// AuthService parses that out into `AccountIdentity.isTeacher`; this service
/// just mirrors it into a notifier so feature widgets keep their existing
/// `DataService.role.isTeacher` API.
class RoleService {
  RoleService() {
    DataService.auth.currentUser.addListener(_update);
    _update();
  }

  final ValueNotifier<bool> isTeacher = ValueNotifier<bool>(false);

  void _update() {
    isTeacher.value = DataService.auth.currentUser.value?.isTeacher ?? false;
  }

  void dispose() {
    DataService.auth.currentUser.removeListener(_update);
    isTeacher.dispose();
  }
}
