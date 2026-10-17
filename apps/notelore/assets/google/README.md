# Google "G" logo

`g_light.png` and `g_dark.png` are Google's official "G" logo, cut unchanged
(the logo's own 20x20 area, at 4x) from the icon-only sign-in button assets of
Google's sign-in branding guidelines:
https://developers.google.com/identity/branding-guidelines

Their backgrounds are the guidelines' button fills (white, #131314), which the
Sign in with Google button in `lib/src/setup.dart` uses too. Use them only in
that button, per the guidelines.
