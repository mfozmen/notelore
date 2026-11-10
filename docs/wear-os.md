# The Wear OS app

The watch app is a native Kotlin + Compose for Wear OS app (Flutter on Wear OS is not worth
its limits here). It has no key, model or notes of its own: it talks to the phone app over the
Wearable Data Layer, and the phone runs the chat turn.

## Where it lives

`apps/notelore/android/wear/`, a second Gradle module next to the phone's `:app`. One Gradle
build holds both, so:

- both use the same application id (`io.github.mfozmen.notelore`) and the same signing: the
  debug key on a developer machine, the release key from the same `NOTELORE_ANDROID_*`
  environment in a release. The Data Layer only pairs apps that share both.
- CI builds it with the Gradle wrapper `flutter build apk` already set up:
  `./gradlew :wear:assembleDebug :wear:testDebugUnitTest` in `apps/notelore/android`.

The APK lands in `apps/notelore/build/wear/outputs/apk/debug/wear-debug.apk`.

## The Data Layer seam

- Watch: `DataLayer` (`wear/src/main/kotlin/.../DataLayer.kt`), an interface over sending a text
  message on a path and listening for messages. `MessageClientDataLayer` is the thin real one
  over Play services' `MessageClient`; JVM unit tests use `FakeDataLayer`.
- Phone: `WatchLink` (`apps/notelore/lib/src/watch_link.dart`) over the method channel
  `io.github.mfozmen.notelore/watch`; `MainActivity.kt` holds the `MessageClient` glue. Dart
  tests fake the channel.

## The Wear OS emulator

`tool/wear_emulator.sh` drives a round Wear OS 5 (API 34) AVD, `notelore_wear_api34`, on port
5560. Every adb call passes `-s emulator-5560`, so the phone AVD (`notelore_latency_api35`,
`emulator-5554`) is never touched, and both can run at once. Never sign in to any account on it.

```bash
bash tool/wear_emulator.sh create            # download the system image, create the AVD (once)
bash tool/wear_emulator.sh start             # headless; returns once booted
(cd apps/notelore && flutter build apk --debug)   # sets up the Gradle wrapper
(cd apps/notelore/android && ./gradlew :wear:assembleDebug)
bash tool/wear_emulator.sh install           # install and open the watch app
bash tool/wear_emulator.sh shot wear.png     # screenshot
bash tool/wear_emulator.sh tap 227 227       # tap the middle of the 454x454 screen
bash tool/wear_emulator.sh stop
```

On Windows the script finds the SDK in `%LOCALAPPDATA%\Android\Sdk`; elsewhere set
`ANDROID_HOME` if it is not in the default place.

The emulator has no paired phone, so the Data Layer sees no node there: `send` answers false.
The phone ↔ watch path is checked on a real watch.

## A real watch (Galaxy Watch6 Classic)

Install a debug build over Wi-Fi ADB. The watch and the PC must be on the same Wi-Fi.

1. On the watch: **Settings → About watch → Software information**, tap **Software version**
   seven times. **Developer options** appears in Settings.
2. **Settings → Developer options**: turn on **ADB debugging** and **Wireless debugging**
   (it asks to allow; accept).
3. In **Wireless debugging**, tap **Pair new device**. The watch shows an IP address, a port and
   a six-digit code. On the PC:

   ```bash
   adb pair <ip>:<pairing port>          # enter the code
   ```

4. Back in **Wireless debugging**, the watch shows its IP address and a second port (the
   connection port, not the pairing one):

   ```bash
   adb connect <ip>:<port>
   adb devices                           # the watch shows as <ip>:<port>
   adb -s <ip>:<port> install -r apps/notelore/build/wear/outputs/apk/debug/wear-debug.apk
   ```

The phone app must be a debug build from the same machine too, so both carry the same debug
key; a release phone app and a debug watch app do not pair. Turn **Wireless debugging** off
when done: it drains the battery.
