/// Which Google sign-in this build uses for Drive.
///
/// The OAuth client ids come in at build time (`--dart-define`, from `.env`
/// locally and from GitHub secrets for releases) and are never committed. A
/// build without them has no Drive sync.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'awake_native.dart';

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
}) => _googleAuth(driveScope, 'google', mobile, keys, keySpace, (
  id: clientId,
  secret: clientSecret,
  web: webClientId,
));

/// The calendar's own grant (#432): its own scope and refresh token, so
/// turning it on or off never touches Drive's.
OAuthSignIn? calendarAuthFor({
  required bool mobile,
  required FlutterSecureStorage keys,
  required String keySpace,
  String clientId = _clientId,
  String clientSecret = _clientSecret,
  String webClientId = _webClientId,
}) => _googleAuth(calendarScope, 'google.calendar', mobile, keys, keySpace, (
  id: clientId,
  secret: clientSecret,
  web: webClientId,
));

/// The OAuth clients this build was made with.
typedef _Clients = ({String id, String secret, String web});

OAuthSignIn? _googleAuth(
  String scope,
  String keyName,
  bool mobile,
  FlutterSecureStorage keys,
  String keySpace,
  _Clients clients,
) {
  if (mobile) {
    return clients.web.isEmpty ? null : GoogleSignInAuth(serverClientId: clients.web, scope: scope);
  }
  if (clients.id.isEmpty) return null;
  final name = '$keySpace.$keyName.refresh_token';
  return LoopbackAuth(
    scope: scope,
    clientId: clients.id,
    clientSecret: clients.secret,
    openBrowser: (url) => launchUrl(url, mode: LaunchMode.externalApplication),
    readRefreshToken: () => keys.read(key: name),
    saveRefreshToken: (token) =>
        token == null ? keys.delete(key: name) : keys.write(key: name, value: token),
  );
}

/// The ChatGPT plan's sign-in: OpenAI's loopback redirect for local apps, on
/// 127.0.0.1 of this device. A phone opens the page inside the app (a custom
/// tab), and is held [awake] meanwhile: Android freezes an app in the
/// background, and a frozen app never hears the answer (#409).
OAuthSignIn chatGptAuthFor({
  required bool mobile,
  required FlutterSecureStorage keys,
  required String keySpace,
  Awake? awake,
}) {
  String name(String item) => '$keySpace.chatgpt.$item';
  final auth = ChatGptAuth(
    openBrowser: (url) =>
        launchUrl(url, mode: mobile ? LaunchMode.inAppBrowserView : LaunchMode.externalApplication),
    read: (item) => keys.read(key: name(item)),
    write: (item, value) =>
        value == null ? keys.delete(key: name(item)) : keys.write(key: name(item), value: value),
    // A phone: the page sends the browser back here (SignedInActivity), and the
    // code goes out only once the app is in front, never cut off behind the tab.
    returnTo: mobile ? Uri.parse('notelore://signed-in') : null,
    backInApp: mobile ? _inFront : null,
  );
  return mobile ? AwakeSignIn(auth, awake ?? const NativeAwake()) : auth;
}

/// Keeps the app running, out of the system's freezer, while held.
abstract interface class Awake {
  Future<void> hold();
  Future<void> release();
}

/// [inner], held [awake] for as long as an interactive sign-in runs, and let
/// go however it ends.
class AwakeSignIn implements OAuthSignIn {
  AwakeSignIn(this.inner, this.awake);

  final OAuthSignIn inner;
  final Awake awake;

  @override
  Future<void> signIn() async {
    await awake.hold();
    try {
      await inner.signIn();
    } finally {
      await awake.release();
    }
  }

  @override
  Future<bool> signedIn() => inner.signedIn();

  @override
  Future<String> token({bool refresh = false}) => inner.token(refresh: refresh);

  @override
  Future<void> signOut() => inner.signOut();
}

/// Completes once the app is in front: at once if it already is.
Future<void> _inFront() {
  if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) return Future.value();
  final back = Completer<void>();
  late final AppLifecycleListener listener;
  listener = AppLifecycleListener(
    onResume: () {
      listener.dispose();
      back.complete();
    },
  );
  return back.future;
}

/// Drive access through the google_sign_in plugin. The plugin keeps the grant;
/// tokens are asked for silently and only [signIn] may show a sheet.
class GoogleSignInAuth implements DriveAuth {
  GoogleSignInAuth({required this.serverClientId, this.scope = driveScope});

  final String serverClientId;

  /// What it grants: Drive by default; the calendar has its own (#432).
  final String scope;

  /// Once per app: Drive's and the calendar's sign-ins share the plugin.
  static Future<void>? _initialized;

  Future<GoogleSignInAuthorizationClient> _client() async {
    await (_initialized ??= GoogleSignIn.instance.initialize(serverClientId: serverClientId));
    return GoogleSignIn.instance.authorizationClient;
  }

  String? _last;

  @override
  Future<bool> signedIn() async => await (await _client()).authorizationForScopes(_scopes) != null;

  /// Drive's grant is two scopes in one string (#454).
  List<String> get _scopes => scope.split(' ');

  @override
  Future<void> signIn() async {
    final client = await _client();
    try {
      await client.authorizeScopes(_scopes);
    } on GoogleSignInException catch (error) {
      throw SignInFailed(error.description ?? error.code.name);
    }
    // A box left unticked: the grant does not hold every scope (#484).
    if (await client.authorizationForScopes(_scopes) == null) throw const PartialGrant();
  }

  @override
  Future<String> token({bool refresh = false}) async {
    final client = await _client();
    if (refresh && _last != null) await client.clearAuthorizationToken(accessToken: _last!);
    final authorization = await client.authorizationForScopes(_scopes);
    if (authorization == null) throw const NotSignedIn();
    return _last = authorization.accessToken;
  }

  @override
  Future<void> signOut() async {
    final client = await _client();
    if (scope != driveScope) {
      // The plugin can only disconnect the whole account, which would take
      // Drive too: the calendar drops its token here, and its grant stays
      // with Google until the user removes it in their account settings.
      if (_last case final token?) await client.clearAuthorizationToken(accessToken: token);
      return;
    }
    await GoogleSignIn.instance.disconnect(); // revokes the grant, not just this device
  }
}
