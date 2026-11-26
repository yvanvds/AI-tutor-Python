// Opening the user's browser at a URL: the GitHub device flow's verification
// page (#57) and the school's sign-in page (`AuthService.signIn`, #345).
//
// A seam for the same reason `installerLauncherProvider` is one (#49): the
// production implementation hands a URL to the operating system, which in a
// test run means a real browser window on the machine running the suite.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the browser; whether the operating system took it.
typedef BrowserLauncher = Future<bool> Function(Uri url);

final browserLauncherProvider = Provider<BrowserLauncher>(
  (_) =>
      (Uri url) => launchUrl(url, mode: LaunchMode.externalApplication),
);
