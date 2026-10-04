# Notelore mobile

The Android app of [Notelore](https://github.com/mfozmen/notelore) (iOS later), built with [Briefcase](https://briefcase.readthedocs.io/) and [Toga](https://toga.readthedocs.io/) on the shared core in `packages/core`. Plan and status: issue #48.

```bash
uvx --from briefcase==0.4.5 briefcase create android   # from apps/mobile
uvx --from briefcase==0.4.5 briefcase build android    # debug APK under build/notelore-mobile/android/gradle/app/build/outputs/apk/debug/
```
