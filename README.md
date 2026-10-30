# Aster

Aster is a native macOS AI companion with animated desktop agents, business workspaces, personal tools and an iPhone remote app. This is the complete development checkpoint at version **0.6.0**, preserved on **2026-10-01**.

Development is paused at the owner's request. See [CONTINUE.md](CONTINUE.md) for verified behavior, remaining work and how to resume.

## Projects

| Folder | Contents |
| --- | --- |
| `outputs/Aster-macOS` | Native Swift/SwiftUI macOS application, shared remote protocol, assets and tests. |
| `outputs/Aster-iPhone` | Native SwiftUI iPhone remote application and Xcode project. Keep next to Aster-macOS. |
| `outputs/Aster-Relay` | Encrypted WebSocket packet relay, local tests and Dockerfile. |
| `outputs/aster` | Original web prototype with its build tooling and dependency lockfile. |
| `archive/source-checkpoints` | Earlier native source snapshots, retained for development history. |
| `archive/development-tools` | Earlier implementation and live-validation helpers; some retain original local paths. |
| `archive/web-prototype-history.bundle` | Original web prototype Git history. |

## Credentials

**No OpenAI API key is included. Each user must supply their own key.**

The native Mac app accepts a key in Settings → Connections, validates it and stores it in that user's macOS Keychain. The iPhone app does not need an OpenAI key: it links to a Mac through a private QR code. The relay does not receive the conversation encryption key or the OpenAI key.

For the original web prototype, copy `.env.example` to a private `.env.local` and set your own `OPENAI_API_KEY`. It is used server-side; do not put it in a public environment variable. Native development signing material, Apple account credentials, Vercel tokens, personal app state and conversations are excluded from this repository.

## Build and run

Mac: the app runs on macOS 14+ and builds with Xcode 26 or later (macOS 26 SDK). `outputs/Aster-macOS` is a Swift package: the `Aster` executable compiles `Sources/` and `Shared/`, and the `AsterTests` XCTest target covers `Tests/`. From the repository root:

```sh
zsh outputs/Aster-macOS/run.sh     # incremental debug build, bundled, signed and opened
zsh outputs/Aster-macOS/test.sh    # all XCTest suites (accepts swift test arguments, e.g. --filter ComputerTests)
zsh outputs/Aster-macOS/build.sh   # release Aster.app; ASTER_ARCHS="arm64 x86_64" for a universal build
```

Open `outputs/Aster-macOS/Package.swift` in Xcode to edit, navigate and run the tests. Launch the app with `run.sh` rather than Xcode's Run button: only the bundle that `build.sh` assembles has the Info.plist, resources and stable signature that macOS permissions need. To debug, use Xcode → Debug → Attach to Process → Aster. Debug builds accept a local `ws://` relay; release builds require `wss://`.

The development signer generates its own private local identity, excluded by `.gitignore`. Public distribution still requires your own Apple Developer ID certificate and notarization credentials. The existing [universal Mac preview installer](outputs/Aster-0.6.0-preview-universal.dmg) contains arm64 and x86_64, but has a local development signature and is not yet notarized.

iPhone: open `outputs/Aster-iPhone/AsterRemote.xcodeproj`, select your own signing team and a unique bundle identifier. The generator also accepts `ASTER_APPLE_TEAM` and `ASTER_IOS_BUNDLE_ID`. Requires iOS 17+. Distribution to physical devices or TestFlight is unfinished.

Relay: Node 24+, pnpm 11.19.0. Read [the relay guide](outputs/Aster-Relay/README.md). The included implementation is verified as one local persistent instance; it must be adapted for shared coordination before Vercel deployment.

This repository is a development preview. The remote internet deployment, distribution signing, notarization, physical iPhone testing and mobile push notifications remain unfinished. Screen sharing currently uses periodic images rather than a 60 fps video stream.
