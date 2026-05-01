// Azure credentials for Cosmos DB + Entra ID.
//
// Required `.env` entries (file is gitignored, lives at repo root):
//
//   COSMOS_ENDPOINT=https://<account>.documents.azure.com:443/
//   COSMOS_KEY=<primary-master-key>
//   ENTRA_TENANT_ID=<tenant-guid>
//   ENTRA_CLIENT_ID=<app-registration-client-id>
//   ENTRA_REDIRECT_URI=<redirect-uri-from-app-registration>
//
// Only `COSMOS_KEY` is treated as a secret and obfuscated by envied. The
// others are not secrets — tenant/client IDs and redirect URIs are public per
// Microsoft's OAuth2 model. They live in the same .env for convenience.
//
// After editing .env, regenerate with:
//   dart run build_runner build --delete-conflicting-outputs

import 'package:envied/envied.dart';

part 'azure_config.g.dart';

@Envied(path: ".env")
abstract class AzureConfig {
  @EnviedField(varName: 'COSMOS_ENDPOINT')
  static final String cosmosEndpoint = _AzureConfig.cosmosEndpoint;

  @EnviedField(varName: 'COSMOS_KEY', obfuscate: true)
  static final String cosmosKey = _AzureConfig.cosmosKey;

  @EnviedField(varName: 'ENTRA_TENANT_ID')
  static final String tenantId = _AzureConfig.tenantId;

  @EnviedField(varName: 'ENTRA_CLIENT_ID')
  static final String clientId = _AzureConfig.clientId;

  @EnviedField(varName: 'ENTRA_REDIRECT_URI')
  static final String redirectUri = _AzureConfig.redirectUri;
}
