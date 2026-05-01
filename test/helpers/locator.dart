import 'package:get_it/get_it.dart';

/// Register a mock for a service type. Replaces any existing registration so
/// each test starts from a clean slate.
void registerMock<T extends Object>(T mock) {
  final locator = GetIt.instance;
  if (locator.isRegistered<T>()) {
    locator.unregister<T>();
  }
  locator.registerSingleton<T>(mock);
}

/// Tear-down hook for tests that touch the locator.
Future<void> resetLocator() => GetIt.instance.reset();
