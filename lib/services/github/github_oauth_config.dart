// The GitHub OAuth app the in-app bug reporter signs in with (#57).
//
// Optional `.env` entry (file is gitignored, lives at repo root):
//
//   GITHUB_OAUTH_CLIENT_ID=Ov23li...
//
// This is a **public** identifier, not a secret, and it is deliberately not
// obfuscated — the device flow has no client secret at all, which is the
// reason it suits a desktop app that ships to students (the same reasoning as
// `ENTRA_CLIENT_ID` in `azure_config.dart`).
//
// It defaults to the empty string, so a checkout whose `.env` predates this
// feature — and CI's generated dummy `.env` — still generates and builds. An
// empty client id means "no OAuth app has been registered for this build":
// `GitHubDeviceFlow.isConfigured` is then false and the Options panel says so
// instead of starting a flow that cannot succeed. See README "Step 8" for how
// to register the app.
//
// After editing .env, regenerate with:
//   dart run build_runner build

import 'package:envied/envied.dart';

part 'github_oauth_config.g.dart';

@Envied(path: ".env")
abstract class GitHubOAuthConfig {
  @EnviedField(varName: 'GITHUB_OAUTH_CLIENT_ID', defaultValue: '')
  static const String clientId = _GitHubOAuthConfig.clientId;
}
