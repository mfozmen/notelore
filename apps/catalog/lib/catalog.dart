import 'package:flutter/material.dart';
import 'package:notelore/src/app.dart' show Home;
import 'package:notelore/src/chat.dart' show FieldDecoration, Orb;
import 'package:notelore/src/empty_state.dart';
import 'package:notelore/src/icons.dart';
import 'package:notelore/src/mark.dart';
import 'package:notelore/src/note_view.dart' show NotePage;
import 'package:notelore/src/schemes.dart';
import 'package:notelore/src/section_label.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore/src/settings.dart' show SettingsScreen;
import 'package:notelore/src/soft.dart';
import 'package:notelore/src/strings.dart';
import 'package:notelore/src/theme.dart';
import 'package:notelore_core/notelore_core.dart' show NoteInfo;
import 'package:widgetbook/widgetbook.dart';

/// The catalog's knobs: Kil by day and Orman by night, text at 1x, 1.5x and 2x,
/// and the screens the design is checked on.
final catalogAddons = <WidgetbookAddon>[
  MaterialThemeAddon(
    themes: [
      WidgetbookTheme(name: 'Kil (light)', data: noteloreTheme(Brightness.light)),
      WidgetbookTheme(name: 'Orman (dark)', data: noteloreTheme(Brightness.dark)),
    ],
  ),
  TextScaleAddon(min: 1, max: 2, divisions: 2),
  ViewportAddon(catalogViewports),
];

/// The screens every design is checked on.
const catalogViewports = [
  ViewportData(
    name: 'Galaxy S23 Ultra (412x915)',
    width: 412,
    height: 915,
    pixelRatio: 3.5,
    platform: TargetPlatform.android,
  ),
  ViewportData(
    name: 'Small phone (360x640)',
    width: 360,
    height: 640,
    pixelRatio: 2,
    platform: TargetPlatform.android,
  ),
  ViewportData(
    name: 'Desktop (1280x800)',
    width: 1280,
    height: 800,
    pixelRatio: 1,
    platform: TargetPlatform.windows,
  ),
];

/// The main screens by name, each built on a session; the goldens render the same ones.
final catalogScreens = <String, Widget Function(BuildContext context, Session session)>{
  'Chat': (_, session) => Home(session),
  'Notes': (_, session) => Home(session, tab: 1),
  'Note page': (_, session) => NotePage(session, _shed(session), session.readNote(_shed(session))),
  'Calendar': (_, session) => Home(session, tab: 2),
  'About me': (_, session) => Home(session, tab: 3),
  // Settings is in the phone's menu, and a tab of its own on a wide window.
  'Settings': (context, session) => MediaQuery.sizeOf(context).width >= Layout.wide
      ? Home(session, tab: 4)
      : SettingsScreen(session),
};

NoteInfo _shed(Session session) =>
    session.listNotes().firstWhere((note) => note.slug == 'garden-shed');

List<WidgetbookNode> catalogDirectories(Session session) => [
  WidgetbookCategory(
    name: 'Rules',
    children: [
      WidgetbookComponent(
        name: 'Design language',
        useCases: [WidgetbookUseCase(name: 'Rules', builder: (_) => const RulesPage())],
      ),
    ],
  ),
  WidgetbookCategory(name: 'Components', children: _components),
  WidgetbookCategory(
    name: 'Screens',
    children: [
      for (final MapEntry(:key, :value) in catalogScreens.entries)
        WidgetbookComponent(
          name: key,
          useCases: [
            WidgetbookUseCase(name: 'Fake notes', builder: (context) => value(context, session)),
          ],
        ),
    ],
  ),
];

final _strings = EnglishStrings();

WidgetbookComponent _component(String name, WidgetBuilder builder) => WidgetbookComponent(
  name: name,
  useCases: [
    WidgetbookUseCase(
      name: 'Default',
      builder: (context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.m),
            child: builder(context),
          ),
        ),
      ),
    ),
  ],
);

final _components = [
  WidgetbookComponent(
    name: 'Floating nav',
    useCases: [
      WidgetbookUseCase(
        name: 'Default',
        builder: (context) => Scaffold(
          extendBody: true,
          body: const SizedBox.expand(),
          bottomNavigationBar: SoftNavBar(
            destinations: [
              (AppIcons.chat, AppIcons.chatActive, _strings.chat),
              (AppIcons.note, AppIcons.noteActive, _strings.notes),
              (AppIcons.calendar, AppIcons.calendarActive, _strings.calendar),
              (AppIcons.person, AppIcons.personActive, _strings.aboutMeSection),
            ],
            selected: context.knobs.int.slider(label: 'Selected', max: 3, initialValue: 0),
            onSelected: (_) {},
          ),
        ),
      ),
    ],
  ),
  _component(
    'Buttons',
    (context) => Wrap(
      spacing: Gap.s,
      runSpacing: Gap.s,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton(onPressed: () {}, child: const Text('Connect')),
        OutlinedButton(onPressed: () {}, child: const Text('Later')),
        TextButton(onPressed: () {}, child: const Text('Open the note')),
        const FilledButton(onPressed: null, child: Text('Disabled')),
        softBack(context, onPressed: () {}),
        IconButton(
          style: softRound(Theme.of(context).colorScheme),
          tooltip: 'Search',
          onPressed: () {},
          icon: const Icon(AppIcons.search),
        ),
      ],
    ),
  ),
  _component(
    'Cards',
    (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: ListTile(
            leading: const Icon(AppIcons.note),
            title: const Text('Garden Shed'),
            subtitle: const Text('Updated 28 September'),
            onTap: () {},
          ),
        ),
        const SizedBox(height: Gap.m),
        HotCard(
          child: Padding(
            padding: const EdgeInsets.all(Gap.m),
            child: Builder(
              builder: (context) {
                final tokens = Theme.of(context).extension<NoteloreTokens>()!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ROOF', style: tokens.label.copyWith(color: tokens.hotLabel)),
                    Text(
                      'Corrugated metal',
                      style: Theme.of(context).textTheme.titleLarge!
                          .copyWith(color: tokens.hotValue),
                    ),
                    Text(
                      'Cheaper, and it outlasts shingles.',
                      style: TextStyle(color: tokens.hotReason),
                    ),
                    TextButton(onPressed: () {}, child: const Text('Garden Shed')),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    ),
  ),
  _component(
    'Switch',
    (context) => SoftSwitchTile(
      title: const Text('Reminders'),
      subtitle: const Text('A notification at the time'),
      value: context.knobs.boolean(label: 'On', initialValue: true),
      onChanged: context.knobs.boolean(label: 'Enabled', initialValue: true) ? (_) {} : null,
    ),
  ),
  _component(
    'Radio',
    (context) => Column(
      children: [
        for (final (label, selected) in [('System', true), ('Light', false), ('Dark', false)])
          ListTile(
            leading: SoftRadio(selected: selected),
            title: Text(label),
            onTap: () {},
          ),
      ],
    ),
  ),
  _component(
    'Checkbox',
    (context) => Column(
      children: [
        CheckboxListTile(value: false, onChanged: (_) {}, title: const Text('Paint the door')),
        CheckboxListTile(value: true, onChanged: (_) {}, title: const Text('Level the ground')),
      ],
    ),
  ),
  _component(
    'Chips',
    (context) => Wrap(
      spacing: Gap.s,
      runSpacing: Gap.s,
      children: [
        FilterChip(label: const Text('Projects'), selected: true, onSelected: (_) {}),
        FilterChip(label: const Text('Topics'), selected: false, onSelected: (_) {}),
        ActionChip(label: const Text('Which roof did we pick?'), onPressed: () {}),
      ],
    ),
  ),
  _component(
    'Snackbar',
    (context) => FilledButton(
      onPressed: () =>
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Moved to the archive'))),
      child: const Text('Show a snackbar'),
    ),
  ),
  _component(
    'Pickers',
    (context) => Wrap(
      spacing: Gap.m,
      runSpacing: Gap.m,
      children: [
        DatePickerDialog(
          initialDate: DateTime(2026, 9, 30),
          firstDate: DateTime(2026),
          lastDate: DateTime(2027),
        ),
        const TimePickerDialog(initialTime: TimeOfDay(hour: 9, minute: 30)),
      ],
    ),
  ),
  _component(
    'Section labels',
    (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Label(_strings.settings),
        SectionLabel('Coming up', strings: _strings),
        SectionLabel('Late', strings: _strings, late: true),
      ],
    ),
  ),
  _component(
    'Mic orb',
    (context) => Orb(
      IconButton(
        tooltip: 'Talk',
        icon: const Icon(AppIcons.mic, color: Colors.white),
        onPressed: () {},
      ),
    ),
  ),
  _component('Message field', (context) => const _Field()),
  _component(
    'Empty state',
    (context) => EmptyState(
      icon: AppIcons.noteEmpty,
      title: 'No notes yet',
      hint: 'Tell the assistant something and it becomes a note.',
      actions: [FilledButton(onPressed: () {}, child: const Text('Start in the chat'))],
    ),
  ),
  _component('Mark', (context) => const NoteloreMark()),
];

/// The chat's message field: the soft, sunken capsule with its edge.
class _Field extends StatelessWidget {
  const _Field();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: FieldDecoration(
        color: colors.surfaceContainerHighest,
        edge: BorderSide(color: colors.outlineVariant),
        radius: Radii.field,
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: Gap.m),
        child: TextField(
          decoration: InputDecoration(
            hintText: 'Tell me something…',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
    );
  }
}

/// The first page: the rules every screen follows.
class RulesPage extends StatelessWidget {
  const RulesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    Widget heading(String title) => Padding(
      padding: const EdgeInsets.only(top: Gap.l, bottom: Gap.s),
      child: Label(title),
    );
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(Gap.m),
        children: [
          Text('Notelore design language', style: text.headlineMedium),
          const SizedBox(height: Gap.s),
          Text(
            'Kil by day, Orman by night. Spacing from Gap, widths from Layout, '
            'colours from the theme, never hard-coded.',
            style: text.bodyMedium,
          ),
          heading('Colours'),
          for (final (name, scheme) in [('Kil (day)', kil), ('Orman (night)', orman)]) ...[
            Text(name, style: text.titleMedium),
            const SizedBox(height: Gap.xs),
            Wrap(
              spacing: Gap.s,
              runSpacing: Gap.s,
              children: [
                for (final (role, color, on) in [
                  ('primary', scheme.primary, scheme.onPrimary),
                  ('secondary', scheme.secondary, scheme.onSecondary),
                  ('tertiary', scheme.tertiary, scheme.onTertiary),
                  ('surface', scheme.surface, scheme.onSurface),
                  ('container', scheme.surfaceContainerHighest, scheme.onSurface),
                  ('outline', scheme.outlineVariant, scheme.onSurface),
                  ('error', scheme.error, scheme.onError),
                ])
                  _Swatch(role, color, on),
              ],
            ),
            const SizedBox(height: Gap.m),
          ],
          heading('Type'),
          Text('Fraunces 600: titles', style: text.headlineSmall),
          Text('Plus Jakarta Sans: everything you read', style: text.bodyLarge),
          Text('JetBrains Mono: small labels', style: theme.extension<NoteloreTokens>()!.label),
          heading('Spacing (Gap)'),
          for (final (name, gap) in [('xs', Gap.xs), ('s', Gap.s), ('m', Gap.m), ('l', Gap.l)])
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.xs),
              child: Row(
                children: [
                  SizedBox(width: 32, child: Text(name)),
                  Container(width: gap, height: Gap.m, color: theme.colorScheme.primary),
                  const SizedBox(width: Gap.s),
                  Text('${gap.toInt()} dp'),
                ],
              ),
            ),
          heading('The orb'),
          Row(
            children: [
              Orb(
                IconButton(
                  tooltip: 'Talk',
                  icon: const Icon(AppIcons.mic, color: Colors.white),
                  onPressed: () {},
                ),
              ),
              const SizedBox(width: Gap.m),
              const Expanded(child: Text('44 dp in a 48 dp slot; the one accent fill.')),
            ],
          ),
          heading('The soft card'),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(Gap.m),
              child: Text('Radius 18, a hairline edge, no shadow by day.'),
            ),
          ),
          heading('Phosphor weights'),
          Row(
            spacing: Gap.l,
            children: [
              const _Glyph('Regular', Icon(AppIcons.note)),
              const _Glyph('Fill', Icon(AppIcons.checked)),
              _Glyph(
                'Duotone',
                Stack(
                  children: [
                    Icon(
                      AppIcons.noteActive.fill,
                      color: theme.colorScheme.primary.withValues(alpha: .3),
                    ),
                    Icon(AppIcons.noteActive.line, color: theme.colorScheme.primary),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.role, this.color, this.on);

  final String role;
  final Color color;
  final Color on;

  @override
  Widget build(BuildContext context) => Container(
    width: 96,
    height: 56,
    padding: const EdgeInsets.all(Gap.s),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(Radii.chip),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Text(role, style: TextStyle(color: on, fontSize: 12)),
  );
}

class _Glyph extends StatelessWidget {
  const _Glyph(this.name, this.icon);

  final String name;
  final Widget icon;

  @override
  Widget build(BuildContext context) => Column(spacing: Gap.xs, children: [icon, Text(name)]);
}
