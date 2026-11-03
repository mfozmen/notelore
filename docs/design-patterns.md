# Design patterns in Notelore

Notelore uses a few patterns on purpose, in Dart's own forms. This page lists them, shows where each one lives, and says when a new one is worth adding. The rules in [`CLAUDE.md`](../CLAUDE.md) come first. A pattern never weakens an invariant there: Markdown is the truth, writes are narrow, and every change can be undone.

## When to reach for a pattern

- **The variation must already exist.** Use a pattern when two or more real variants exist today, or when one rule is copied to two or more places that must change together. An interface with one implementation, or a factory with one product, is only an extra layer.
- **Pick the smallest Dart form that works.**
  - One operation that varies: a function `typedef` (`Transport`, `Resolver`, `Rename`).
  - Several operations that vary together: an `abstract interface class`.
  - A closed set of cases the compiler must check: a `sealed class` with an exhaustive `switch`.
  - Small data without behaviour: a record.
- **Branch in one place.** A `switch` on a kind, a platform or a provider name belongs in one place, usually the factory that builds the strategy. If the same switch shows up a second time, it is a strategy waiting to be extracted.
- **Inject what crosses a boundary.** Network, filesystem moves, clocks, processes and platform plugins are injected, so tests run against fakes with no network (CLAUDE.md, *No network in tests*).

## Patterns in use

| Pattern | Where | Why here |
|---|---|---|
| **Strategy** (interface) | `LlmProvider` (`providers/base.dart`): Anthropic, OpenAI, Gemini, DeepSeek, Ollama, ChatGPT and the device model | The agent loop is the same for every model; only the wire format changes. |
| **Strategy** (interface) | `Remote` (`sync/engine.dart`): `DriveRemote`, and the in-memory Drive in the tests | One sync pass against any store. Drive is a detail of the engine. |
| **Strategy** (interface) | `OAuthSignIn` / `DriveAuth`, `ReminderCalendar`, `LocalEngine`, `DeviceAuth`, `ReminderNotifier` | Each has a platform or vendor implementation and a test fake. |
| **Strategy** (function) | `Transport` (`providers/http.dart`), `Resolver` and `Ask` (`sync/`), `Rename`, `Pause` and `MoveFile` (`store/`) | A single operation, so a function type is enough and a fake is one lambda. |
| **Factory** | `createProvider` (`providers/providers.dart`), `updaterFor` (`apps/notelore/lib/src/update.dart`), `keysFor` (`keychain_vault.dart`) | The one place that turns a name or a platform into a strategy. |
| **Decorator** | `MeteredProvider` (`usage.dart`) wraps any `LlmProvider` to count tokens. `UntilWrite` (`eval.dart`) stops a turn at its first write. `KeychainVault` wraps `FlutterSecureStorage` | Adds behaviour without touching the providers or the plugin. |
| **Facade** | `Toolbox` (`tools.dart`) over the store and index | The model sees narrow tools. The store keeps its full API for the app. |
| **Command** | The agent's tools: a name, a JSON schema and a handler (`tools.dart`) | The model asks for an action by name. The toolbox checks it and runs it. |
| **Sealed union** | `NoteEntry` (`store/format.dart`), `MergePart` (`sync/merge.dart`) | The parser and the merge must handle every case. The compiler checks it. |
| **Observer** | `Session` and `VoiceMode` are `ChangeNotifier`s that the screens listen to | The screens rebuild when shared state changes. They never poll. |
| **Derived state** | `NoteIndex` (`store/index.dart`) and the sync manifest | Each is rebuilt from the Markdown files. Deleting one loses nothing (invariant 1). |

## Adding one

1. **Name the variation:** say what differs (a platform, a provider, a note kind) and list the places that branch on it today.
2. **Test first:** write one test per variant through the new seam (TDD), using the fakes the tests already have.
3. **Branch in one place:** move each branch into its variant. The only `switch` left is in the factory.
4. **Keep behaviour the same in the refactor PR:** the existing tests pass unchanged, except where they build the object. Changes in behaviour go in their own PR.
5. **Update this table:** list the new pattern in the same PR.

## Smells that ask for one

- **A repeated switch:** the same `switch`, or an `if (system == …)` chain, on one key in several methods. The updater's platform branches are an example (#655).
- **Parallel lists:** several lists or maps keyed by the same names that must be edited together, such as a tool's schema, its handler, its slim wording and whether it writes.
- **A class with several jobs:** one that holds unrelated jobs and their state, so a change to one job retests the rest.
- **Near-copies:** two or more copies of a sequence that differ in one step. That one step is the strategy, or the hook of a template method.
