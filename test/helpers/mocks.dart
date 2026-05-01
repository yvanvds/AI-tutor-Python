import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/instructions/instructions_service.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:ai_tutor_python/services/sound/sound_service.dart';
import 'package:ai_tutor_python/services/splash/splash_service.dart';
import 'package:ai_tutor_python/services/status_report/report_service.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:mocktail/mocktail.dart';

class MockAccountService extends Mock implements AccountService {}

class MockAuthService extends Mock implements AuthService {}

class MockChatService extends Mock implements ChatService {}

class MockCodeService extends Mock implements CodeService {}

class MockConductor extends Mock implements Conductor {}

class MockGoalsService extends Mock implements GoalsService {}

class MockInstructionsService extends Mock implements InstructionsService {}

class MockOpenaiConnector extends Mock implements OpenaiConnector {}

class MockProgressService extends Mock implements ProgressService {}

class MockReportService extends Mock implements ReportService {}

class MockSoundService extends Mock implements SoundService {}

class MockSplashService extends Mock implements SplashService {}

class MockTutorService extends Mock implements TutorService {}
