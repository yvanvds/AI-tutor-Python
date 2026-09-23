class GlobalConfig {
  final String model;
  final String apiKey;

  /// The oldest build allowed to run (#165), as `MinimumVersion` on the doc —
  /// `2.6.0`, or `2.6.0+23` to name a build — or `null` when the school sets
  /// none. Set from the Cosmos portal, like `ApiKey`; read by
  /// `updateRequirementProvider`, which puts a build below it in front of the
  /// update screen instead of the app. A blank value is the same as none.
  final String? minimumVersion;

  const GlobalConfig({
    required this.model,
    required this.apiKey,
    this.minimumVersion,
  });

  factory GlobalConfig.fromMap(Map<String, dynamic> map) {
    final Object? minimum = map['MinimumVersion'];
    final String minimumText = minimum is String ? minimum.trim() : '';
    return GlobalConfig(
      model: (map['Model'] ?? '') as String,
      apiKey: (map['ApiKey'] ?? '') as String,
      minimumVersion: minimumText.isEmpty ? null : minimumText,
    );
  }

  /// Serialize for Cosmos. Always written under the single `global` doc id
  /// in the `config` container; both `id` and the partition-key field
  /// (`type: "config"`) are included so callers can pass the map directly
  /// to upsert.
  Map<String, dynamic> toMap() => {
    'id': 'global',
    'type': 'config',
    'Model': model,
    'ApiKey': apiKey,
    if (minimumVersion != null) 'MinimumVersion': minimumVersion,
  };
}
