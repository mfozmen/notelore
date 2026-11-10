import 'package:flutter/material.dart';

const _regular = 'Phosphor';
const _fill = 'Phosphor Fill';
const _duotone = 'Phosphor Duotone';

/// A two-layer Phosphor glyph: the outline over its fill shape.
typedef Duotone = ({IconData line, IconData fill});

/// Every glyph the app draws, from the bundled Phosphor fonts: Regular
/// everywhere, Fill for a toggle's "on" state and Send, Duotone for the active
/// tab and empty screens. Code points are Phosphor 2.1's; one glyph has the same
/// one in every font, so the family alone picks Regular or Fill.
abstract final class AppIcons {
  static const add = IconData(0xe3d4, fontFamily: _regular);
  static const alarm = IconData(0xe006, fontFamily: _regular);
  static const archive = IconData(0xe00c, fontFamily: _regular);
  static const attach = IconData(0xe39a, fontFamily: _regular);
  static const back = IconData(0xe058, fontFamily: _regular);
  static const bolt = IconData(0xe2de, fontFamily: _regular);
  static const book = IconData(0xe0e6, fontFamily: _regular);
  static const brain = IconData(0xe74e, fontFamily: _regular);
  static const brokenImage = IconData(0xe7a8, fontFamily: _regular);
  static const build = IconData(0xe5d4, fontFamily: _regular);
  static const calendar = IconData(0xe7b4, fontFamily: _regular);
  static const chart = IconData(0xe150, fontFamily: _regular);
  static const chat = IconData(0xe166, fontFamily: _regular);
  static const check = IconData(0xe182, fontFamily: _regular);
  static const checked = IconData(0xe184, fontFamily: _fill);
  static const checklist = IconData(0xeadc, fontFamily: _regular);
  static const chevronLeft = IconData(0xe138, fontFamily: _regular);
  static const chevronRight = IconData(0xe13a, fontFamily: _regular);
  static const cleanup = IconData(0xec54, fontFamily: _regular);
  static const close = IconData(0xe4f6, fontFamily: _regular);
  static const cloud = IconData(0xe1aa, fontFamily: _regular);
  static const cloudDone = IconData(0xe1b0, fontFamily: _regular);
  static const cloudOff = IconData(0xe1b6, fontFamily: _regular);
  static const cloudUpload = IconData(0xe1ae, fontFamily: _regular);
  static const collapse = IconData(0xe13c, fontFamily: _regular);
  static const command = IconData(0xe1c4, fontFamily: _regular);
  static const contrast = IconData(0xe18c, fontFamily: _regular);
  static const copy = IconData(0xe1ca, fontFamily: _regular);
  static const cost = IconData(0xe78e, fontFamily: _regular);
  static const darkMode = IconData(0xe330, fontFamily: _regular);
  static const delete = IconData(0xe4a6, fontFamily: _regular);
  static const deleteForever = IconData(0xe4a8, fontFamily: _regular);
  static const done = IconData(0xe184, fontFamily: _regular);
  static const download = IconData(0xe20c, fontFamily: _regular);
  static const error = IconData(0xe4e2, fontFamily: _regular);
  static const event = IconData(0xe712, fontFamily: _regular);
  static const expand = IconData(0xe136, fontFamily: _regular);
  static const fileOpen = IconData(0xe256, fontFamily: _regular);
  static const fingerprint = IconData(0xe23e, fontFamily: _regular);
  static const folder = IconData(0xe24a, fontFamily: _regular);
  static const history = IconData(0xe1a0, fontFamily: _regular);
  static const image = IconData(0xe2ca, fontFamily: _regular);
  static const info = IconData(0xe2ce, fontFamily: _regular);
  static const insert = IconData(0xe090, fontFamily: _regular);
  static const insights = IconData(0xe154, fontFamily: _regular);
  static const key = IconData(0xe2d6, fontFamily: _regular);
  static const lightMode = IconData(0xe472, fontFamily: _regular);
  static const linkOff = IconData(0xe2e4, fontFamily: _regular);
  static const lock = IconData(0xe2fa, fontFamily: _regular);
  static const lockOpen = IconData(0xe306, fontFamily: _regular);
  static const login = IconData(0xe428, fontFamily: _regular);
  static const logout = IconData(0xe42a, fontFamily: _regular);
  static const menu = IconData(0xe2f0, fontFamily: _regular);
  static const mic = IconData(0xe326, fontFamily: _regular);
  static const micOn = IconData(0xe326, fontFamily: _fill);
  static const moreHoriz = IconData(0xe1fe, fontFamily: _regular);
  static const moreVert = IconData(0xe208, fontFamily: _regular);
  static const note = IconData(0xe23a, fontFamily: _regular);
  static const notifications = IconData(0xe0ce, fontFamily: _regular);
  static const notificationsOff = IconData(0xe0d4, fontFamily: _regular);
  static const notificationsOn = IconData(0xe5e8, fontFamily: _regular);
  static const openInNew = IconData(0xe5de, fontFamily: _regular);
  static const palette = IconData(0xe6c8, fontFamily: _regular);
  static const pattern = IconData(0xe1fc, fontFamily: _regular);
  static const person = IconData(0xe4c2, fontFamily: _regular);
  static const pin = IconData(0xe3e2, fontFamily: _regular);
  static const pinCode = IconData(0xe752, fontFamily: _regular);
  static const pinOn = IconData(0xe3e2, fontFamily: _fill);
  static const privacy = IconData(0xe40c, fontFamily: _regular);
  static const refresh = IconData(0xe036, fontFamily: _regular);
  static const replay = IconData(0xe038, fontFamily: _regular);
  static const restore = IconData(0xe038, fontFamily: _regular);
  static const schedule = IconData(0xe19a, fontFamily: _regular);
  static const search = IconData(0xe30c, fontFamily: _regular);
  static const send = IconData(0xe08e, fontFamily: _fill);
  static const settings = IconData(0xe270, fontFamily: _regular);
  static const share = IconData(0xeaf0, fontFamily: _regular);
  static const shield = IconData(0xe40a, fontFamily: _regular);
  static const sparkle = IconData(0xe6a2, fontFamily: _regular);
  static const stop = IconData(0xe46c, fontFamily: _fill);
  static const sync = IconData(0xe094, fontFamily: _regular);
  static const systemMode = IconData(0xe18e, fontFamily: _regular);
  static const tag = IconData(0xe478, fontFamily: _regular);
  static const textBigger = IconData(0xe3d4, fontFamily: _regular);
  static const textSize = IconData(0xe6ee, fontFamily: _regular);
  static const textSmaller = IconData(0xe32a, fontFamily: _regular);
  static const thumbDown = IconData(0xe48c, fontFamily: _regular);
  static const thumbDownOn = IconData(0xe48c, fontFamily: _fill);
  static const thumbUp = IconData(0xe48e, fontFamily: _regular);
  static const thumbUpOn = IconData(0xe48e, fontFamily: _fill);
  static const translate = IconData(0xe4a2, fontFamily: _regular);
  static const unchecked = IconData(0xe18a, fontFamily: _regular);
  static const update = IconData(0xe028, fontFamily: _regular);
  static const voice = IconData(0xeca8, fontFamily: _regular);
  static const volumeOff = IconData(0xe45a, fontFamily: _regular);
  static const volumeOn = IconData(0xe44a, fontFamily: _regular);
  static const warning = IconData(0xe4e0, fontFamily: _regular);
  static const web = IconData(0xe288, fontFamily: _regular);

  static const Duotone chatActive = (
    line: IconData(0xe167, fontFamily: _duotone),
    fill: IconData(0xe166, fontFamily: _duotone),
  );
  static const Duotone noteActive = (
    line: IconData(0xe23b, fontFamily: _duotone),
    fill: IconData(0xe23a, fontFamily: _duotone),
  );
  static const Duotone calendarActive = (
    line: IconData(0xe7b5, fontFamily: _duotone),
    fill: IconData(0xe7b4, fontFamily: _duotone),
  );
  static const Duotone personActive = (
    line: IconData(0xe4c3, fontFamily: _duotone),
    fill: IconData(0xe4c2, fontFamily: _duotone),
  );
  static const Duotone settingsActive = (
    line: IconData(0xe271, fontFamily: _duotone),
    fill: IconData(0xe270, fontFamily: _duotone),
  );
  static const Duotone chatEmpty = (
    line: IconData(0xe34d, fontFamily: _duotone),
    fill: IconData(0xe34c, fontFamily: _duotone),
  );
  static const Duotone noteEmpty = noteActive;
  static const Duotone archiveEmpty = (
    line: IconData(0xe00d, fontFamily: _duotone),
    fill: IconData(0xe00c, fontFamily: _duotone),
  );
  static const Duotone searchEmpty = (
    line: IconData(0xe30d, fontFamily: _duotone),
    fill: IconData(0xe30c, fontFamily: _duotone),
  );
  static const Duotone eventEmpty = (
    line: IconData(0xe713, fontFamily: _duotone),
    fill: IconData(0xe712, fontFamily: _duotone),
  );

  /// [icon]'s fill in the outline's colour, faint, under the outline.
  static Widget duo(Duotone icon, {double? size, Color? color}) => Stack(
    alignment: Alignment.center,
    children: [
      Opacity(
        opacity: 0.3,
        child: Icon(icon.fill, size: size, color: color),
      ),
      Icon(icon.line, size: size, color: color),
    ],
  );
}
