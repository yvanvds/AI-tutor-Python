// The school mode every test that boots `GoalsApp` runs in (#262).
//
// Not the build's own: a test must not depend on the developer's `.env` (a
// real school) or CI's (no school, so stand-alone). Flows about stand-alone
// mode override `appModeProvider` with `const StandaloneMode()` instead.

import 'package:ai_tutor_python/core/app_mode.dart';

final SchoolConfig kTestSchool = SchoolConfig(
  tenantId: '11111111-1111-1111-1111-111111111111',
  clientId: '22222222-2222-2222-2222-222222222222',
  redirectUri: 'http://localhost',
  databaseEndpoint: Uri.parse('https://test-school.documents.azure.com:443/'),
);

final AppMode kTestSchoolMode = SchoolMode(kTestSchool);
