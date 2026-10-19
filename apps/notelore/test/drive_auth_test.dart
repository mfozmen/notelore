import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:notelore/src/drive_auth.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'support.dart' show FakeAuth, FakeAwake, FakeLauncher;

/// The Google sign-in plugin, in memory: one account that has or has not
/// granted Drive access.
class FakeSignIn extends GoogleSignInPlatform with MockPlatformInterfaceMixin {
  var granted = false;
  var refused = false;
  var issued = 0;
  final cleared = <String>[];
  var disconnected = false;
  String? serverClientId;

  /// The scopes each token request named.
  final asked = <List<String>>[];

  @override
  Future<void> init(InitParameters params) async => serverClientId = params.serverClientId;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async {
    asked.add(params.request.scopes);
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

void main() {
  planTests();
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
    expect(platform.asked, everyElement(driveScope.split(' ')));
  });

  test("phone: the calendar's grant asks for the calendar scope alone (#432)", () async {
    final auth = calendarAuthFor(
      mobile: true,
      keys: const FlutterSecureStorage(),
      keySpace: 'n',
      webClientId: 'web',
    )!;
    await auth.signIn();
    expect(platform.asked.last, [calendarScope]);
    // Signing the calendar out never revokes Drive: one account, one grant to disconnect.
    await auth.token();
    await auth.signOut();
    expect(platform.disconnected, isFalse);
    expect(platform.cleared, hasLength(1));
    await calendarAuthFor(
      mobile: true,
      keys: const FlutterSecureStorage(),
      keySpace: 'n',
      webClientId: 'web',
    )!.signOut();
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
    expect(calendarAuthFor(mobile: false, keys: keys, keySpace: 'n'), isNull);
    expect(calendarAuthFor(mobile: true, keys: keys, keySpace: 'n', webClientId: ''), isNull);
  });

  test("desktop: the calendar's grant has its own scope and refresh token (#432)", () async {
    final auth =
        calendarAuthFor(
              mobile: false,
              keys: const FlutterSecureStorage(),
              keySpace: 'notelore-dev',
              clientId: 'id',
              clientSecret: 's',
            )!
            as LoopbackAuth;
    expect(auth.scope, calendarScope);
    await auth.saveRefreshToken('c');
    // Drive's token is a different entry: switching the calendar never touches Drive.
    expect(
      await const FlutterSecureStorage().read(key: 'notelore-dev.google.calendar.refresh_token'),
      'c',
    );
    expect(
      await const FlutterSecureStorage().read(key: 'notelore-dev.google.refresh_token'),
      isNull,
    );
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

void planTests() {
  test('a phone keeps the app awake while a sign-in waits, and lets go after (#409)', () async {
    final awake = FakeAwake();
    final inner = FakeAuth();
    final held = AwakeSignIn(inner, awake);
    await held.signIn();
    expect(awake.calls, ['hold', 'release']);
    expect(await held.signedIn(), isTrue);
    expect(await held.token(), 'token');
    // A failed sign-in lets go too, and its error is the one that shows.
    inner.failSignIn = Exception('refused');
    await expectLater(held.signIn(), throwsA(isA<Exception>()));
    expect(awake.calls, ['hold', 'release', 'hold', 'release']);
    await held.signOut();
    expect(inner.signedOut, isTrue);
    // The phone's ChatGPT sign-in is held; the desktop's is not.
    const keys = FlutterSecureStorage();
    expect(
      chatGptAuthFor(mobile: true, keys: keys, keySpace: 'n', awake: awake),
      isA<AwakeSignIn>(),
    );
    expect(chatGptAuthFor(mobile: false, keys: keys, keySpace: 'n'), isA<ChatGptAuth>());
  });

  test('the ChatGPT plan sign-in, on phones too, kept in the keystore', () async {
    const keys = FlutterSecureStorage();
    final launcher = FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    // A phone opens the page inside the app, which keeps it running for the
    // loopback answer; the desktop uses the browser.
    final phone =
        (chatGptAuthFor(mobile: true, keys: keys, keySpace: 'n') as AwakeSignIn).inner
            as ChatGptAuth;
    await phone.openBrowser(Uri.parse('https://auth.openai.com/p'));
    expect(launcher.modes.single, PreferredLaunchMode.inAppBrowserView);
    final auth = chatGptAuthFor(mobile: false, keys: keys, keySpace: 'notelore-dev') as ChatGptAuth;
    await auth.openBrowser(Uri.parse('https://auth.openai.com/x'));
    expect(launcher.opened.last, 'https://auth.openai.com/x');
    expect(launcher.modes.last, PreferredLaunchMode.externalApplication);
    await auth.write('client_id', 'oaiapp_1');
    expect(await keys.read(key: 'notelore-dev.chatgpt.client_id'), 'oaiapp_1');
    expect(await auth.read('client_id'), 'oaiapp_1');
    await auth.write('client_id', null);
    expect(await auth.read('client_id'), isNull);
  });

  testWidgets('phone: the browser comes back to the app, then the code is exchanged (#300, #301)', (
    tester,
  ) async {
    const keys = FlutterSecureStorage();
    final phone =
        (chatGptAuthFor(mobile: true, keys: keys, keySpace: 'n') as AwakeSignIn).inner
            as ChatGptAuth;
    expect(phone.returnTo, Uri.parse('notelore://signed-in'));
    // Behind the sign-in tab: waits until Notelore is in front again.
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.paused);
    var back = false;
    unawaited(phone.backInApp!().then((_) => back = true));
    await tester.pump();
    expect(back, isFalse);
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(back, isTrue);
    // Already in front (the user came back before the answer): no wait.
    await phone.backInApp!();
    // The desktop's browser is another app: nothing to wait for or return to.
    final desktop = chatGptAuthFor(mobile: false, keys: keys, keySpace: 'n') as ChatGptAuth;
    expect(desktop.backInApp, isNull);
    expect(desktop.returnTo, isNull);
  });
}
