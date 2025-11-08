import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/config/global_config_service.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/instructions/instructions_service.dart';
import 'package:ai_tutor_python/services/output/output_service.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:ai_tutor_python/services/role/role_service.dart';
import 'package:ai_tutor_python/services/sound/sound_service.dart';
import 'package:ai_tutor_python/services/splash/splash_service.dart';
import 'package:ai_tutor_python/services/status_report/report_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:get_it/get_it.dart';

class DataService {
  static GetIt _locator = GetIt.instance;

  static void init() {
    _locator.registerLazySingleton(() => AccountService());
    _locator.registerLazySingleton(() => GlobalConfigService());
    _locator.registerLazySingleton(() => InstructionsService());
    _locator.registerLazySingleton(() => ProgressService());
    _locator.registerLazySingleton(() => ReportService());
    _locator.registerLazySingleton(() => GoalsService());
    _locator.registerLazySingleton(() => RoleService());
    _locator.registerLazySingleton(() => ChatService());
    _locator.registerLazySingleton(() => TutorService());
    _locator.registerLazySingleton(() => CodeService());
    _locator.registerLazySingleton(() => OutputService());
    _locator.registerLazySingleton(() => SplashService());
    _locator.registerLazySingleton(() => SoundService());
  }

  static AccountService get account => _locator<AccountService>();
  static GlobalConfigService get globalConfig =>
      _locator<GlobalConfigService>();
  static InstructionsService get instructions =>
      _locator<InstructionsService>();
  static ProgressService get progress => _locator<ProgressService>();
  static ReportService get report => _locator<ReportService>();
  static GoalsService get goals => _locator<GoalsService>();
  static RoleService get role => _locator<RoleService>();
  static ChatService get chat => _locator<ChatService>();
  static TutorService get tutor => _locator<TutorService>();
  static CodeService get code => _locator<CodeService>();
  static OutputService get output => _locator<OutputService>();
  static SplashService get splash => _locator<SplashService>();
  static SoundService get sound => _locator<SoundService>();
}
