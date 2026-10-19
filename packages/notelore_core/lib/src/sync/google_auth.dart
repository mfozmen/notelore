/// Signing in to Google Drive.
///
/// [DriveAuth] is what the sync needs: a sign-in step and fresh access tokens.
/// [LoopbackAuth] implements it on the desktop with Google's loopback flow for
/// installed apps: the system browser signs in and redirects to a one-shot
/// server on 127.0.0.1, the code is exchanged with PKCE, and only the refresh
/// token is kept (in the platform keystore, through the callbacks). The client
/// secret of a desktop client is not confidential, by Google's own design;
/// it is injected at build time all the same and never committed.
library;

import 'package:http/http.dart' as http;

import '../oauth.dart';
import '../providers/http.dart';
import 'drive.dart';

export '../oauth.dart' show NotSignedIn, SignInFailed;

/// What the sync needs from a Google sign-in; tokens are for [driveScope].
typedef DriveAuth = OAuthSignIn;

const _authorize = 'https://accounts.google.com/o/oauth2/v2/auth';
const _token = 'https://oauth2.googleapis.com/token';
const _revoke = 'https://oauth2.googleapis.com/revoke';

class LoopbackAuth implements DriveAuth {
  LoopbackAuth({
    required this.clientId,
    required this.clientSecret,
    required this.openBrowser,
    required this.readRefreshToken,
    required this.saveRefreshToken,
    http.Client? client,
    DateTime Function()? clock,
    this.wait = const Duration(minutes: 5),
    this.timeout = const Duration(seconds: 30),
    this.scope = driveScope,
  }) : _client = client ?? http.Client(),
       clock = clock ?? DateTime.timestamp;

  final String clientId;
  final String clientSecret;

  /// What the sign-in grants: Drive by default; the calendar has its own (#432).
  final String scope;
  final Future<void> Function(Uri url) openBrowser;
  final Future<String?> Function() readRefreshToken;

  /// Stores the refresh token; null forgets it.
  final Future<void> Function(String? token) saveRefreshToken;
  final DateTime Function() clock;

  /// How long the sign-in waits for the browser to come back.
  final Duration wait;

  /// How long a token request may take before it counts as offline.
  final Duration timeout;
  final http.Client _client;

  String? _access;
  DateTime _expires = DateTime.utc(0);

  @override
  Future<bool> signedIn() async => await readRefreshToken() != null;

  @override
  Future<void> signIn() async {
    final verifier = randomSecret(48);
    final state = randomSecret(16);
    final (:query, :redirect) = await loopbackRedirect(
      authorizeUrl: (redirect) => Uri.parse(_authorize).replace(
        queryParameters: {
          'client_id': clientId,
          'redirect_uri': redirect,
          'response_type': 'code',
          'scope': scope,
          'access_type': 'offline',
          'prompt': 'consent', // always hand out a refresh token
          'state': state,
          'code_challenge': pkceChallenge(verifier),
          'code_challenge_method': 'S256',
        },
      ),
      state: state,
      openBrowser: openBrowser,
      wait: wait,
    );
    final tokens = await _post({
      'grant_type': 'authorization_code',
      'code': query['code']!,
      'redirect_uri': redirect,
      'code_verifier': verifier,
    });
    await saveRefreshToken(tokens['refresh_token']! as String);
    _keep(tokens);
  }

  @override
  Future<String> token({bool refresh = false}) async {
    final valid =
        _access != null && clock().isBefore(_expires.subtract(const Duration(minutes: 1)));
    if (valid && !refresh) return _access!;
    final stored = await readRefreshToken();
    if (stored == null) throw const NotSignedIn();
    try {
      _keep(await _post({'grant_type': 'refresh_token', 'refresh_token': stored}));
    } on HttpError catch (error) {
      if (error.status != 400 || !error.message.contains('invalid_grant')) rethrow;
      await saveRefreshToken(null); // revoked or expired for good: sign in again
      throw const NotSignedIn('Google Drive access was revoked or expired');
    }
    return _access!;
  }

  void _keep(Map<String, Object?> tokens) {
    _access = tokens['access_token']! as String;
    _expires = clock().add(Duration(seconds: tokens['expires_in']! as int));
  }

  Future<Map<String, Object?>> _post(Map<String, String> form) => postForm(
    _client,
    _token,
    {...form, 'client_id': clientId, 'client_secret': clientSecret},
    timeout: timeout,
    service: 'Google',
  );

  /// Forgets the token here and, best effort, revokes it at Google.
  @override
  Future<void> signOut() async {
    final stored = await readRefreshToken();
    _access = null;
    if (stored == null) return;
    await saveRefreshToken(null);
    try {
      await _client.post(Uri.parse(_revoke), body: {'token': stored});
    } on http.ClientException {
      // offline: the token is gone from this device, which is what matters
    }
  }
}
