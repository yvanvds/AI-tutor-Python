import 'package:cloud_firestore/cloud_firestore.dart';

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

  factory GlobalConfig.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return GlobalConfig.fromMap(data);
  }

  Map<String, dynamic> toMap() => {
    // kept for withConverter symmetry, not for writes
    'Model': model,
    'ApiKey': apiKey,
  };
}
