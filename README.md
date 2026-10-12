# PodTrackio

Native learning companions for **macOS, iOS, and Android**. Build a focused
library of educational YouTube videos and podcasts, take notes, track progress,
and turn transcripts into study briefs and follow-up conversations.

All three apps live in this repository and share the Supabase data contract.
They are separate native implementations; their source files are maintained
independently. The Android interface is optimized for tablets and adapts to
smaller screens.

## Repository layout

| Version | Source and project | Requirements |
| --- | --- | --- |
| macOS | [`Sources/PodcastTracker`](Sources/PodcastTracker), [`Package.swift`](Package.swift), [`PodTrackio.xcodeproj`](PodTrackio.xcodeproj) | macOS 26+, Xcode with macOS 26 SDK and Swift 6.2+ |
| iOS | [`ios/`](ios), [`ios/PodTrackio.xcodeproj`](ios/PodTrackio.xcodeproj) | iOS/iPadOS 26+, Xcode with iOS 26 SDK |
| Android | [`android/`](android) | Android 8+ (API 26), JDK 17, Android SDK 36 |
| Shared backend | [`supabase/`](supabase) | Your own Supabase project for auth and sync |

## Features

- Episode libraries, categories, collections, notes, and learning schedules.
- Playback progress, goals, streaks, achievements, and focus reminders.
- Transcript imports, AI learning briefs, action plans, and transcript-grounded chat.
- Optional account sync through Supabase; downloads and API keys stay on-device.
- iOS widgets and native Android tablet layouts.

Feature availability varies by platform and distribution flavor. See
[Brain architecture](BRAIN.md) and [Android feature parity](android/FEATURE_PARITY.md).

## Get the code

```bash
git clone https://github.com/tanmaybawakar/Podcast-tracker.git
cd Podcast-tracker
```

## macOS

### Install

Download [PodTrackio.dmg](PodTrackio.dmg), open it, and drag **PodTrackio** to
**Applications**. This existing installer is ad-hoc signed; use Finder's
Control-click → **Open** if Gatekeeper requires it. It is not a notarized release
of every platform or necessarily the newest source revision.

### Build and test

Select an Xcode installation that includes the required SDK:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./script/build_and_run.sh
swift test
```

Use `./script/build_and_run.sh --verify` to validate and launch the app, or
`./script/build_and_run.sh --dmg` to build an installer. Build outputs stay in
ignored local directories. The Xcode project is the sandboxed App Store variant;
the Swift package provides the full local version with external media tools.

## iOS

```bash
open ios/PodTrackio.xcodeproj
```

Choose the **PodTrackio** scheme and an iPhone or iPad simulator, then build and
run. To install on your own device, select your development team for both the
app and widget targets and configure your own bundle identifiers and app group.
No signing certificate or private signing key is included.

For a simulator compile without signing:

```bash
xcodebuild -project ios/PodTrackio.xcodeproj -scheme PodTrackio \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

[`ios/project.yml`](ios/project.yml) is the XcodeGen definition; the generated
project is included, so XcodeGen is optional. There is no prebuilt iOS installer
or App Store publication in this repository.

## Android

Copy the configuration template and set your local SDK path and your own
Supabase publishable/anon key:

```bash
cd android
cp local.properties.example local.properties
./gradlew testFullDebugUnitTest testPlayDebugUnitTest
./gradlew assembleFullDebug assemblePlayDebug
```

`local.properties` is ignored. The same `PODTRACKIO_SUPABASE_URL` and
`PODTRACKIO_SUPABASE_ANON_KEY` values can be supplied through environment
variables. Do not use a Supabase service-role key here.

| Flavor | Behavior | Debug APK |
| --- | --- | --- |
| `full` | Native media playback, downloads, and playlist extraction | `app/build/outputs/apk/full/debug/app-full-debug.apk` |
| `play` | Embedded YouTube playback; external extraction/download component excluded | `app/build/outputs/apk/play/debug/app-play-debug.apk` |

Additional checks: `./gradlew lintFullDebug lintPlayDebug` and, with a device or
emulator connected, `./gradlew connectedFullDebugAndroidTest`.

The `full` flavor includes GPL-licensed third-party components; read
[third-party notices](android/THIRD_PARTY_NOTICES.md) before distributing it.
The flavor names do not guarantee approval by an app store.

## AI keys and backend setup

Add your own **Groq** and **TranscriptAPI** keys in each app's Settings. Apple
apps use Keychain; Android encrypts stored credentials with Android Keystore.
You can paste/import a transcript when automatic retrieval is unavailable.

For an independent backend:

1. Create a Supabase project and apply the SQL files under `supabase/migrations/`
   in timestamp order. Enable Row Level Security and owner-only access for every
   user-data table. Verify signed-out denial and isolation between two users;
   `supabase/tests/workspace_access.sql` checks owner visibility without changing data.
2. Enable the OAuth providers you intend to use and allow the native redirect
   `podtrackio://auth-callback`. Configure provider secrets only in Supabase.
3. In Apple source, replace the public project URL and `anonKey` constants in
   both `AuthManager.swift` and `SupabaseClient.swift` (under
   `Sources/PodcastTracker/Helpers/` for macOS and the equivalent path inside
   `ios/` for iOS). Android reads these values from local configuration.

The Apple source retains the existing service's public client identifier for
compatibility. It is not a privileged credential, and deleting it from source
would not secure a misconfigured database. Use your own backend for development;
never test writes against someone else's project.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, platform checks, and pull
requests. Report ordinary bugs through [GitHub issues](https://github.com/tanmaybawakar/Podcast-tracker/issues),
including platform/version and reproduction steps without private data.

## Privacy and security

Read [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md). Local configuration,
API/session tokens, signing material, build caches, device captures, and personal
workspace data must never be committed. Automated Gitleaks checks scan Git
history on pushes and pull requests.

Source builds and unit tests do not establish live OAuth, paid AI-provider,
cross-device sync, physical-device playback, or background notification behavior.
Validate those separately before distributing a release.

## License

Original PodTrackio source for all three platforms is covered by the root
[MIT license](LICENSE), © 2026 Tangenix Pvt. Ltd. Dependencies and bundled assets
retain their own licenses, including [D3](Sources/PodcastTracker/Resources/BrainCanvas/D3-LICENSE.txt)
and the [Android third-party notices](android/THIRD_PARTY_NOTICES.md).
