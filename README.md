# Aster

**A personal AI companion that lives in your Mac's notch.** Aster talks with you, picks the right expert for each request, does the work in your apps and keeps your day connected. It runs on your own OpenAI or Claude key, with the model you choose.

Native Swift/SwiftUI for macOS 14+, with an iPhone remote app and an end-to-end encrypted relay. This is a development preview, not a notarized release.

## What Aster does

- **Lives in the notch.** At rest Aster blends into the MacBook notch (top center on other displays). Hover it to open a compact chat; while Aster listens, thinks or speaks the island widens into a live activity. A floating mascot is available instead.
- **One chat, nine modes.** Auto picks the right mode for every request and switches as the conversation moves: Study, Builder, Founder, Research, Finance, Growth, Content and Personal. You can also pin a mode.
- **Proactive.** Every answer ends with up to three next steps as buttons. Tap one, or just say "yes", and Aster does it. When a mission it started finishes, Aster comes back to the chat with what is ready.
- **Acts on your Mac.** "Open Numbers and make a budget for this month": Aster operates your apps, shows every step and stops to ask before anything that sends, buys, deletes or publishes. Press Esc to stop it.
- **Sees what you see.** Toggle the eye and your next question goes with a screenshot (Aster's own windows excluded). ⌥⌘K opens *By your side*, which explains your screen with drawn marks.
- **Talks.** Press ⌥Space anywhere, speak and pause. Recognition runs on the Mac when the language allows; answers can be read aloud.
- **Your day, connected.** Reads Apple Mail (and opens drafts for you to send, never sends), reads and creates calendar events, reminders and notes. Everything is read on your Mac through Apple's own apps.
- **Missions and startups.** Longer work runs as a mission in the right mode. "I want to start a note-sharing startup for students" kicks off every department in parallel: strategy, market research with sources, product, growth, finance and legal, plus a seven-day task list. Nothing is published, hired, paid or sent.
- **Projects.** A startup, a degree, a channel, a research question or something personal: each project has its own chat with Aster, its own team of agents (Auto picks among them), and its own goal, tasks, memory and missions. Templates bring the right team and the first useful actions, like a study plan or the startup kickoff.
- **Memory, tasks and routines.** A memory you can read and edit, local tasks and scheduled routines.
- **From your iPhone.** Aster Remote links to your Mac with a private QR code: chat, follow missions and, if you allow it, view and control the screen. The relay never sees your keys or your conversations.

## Bring your own AI

No API key is included, and none ever leaves your Mac except in requests to the provider that issued it. The first launch walks you through it: choose **Claude** (Anthropic) or **OpenAI**, paste your key, pick a model from those your account can use. Keys are stored in the macOS Keychain; you can switch provider or model at any time in Settings → Connections.

| | Claude | OpenAI |
| --- | --- | --- |
| Quick chat with Aster's tools and web search | ✓ | ✓ |
| Operating the Mac and questions about your screen | ✓ | ✓ |
| Missions | Run from this Mac; the deliverable is written in the answer | Hosted agent workspace that writes files and runs code |
| Spoken answers | macOS voices (OpenAI's natural voices if an OpenAI key is also saved) | Natural voices or macOS voices |

Claude is called through the Messages API (`anthropic-version: 2026-10-21`) with streaming, tool use, images and server-side web search; OpenAI through the Responses and Agents APIs.

## Built to be safe

Safety is enforced in code, not left to the model:

- Before every click, key or text on the Mac, Aster reads the real control under the cursor with Accessibility. Send, buy, pay, delete, publish, sign, accept and similar steps pause for your permission. Passwords, card numbers and API keys are never typed; Terminal, Keychain Access and System Settings are off limits.
- A conversation that read mail, notes, calendars, the web or your screen may contain instructions written by someone else. In those conversations, operating the Mac or starting a mission asks you first, showing the exact action, and no memories are saved.
- Links in answers only open web and mail addresses. Tasks started from the iPhone never approve sensitive steps.
- The iPhone link is encrypted end to end (AES-GCM, HKDF-derived keys, replay protection); the relay rate-limits new rooms.

## Build and run

Requires Xcode 26 or later (macOS 26 SDK). `outputs/Aster-macOS` is a Swift package: the `Aster` executable compiles `Sources/` and `Shared/`, and `AsterTests` covers `Tests/`. From the repository root:

```sh
zsh outputs/Aster-macOS/run.sh     # incremental debug build, bundled, signed and opened
zsh outputs/Aster-macOS/test.sh    # all XCTest suites (accepts swift test arguments, e.g. --filter ClaudeTests)
zsh outputs/Aster-macOS/build.sh   # release Aster.app; ASTER_ARCHS="arm64 x86_64" for a universal build
```

The tests use recorded fixtures: they need no key and spend nothing. Open `outputs/Aster-macOS/Package.swift` in Xcode to edit and run them, but launch the app with `run.sh`: only the bundle that `build.sh` assembles has the Info.plist, resources and stable signature that macOS permissions need. To debug, use Xcode → Debug → Attach to Process → Aster. Debug builds accept a local `ws://` relay; release builds require `wss://`.

The development signer generates its own private local identity, excluded by `.gitignore`. Public distribution needs your own Apple Developer ID certificate and notarization.

**iPhone:** open `outputs/Aster-iPhone/AsterRemote.xcodeproj` and set your own signing team and bundle identifier (or `ASTER_APPLE_TEAM` and `ASTER_IOS_BUNDLE_ID`). Requires iOS 17+.

**Relay:** Node 24+, pnpm 11.19.0. See [the relay guide](outputs/Aster-Relay/README.md). It is verified as one persistent instance; it needs shared coordination before running on several instances.

## Repository

| Folder | Contents |
| --- | --- |
| `outputs/Aster-macOS` | The macOS app: sources, shared remote protocol, assets, localization (Spanish and English) and tests. |
| `outputs/Aster-iPhone` | Aster Remote for iPhone (SwiftUI). Keep it next to Aster-macOS. |
| `outputs/Aster-Relay` | Encrypted WebSocket relay, tests and Dockerfile. |
| `outputs/aster` | The original web prototype. Copy `.env.example` to a private `.env.local` with your own key; it is used server-side only. |
| `archive` | Earlier source checkpoints, development helpers and the web prototype's history. |

## Status

Working in this preview: everything above on Apple Silicon, with automated tests for the chat providers, projects, tools, safety policy, island layout, voice input, remote protocol and relay. Still unfinished: Developer ID signing and notarization, the iPhone app on TestFlight, a public relay deployment, push notifications and a live video stream for the remote screen (it sends periodic images). Intel builds compile but have not been tested on Intel hardware. [CONTINUE.md](CONTINUE.md) keeps the handoff notes from the 0.6.0 checkpoint.
