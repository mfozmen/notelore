import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:notelore/src/drive_auth.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// The Google sign-in plugin, in memory: one account that has or has not
/// granted Drive access.
class FakeSignIn extends GoogleSignInPlatform with MockPlatformInterfaceMixin {
  var granted = false;
  var refused = false;
  var issued = 0;
  final cleared = <String>[];
  var disconnected = false;
  String? serverClientId;

  @override
  Future<void> init(InitParameters params) async => serverClientId = params.serverClientId;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async {
    expect(params.request.scopes, [driveScope]);
    if (!granted && params.request.promptIfUnauthorized) {
      if (refused) {
        throw const GoogleSignInException(code: GoogleSignInExceptionCode.canceled);
      }
      granted = true;
    }
    return granted ? ClientAuthorizationTokenData(accessToken: 'access-${++issued}') : null;
  }

  @override
  Future<void> clearAuthorizationToken(ClearAuthorizationTokenParams params) async =>
      cleared.add(params.accessToken);

  @override
  Future<void> disconnect(DisconnectParams params) async {
    disconnected = true;
    granted = false;
  }

  @override
  Future<AuthenticationResults?> attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) async => null;

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(AuthenticateParameters params) =>
      throw UnimplementedError();

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async => null;

  @override
  Future<void> signOut(SignOutParams params) async {}
}

/// url_launcher, recording what it was asked to open.
class FakeLauncher extends UrlLauncherPlatform with MockPlatformInterfaceMixin {
  final opened = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    return true;
  }
}

void main() {
  late FakeSignIn platform;
  setUp(() {
    platform = FakeSignIn();
    GoogleSignInPlatform.instance = platform;
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('phone: Google sign-in grants Drive access and hands out tokens', () async {
    final auth = GoogleSignInAuth(serverClientId: 'web-client');
    expect(await auth.signedIn(), isFalse);
    expect(platform.serverClientId, 'web-client');
    await expectLater(auth.token(), throwsA(isA<NotSignedIn>()));
    await auth.signIn();
    expect(await auth.signedIn(), isTrue);
    expect(await auth.token(), startsWith('access-'));
    final stale = await auth.token();
    final fresh = await auth.token(refresh: true);
    expect(platform.cleared, [stale]); // the refused token is dropped first
    expect(fresh, isNot(stale));
    await auth.signOut();
    expect(platform.disconnected, isTrue);
    expect(await auth.signedIn(), isFalse);
  });

  test('phone: saying no is a failed sign-in', () async {
    platform.refused = true;
    await expectLater(
      GoogleSignInAuth(serverClientId: 'web-client').signIn(),
      throwsA(isA<SignInFailed>()),
    );
  });

  test('which sign-in a build gets', () {
    const keys = FlutterSecureStorage();
    expect(driveAuthFor(mobile: true, keys: keys, keySpace: 'n', webClientId: ''), isNull);
    expect(
      driveAuthFor(mobile: true, keys: keys, keySpace: 'n', webClientId: 'web'),
      isA<GoogleSignInAuth>(),
    );
    expect(driveAuthFor(mobile: false, keys: keys, keySpace: 'n', clientId: ''), isNull);
    expect(
      driveAuthFor(mobile: false, keys: keys, keySpace: 'n', clientId: 'id', clientSecret: 's'),
      isA<LoopbackAuth>(),
    );
    // This build was made without the client ids (they are never in the repo).
    expect(driveAuthFor(mobile: false, keys: keys, keySpace: 'n'), isNull);
  });

  test('desktop: the browser opens, the refresh token lives in the keystore', () async {
    final launcher = FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    final auth =
        driveAuthFor(
              mobile: false,
              keys: const FlutterSecureStorage(),
              keySpace: 'notelore-dev',
              clientId: 'id',
              clientSecret: 's',
            )!
            as LoopbackAuth;
    await auth.openBrowser(Uri.parse('https://accounts.google.com/x'));
    expect(launcher.opened, ['https://accounts.google.com/x']);
    await auth.saveRefreshToken('r');
    expect(await const FlutterSecureStorage().read(key: 'notelore-dev.google.refresh_token'), 'r');
    expect(await auth.readRefreshToken(), 'r');
    await auth.saveRefreshToken(null);
    expect(await auth.readRefreshToken(), isNull);
  });
}
