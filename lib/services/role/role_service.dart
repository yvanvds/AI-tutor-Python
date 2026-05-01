import 'package:ai_tutor_python/services/data_service.dart';
import 'package:flutter/widgets.dart';

/// Tracks whether the signed-in user is a teacher.
///
/// Roles ride on the Entra access token's `roles` app-role claim. The
/// AuthService parses that into `AccountIdentity.isTeacher`; this service
/// just mirrors it into a notifier so feature widgets keep using
/// `DataService.role.isTeacher`.
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
