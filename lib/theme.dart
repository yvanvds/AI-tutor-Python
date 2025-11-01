import "package:flutter/material.dart";

class MaterialTheme {
  final TextTheme textTheme;

  const MaterialTheme(this.textTheme);

  static ColorScheme lightScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xff804d79),
      surfaceTint: Color(0xff804d79),
      onPrimary: Color(0xffffffff),
      primaryContainer: Color(0xffffd7f5),
      onPrimaryContainer: Color(0xff663560),
      secondary: Color(0xff6e5869),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xfff7daee),
      onSecondaryContainer: Color(0xff554151),
      tertiary: Color(0xff815345),
      onTertiary: Color(0xffffffff),
      tertiaryContainer: Color(0xffffdbd1),
      onTertiaryContainer: Color(0xff663c2f),
      error: Color(0xffba1a1a),
      onError: Color(0xffffffff),
      errorContainer: Color(0xffffdad6),
      onErrorContainer: Color(0xff93000a),
      surface: Color(0xfffff7f9),
      onSurface: Color(0xff201a1e),
      onSurfaceVariant: Color(0xff4e444b),
      outline: Color(0xff80747b),
      outlineVariant: Color(0xffd1c2cb),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xff352e33),
      inversePrimary: Color(0xfff1b3e6),
      primaryFixed: Color(0xffffd7f5),
      onPrimaryFixed: Color(0xff340832),
      primaryFixedDim: Color(0xfff1b3e6),
      onPrimaryFixedVariant: Color(0xff663560),
      secondaryFixed: Color(0xfff7daee),
      onSecondaryFixed: Color(0xff271624),
      secondaryFixedDim: Color(0xffdabfd2),
      onSecondaryFixedVariant: Color(0xff554151),
      tertiaryFixed: Color(0xffffdbd1),
      onTertiaryFixed: Color(0xff321208),
      tertiaryFixedDim: Color(0xfff5b8a7),
      onTertiaryFixedVariant: Color(0xff663c2f),
      surfaceDim: Color(0xffe3d7dd),
      surfaceBright: Color(0xfffff7f9),
      surfaceContainerLowest: Color(0xffffffff),
      surfaceContainerLow: Color(0xfffdf0f7),
      surfaceContainer: Color(0xfff7eaf1),
      surfaceContainerHigh: Color(0xfff1e5eb),
      surfaceContainerHighest: Color(0xffecdfe5),
    );
  }

  ThemeData light() {
    return theme(lightScheme());
  }

  static ColorScheme lightMediumContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xff53254f),
      surfaceTint: Color(0xff804d79),
      onPrimary: Color(0xffffffff),
      primaryContainer: Color(0xff905b89),
      onPrimaryContainer: Color(0xffffffff),
      secondary: Color(0xff433040),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xff7d6678),
      onSecondaryContainer: Color(0xffffffff),
      tertiary: Color(0xff532c20),
      onTertiary: Color(0xffffffff),
      tertiaryContainer: Color(0xff926152),
      onTertiaryContainer: Color(0xffffffff),
      error: Color(0xff740006),
      onError: Color(0xffffffff),
      errorContainer: Color(0xffcf2c27),
      onErrorContainer: Color(0xffffffff),
      surface: Color(0xfffff7f9),
      onSurface: Color(0xff150f14),
      onSurfaceVariant: Color(0xff3d333a),
      outline: Color(0xff5a4f57),
      outlineVariant: Color(0xff756a71),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xff352e33),
      inversePrimary: Color(0xfff1b3e6),
      primaryFixed: Color(0xff905b89),
      onPrimaryFixed: Color(0xffffffff),
      primaryFixedDim: Color(0xff75436f),
      onPrimaryFixedVariant: Color(0xffffffff),
      secondaryFixed: Color(0xff7d6678),
      onSecondaryFixed: Color(0xffffffff),
      secondaryFixedDim: Color(0xff644e5f),
      onSecondaryFixedVariant: Color(0xffffffff),
      tertiaryFixed: Color(0xff926152),
      onTertiaryFixed: Color(0xffffffff),
      tertiaryFixedDim: Color(0xff76493c),
      onTertiaryFixedVariant: Color(0xffffffff),
      surfaceDim: Color(0xffcfc3c9),
      surfaceBright: Color(0xfffff7f9),
      surfaceContainerLowest: Color(0xffffffff),
      surfaceContainerLow: Color(0xfffdf0f7),
      surfaceContainer: Color(0xfff1e5eb),
      surfaceContainerHigh: Color(0xffe6dae0),
      surfaceContainerHighest: Color(0xffdaced5),
    );
  }

  ThemeData lightMediumContrast() {
    return theme(lightMediumContrastScheme());
  }

  static ColorScheme lightHighContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xff471b44),
      surfaceTint: Color(0xff804d79),
      onPrimary: Color(0xffffffff),
      primaryContainer: Color(0xff683863),
      onPrimaryContainer: Color(0xffffffff),
      secondary: Color(0xff382635),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xff574353),
      onSecondaryContainer: Color(0xffffffff),
      tertiary: Color(0xff472217),
      onTertiary: Color(0xffffffff),
      tertiaryContainer: Color(0xff693e31),
      onTertiaryContainer: Color(0xffffffff),
      error: Color(0xff600004),
      onError: Color(0xffffffff),
      errorContainer: Color(0xff98000a),
      onErrorContainer: Color(0xffffffff),
      surface: Color(0xfffff7f9),
      onSurface: Color(0xff000000),
      onSurfaceVariant: Color(0xff000000),
      outline: Color(0xff322930),
      outlineVariant: Color(0xff50464d),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xff352e33),
      inversePrimary: Color(0xfff1b3e6),
      primaryFixed: Color(0xff683863),
      onPrimaryFixed: Color(0xffffffff),
      primaryFixedDim: Color(0xff4f214b),
      onPrimaryFixedVariant: Color(0xffffffff),
      secondaryFixed: Color(0xff574353),
      onSecondaryFixed: Color(0xffffffff),
      secondaryFixedDim: Color(0xff3f2d3c),
      onSecondaryFixedVariant: Color(0xffffffff),
      tertiaryFixed: Color(0xff693e31),
      onTertiaryFixed: Color(0xffffffff),
      tertiaryFixedDim: Color(0xff4f281c),
      onTertiaryFixedVariant: Color(0xffffffff),
      surfaceDim: Color(0xffc1b6bc),
      surfaceBright: Color(0xfffff7f9),
      surfaceContainerLowest: Color(0xffffffff),
      surfaceContainerLow: Color(0xfffaedf4),
      surfaceContainer: Color(0xffecdfe5),
      surfaceContainerHigh: Color(0xffddd1d7),
      surfaceContainerHighest: Color(0xffcfc3c9),
    );
  }

  ThemeData lightHighContrast() {
    return theme(lightHighContrastScheme());
  }

  static ColorScheme darkScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xfff1b3e6),
      surfaceTint: Color(0xfff1b3e6),
      onPrimary: Color(0xff4c1f48),
      primaryContainer: Color(0xff663560),
      onPrimaryContainer: Color(0xffffd7f5),
      secondary: Color(0xffdabfd2),
      onSecondary: Color(0xff3d2b3a),
      secondaryContainer: Color(0xff554151),
      onSecondaryContainer: Color(0xfff7daee),
      tertiary: Color(0xfff5b8a7),
      onTertiary: Color(0xff4c261a),
      tertiaryContainer: Color(0xff663c2f),
      onTertiaryContainer: Color(0xffffdbd1),
      error: Color(0xffffb4ab),
      onError: Color(0xff690005),
      errorContainer: Color(0xff93000a),
      onErrorContainer: Color(0xffffdad6),
      surface: Color(0xff171216),
      onSurface: Color(0xffecdfe5),
      onSurfaceVariant: Color(0xffd1c2cb),
      outline: Color(0xff9a8d95),
      outlineVariant: Color(0xff4e444b),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xffecdfe5),
      inversePrimary: Color(0xff804d79),
      primaryFixed: Color(0xffffd7f5),
      onPrimaryFixed: Color(0xff340832),
      primaryFixedDim: Color(0xfff1b3e6),
      onPrimaryFixedVariant: Color(0xff663560),
      secondaryFixed: Color(0xfff7daee),
      onSecondaryFixed: Color(0xff271624),
      secondaryFixedDim: Color(0xffdabfd2),
      onSecondaryFixedVariant: Color(0xff554151),
      tertiaryFixed: Color(0xffffdbd1),
      onTertiaryFixed: Color(0xff321208),
      tertiaryFixedDim: Color(0xfff5b8a7),
      onTertiaryFixedVariant: Color(0xff663c2f),
      surfaceDim: Color(0xff171216),
      surfaceBright: Color(0xff3e373c),
      surfaceContainerLowest: Color(0xff120d11),
      surfaceContainerLow: Color(0xff201a1e),
      surfaceContainer: Color(0xff241e22),
      surfaceContainerHigh: Color(0xff2f282d),
      surfaceContainerHighest: Color(0xff3a3338),
    );
  }

  ThemeData dark() {
    return theme(darkScheme());
  }

  static ColorScheme darkMediumContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xffffcef4),
      surfaceTint: Color(0xfff1b3e6),
      onPrimary: Color(0xff40143d),
      primaryContainer: Color(0xffb77eae),
      onPrimaryContainer: Color(0xff000000),
      secondary: Color(0xfff1d4e8),
      onSecondary: Color(0xff32202f),
      secondaryContainer: Color(0xffa2899c),
      onSecondaryContainer: Color(0xff000000),
      tertiary: Color(0xffffd3c6),
      onTertiary: Color(0xff3f1c11),
      tertiaryContainer: Color(0xffba8474),
      onTertiaryContainer: Color(0xff000000),
      error: Color(0xffffd2cc),
      onError: Color(0xff540003),
      errorContainer: Color(0xffff5449),
      onErrorContainer: Color(0xff000000),
      surface: Color(0xff171216),
      onSurface: Color(0xffffffff),
      onSurfaceVariant: Color(0xffe8d8e1),
      outline: Color(0xffbcaeb6),
      outlineVariant: Color(0xff9a8d95),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xffecdfe5),
      inversePrimary: Color(0xff673761),
      primaryFixed: Color(0xffffd7f5),
      onPrimaryFixed: Color(0xff270026),
      primaryFixedDim: Color(0xfff1b3e6),
      onPrimaryFixedVariant: Color(0xff53254f),
      secondaryFixed: Color(0xfff7daee),
      onSecondaryFixed: Color(0xff1b0c19),
      secondaryFixedDim: Color(0xffdabfd2),
      onSecondaryFixedVariant: Color(0xff433040),
      tertiaryFixed: Color(0xffffdbd1),
      onTertiaryFixed: Color(0xff250802),
      tertiaryFixedDim: Color(0xfff5b8a7),
      onTertiaryFixedVariant: Color(0xff532c20),
      surfaceDim: Color(0xff171216),
      surfaceBright: Color(0xff4a4247),
      surfaceContainerLowest: Color(0xff0b060a),
      surfaceContainerLow: Color(0xff221c20),
      surfaceContainer: Color(0xff2d262b),
      surfaceContainerHigh: Color(0xff383135),
      surfaceContainerHighest: Color(0xff433c40),
    );
  }

  ThemeData darkMediumContrast() {
    return theme(darkMediumContrastScheme());
  }

  static ColorScheme darkHighContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xffffeaf7),
      surfaceTint: Color(0xfff1b3e6),
      onPrimary: Color(0xff000000),
      primaryContainer: Color(0xffedafe2),
      onPrimaryContainer: Color(0xff1d001c),
      secondary: Color(0xffffeaf7),
      onSecondary: Color(0xff000000),
      secondaryContainer: Color(0xffd6bbce),
      onSecondaryContainer: Color(0xff150613),
      tertiary: Color(0xffffece7),
      onTertiary: Color(0xff000000),
      tertiaryContainer: Color(0xfff1b5a3),
      onTertiaryContainer: Color(0xff1d0400),
      error: Color(0xffffece9),
      onError: Color(0xff000000),
      errorContainer: Color(0xffffaea4),
      onErrorContainer: Color(0xff220001),
      surface: Color(0xff171216),
      onSurface: Color(0xffffffff),
      onSurfaceVariant: Color(0xffffffff),
      outline: Color(0xfffcecf5),
      outlineVariant: Color(0xffcdbfc7),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xffecdfe5),
      inversePrimary: Color(0xff673761),
      primaryFixed: Color(0xffffd7f5),
      onPrimaryFixed: Color(0xff000000),
      primaryFixedDim: Color(0xfff1b3e6),
      onPrimaryFixedVariant: Color(0xff270026),
      secondaryFixed: Color(0xfff7daee),
      onSecondaryFixed: Color(0xff000000),
      secondaryFixedDim: Color(0xffdabfd2),
      onSecondaryFixedVariant: Color(0xff1b0c19),
      tertiaryFixed: Color(0xffffdbd1),
      onTertiaryFixed: Color(0xff000000),
      tertiaryFixedDim: Color(0xfff5b8a7),
      onTertiaryFixedVariant: Color(0xff250802),
      surfaceDim: Color(0xff171216),
      surfaceBright: Color(0xff564e53),
      surfaceContainerLowest: Color(0xff000000),
      surfaceContainerLow: Color(0xff241e22),
      surfaceContainer: Color(0xff352e33),
      surfaceContainerHigh: Color(0xff41393e),
      surfaceContainerHighest: Color(0xff4c454a),
    );
  }

  ThemeData darkHighContrast() {
    return theme(darkHighContrastScheme());
  }

  ThemeData theme(ColorScheme colorScheme) => ThemeData(
    useMaterial3: true,
    brightness: colorScheme.brightness,
    colorScheme: colorScheme,
    textTheme: textTheme.apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    ),
    scaffoldBackgroundColor: colorScheme.background,
    canvasColor: colorScheme.surface,
  );

  List<ExtendedColor> get extendedColors => [];
}

class ExtendedColor {
  final Color seed, value;
  final ColorFamily light;
  final ColorFamily lightHighContrast;
  final ColorFamily lightMediumContrast;
  final ColorFamily dark;
  final ColorFamily darkHighContrast;
  final ColorFamily darkMediumContrast;

  const ExtendedColor({
    required this.seed,
    required this.value,
    required this.light,
    required this.lightHighContrast,
    required this.lightMediumContrast,
    required this.dark,
    required this.darkHighContrast,
    required this.darkMediumContrast,
  });
}

class ColorFamily {
  const ColorFamily({
    required this.color,
    required this.onColor,
    required this.colorContainer,
    required this.onColorContainer,
  });

  final Color color;
  final Color onColor;
  final Color colorContainer;
  final Color onColorContainer;
}
