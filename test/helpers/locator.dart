import 'package:flutter_riverpod/flutter_riverpod.dart';

ProviderContainer makeContainer({List<Override> overrides = const []}) {
  return ProviderContainer(overrides: overrides);
}
