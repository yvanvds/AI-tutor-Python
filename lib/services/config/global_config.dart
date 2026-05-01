class GlobalConfig {
  final String model;
  final String apiKey;

  const GlobalConfig({required this.model, required this.apiKey});

  factory GlobalConfig.fromMap(Map<String, dynamic> map) {
    return GlobalConfig(
      model: (map['Model'] ?? '') as String,
      apiKey: (map['ApiKey'] ?? '') as String,
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
  };
}
