# Provider wizard: connect a model, compare honestly, switch anytime

Date: 2026-10-18. The maintainer agreed this design in chat.

## Goal

A user with no model connected is guided to one in a few simple steps, and knows what each choice costs and where their notes go. The same wizard runs again from Settings to connect another model. Every connected model stays, so switching back is one tap. Notelore has no server of its own; every option is the user's own (a plan, a key, a local model).

## Decisions

- **Choose step: every option side by side**, as comparison cards. No questionnaire, no single default.
- **Switching keeps old connections.** Their keys and sign-ins stay in the keystore. Settings lists the connected models, switches with one tap and removes them one by one.
- **The on-device model is hidden until it is ready** (#227). It joins the Choose step as a card once it ships.

## Flow

The wizard is one full-screen route with four steps. It replaces `SetupScreen` and opens from:
- first run, after Google sign-in (`needsGoogle`), when no model is connected;
- Settings → Model → *Connect another model*;
- the chat's call to action when no model is connected.

1. **Choose.** One card per option this device can use today:
   - ChatGPT plan (OAuth);
   - free Gemini key;
   - your own key (Claude, OpenAI, Gemini);
   - Ollama (desktop only).

   Each card has the same five lines:
   - **Cost:** for example "Free", "Your ChatGPT Plus or Pro plan, no extra charge", "Pay per use, about $X per month for typical use".
   - **Privacy:** where the notes go, for example "Sent to OpenAI", "Google may use free-tier data", "Stays on this computer".
   - **Quality** and **Setup effort.**
   - **Best for:** for example "You have ChatGPT Plus or Pro".

   Cards for options already connected say so.
2. **Connect.** Steps specific to the chosen option:
   - **ChatGPT plan:**
     - One button. The browser hands back to the app (#301).
     - An account with no plan is told plainly, with a link to the Gemini option (#321).
   - **Key:**
     - Numbered steps and one tap to open the key page.
     - Back in the app, a key on the clipboard is recognised and offered.
     - It is checked at once (`Session.connect` validates by listing models).
     - Errors say what to do next, never a raw code (#302, `Strings.chatError`).
   - **Ollama:** checks that the server answers and lists the models it has; otherwise, says how to install and start it.
3. **Try.** One real turn with the connected model, using a fixed short prompt and no tools, is shown as it arrives. A failure goes back to Connect with the reason.
4. **Done.** One line on what is connected and where the notes go, then into the chat.

## Settings → Model

- A list of connected models: name, provider, and a mark on the active one.
  - Tap a row to switch.
  - Each row has a remove action that deletes its key or signs out of it.
- *Connect another model* opens the wizard.
- *Log out* stays for the Google account only. It no longer doubles as "change model".

## No model connected

The chat stays usable for browsing. In place of the message box sits a call to action, "Connect a model to start", which opens the wizard. Notes, search, export and sync keep working.

## Data

There is no new store.
- Keys already live per provider in the keystore (`<keySpace>.<provider>.api_key`). The ChatGPT plan has its own sign-in, and Ollama needs no key.
- **Connected list:** derived. A provider is connected if its key is present, the plan is signed in, or Ollama is enabled on this desktop.
- **Active one:** stays in `settings.json` (`provider`, `model`), as today. It is synced through Drive as today.
- **New session methods:**
  - `connections()`: the connected providers;
  - `switchTo(spec)`: the stored key, the last model and `_use`;
  - `disconnect(spec)`: delete that key or sign out. If it was active, there is no model until another is chosen.
- `logout()` keeps its meaning: Google sign-out plus everything.
- **Migration:** none needed. A user's existing key or sign-in simply shows as connected.

## Errors

- Every step can go back, and leaving the wizard changes nothing that was not finished.
- Validation and network errors use the friendly strings (`Strings.chatError` / `signInProblem`).
- The clipboard is read only on return to the app, and only to offer a key. It is never stored unless the user accepts.

## Testing

- Session tests: `connections`, `switchTo`, `disconnect`, including the active one and the keystore losing a key.
- Widget tests: each step on phone and desktop, EN/TR; first run, the Settings entry and the chat call to action; the back paths; a no-plan ChatGPT account; a bad key.
- Design: the design skills (`mobile-app-ui-design`, `ui-ux-pro-max`, flutter layout skills) before building each step, and the ui-reviewer after. Before/after off-screen renders go in each PR.
- README: the setup and switching sections are rewritten.

## Out of scope

- The on-device model card (it comes with #227).
- New providers.
- Usage and cost pages (#294).
