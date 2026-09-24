class GlobalConfig {
  final String model;
  final String apiKey;

  /// The oldest build allowed to run (#165), as `MinimumVersion` on the doc —
  /// `2.6.0`, or `2.6.0+23` to name a build — or `null` when the school sets
  /// none. Set from the Cosmos portal, like `ApiKey`; read by
  /// `updateRequirementProvider`, which puts a build below it in front of the
  /// update screen instead of the app. A blank value is the same as none.
  final String? minimumVersion;

  /// How many questions the question bank must hold for a plan — fitting it
  /// and not yet asked of this student — before the conductor may take one
  /// from there instead of generating (#186, CONDUCTOR_POLICY §2.7), as
  /// `QuestionBankMinimum` on the doc. `null` when the school sets none (or
  /// a value below 1): `PolicyConstants.bankMinimum` then. Set from the
  /// Cosmos portal, per period.
  final int? questionBankMinimum;

  /// The chance that a question the bank could serve is taken from it
  /// rather than generated (#186), as `QuestionBankShare` on the doc, from 0
  /// to 1. `null` when the school sets none (or a value that is not a
  /// number): `PolicyConstants.bankShare` then. 0 switches serving from the
  /// bank off altogether; the bank still fills. Set from the Cosmos portal.
  final double? questionBankShare;

  const GlobalConfig({
    required this.model,
    required this.apiKey,
    this.minimumVersion,
    this.questionBankMinimum,
    this.questionBankShare,
  });

  factory GlobalConfig.fromMap(Map<String, dynamic> map) {
    final Object? minimum = map['MinimumVersion'];
    final String minimumText = minimum is String ? minimum.trim() : '';
    final Object? bankMinimum = map['QuestionBankMinimum'];
    final Object? bankShare = map['QuestionBankShare'];
    return GlobalConfig(
      model: (map['Model'] ?? '') as String,
      apiKey: (map['ApiKey'] ?? '') as String,
      minimumVersion: minimumText.isEmpty ? null : minimumText,
      questionBankMinimum: bankMinimum is num && bankMinimum >= 1
          ? bankMinimum.toInt()
          : null,
      questionBankShare: bankShare is num && !bankShare.isNaN
          ? bankShare.toDouble().clamp(0.0, 1.0)
          : null,
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
    if (questionBankMinimum != null) 'QuestionBankMinimum': questionBankMinimum,
    if (questionBankShare != null) 'QuestionBankShare': questionBankShare,
  };
}
