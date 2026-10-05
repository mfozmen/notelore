/// Which Google sign-in this build uses for Drive.
///
/// The OAuth client ids come in at build time (`--dart-define`, from `.env`
/// locally and from GitHub secrets for releases) and are never committed. A
/// build without them has no Drive sync.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:url_launcher/url_launcher.dart';

const _clientId = String.fromEnvironment('NOTELORE_GOOGLE_CLIENT_ID');
const _clientSecret = String.fromEnvironment('NOTELORE_GOOGLE_CLIENT_SECRET');
const _webClientId = String.fromEnvironment('NOTELORE_GOOGLE_WEB_CLIENT_ID');

/// Google sign-in on the phone (Android: Credential Manager; the app is
/// registered by package name and signing certificate, plus a web client id).
DriveAuth? driveAuthFor({
  required bool mobile,
  required FlutterSecureStorage keys,
  required String keySpace,
  String clientId = _clientId,
  String clientSecret = _clientSecret,
  String webClientId = _webClientId,
}) {
  if (mobile) return webClientId.isEmpty ? null : GoogleSignInAuth(serverClientId: webClientId);
  if (clientId.isEmpty) return null;
  final name = '$keySpace.google.refresh_token';
  return LoopbackAuth(
    clientId: clientId,
    clientSecret: clientSecret,
    openBrowser: (url) => launchUrl(url, mode: LaunchMode.externalApplication),
    readRefreshToken: () => keys.read(key: name),
    saveRefreshToken: (token) =>
        token == null ? keys.delete(key: name) : keys.write(key: name, value: token),
  );
}

/// Drive access through the google_sign_in plugin. The plugin keeps the grant;
/// tokens are asked for silently and only [signIn] may show a sheet.
class GoogleSignInAuth implements DriveAuth {
  GoogleSignInAuth({required this.serverClientId});

  final String serverClientId;
  Future<void>? _initialized;

  Future<GoogleSignInAuthorizationClient> _client() async {
    await (_initialized ??= GoogleSignIn.instance.initialize(serverClientId: serverClientId));
    return GoogleSignIn.instance.authorizationClient;
  }

  String? _last;

  @override
  Future<bool> signedIn() async =>
      await (await _client()).authorizationForScopes(const [driveScope]) != null;

  @override
  Future<void> signIn() async {
    try {
      await (await _client()).authorizeScopes(const [driveScope]);
    } on GoogleSignInException catch (error) {
      throw SignInFailed(error.description ?? error.code.name);
    }
  }

  @override
  Future<String> token({bool refresh = false}) async {
    final client = await _client();
    if (refresh && _last != null) await client.clearAuthorizationToken(accessToken: _last!);
    final authorization = await client.authorizationForScopes(const [driveScope]);
    if (authorization == null) throw const NotSignedIn();
    return _last = authorization.accessToken;
  }

  @override
  Future<void> signOut() async {
    await _client();
    await GoogleSignIn.instance.disconnect(); // revokes the grant, not just this device
  }
}
