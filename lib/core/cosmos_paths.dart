// Single source of truth for Cosmos container handles.

import 'package:ai_tutor_python/core/cosmos_client.dart';

const String _accountsContainer = 'accounts';
const String _progressContainer = 'progress';
const String _progressHistoryContainer = 'progress_history';
const String _statusReportsContainer = 'status_reports';
const String _goalsContainer = 'goals';
const String _instructionsContainer = 'instructions';
const String _configContainer = 'config';

/// Constant partition-key values for the single-partition containers
/// (`goals`, `instructions`, `config`). Each doc in those containers carries
/// a `type` field with this exact value.
class CosmosPartitions {
  static const String goal = 'goal';
  static const String instruction = 'instruction';
  static const String config = 'config';
}

class CosmosPaths {
  static CosmosClient get _client => CosmosClient.instance;

  /// `/uid` partition. One doc per user.
  static CosmosContainer accounts() => _client.container(_accountsContainer);

  /// `/uid` partition. Doc id `${uid}_${goalId}`. Flattened from the old
  /// `accounts/{uid}/progress/{goalId}` subcollection.
  static CosmosContainer progress() => _client.container(_progressContainer);

  /// `/uid` partition. One doc per progress sample, time-ordered. Time
  /// series for the teacher detail panel; not read in the student flow.
  static CosmosContainer progressHistory() =>
      _client.container(_progressHistoryContainer);

  /// `/uid` partition. Doc id `${uid}_${goalId}`. Flattened from the old
  /// `accounts/{uid}/status_reports/{goalId}` subcollection.
  static CosmosContainer statusReports() =>
      _client.container(_statusReportsContainer);

  /// `/type` partition (always `"goal"`). Single logical partition shared by
  /// all users — tree is small.
  static CosmosContainer goals() => _client.container(_goalsContainer);

  /// `/type` partition (always `"instruction"`). Single logical partition.
  static CosmosContainer instructions() =>
      _client.container(_instructionsContainer);

  /// `/type` partition (always `"config"`). Single doc with id `global`.
  static CosmosContainer config() => _client.container(_configContainer);
}
