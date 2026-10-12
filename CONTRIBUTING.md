# Contributing

Start with the [README](README.md) and use your own backend and API keys.

Keep changes focused on the relevant platform. macOS and iOS have independent
Swift source trees; shared behavior changes may need updates to both. Android
uses the same database contract, so preserve wire formats and migration order.

Before a pull request:

- macOS: run `swift test` with a supported Xcode selected.
- iOS: build the PodTrackio scheme for an iOS simulator with signing disabled.
- Android: run `testFullDebugUnitTest testPlayDebugUnitTest` and build both flavors.
- Backend: after loading an owned test podcast, run `supabase/tests/workspace_access.sql`
  in the SQL editor or with `psql -v ON_ERROR_STOP=1 -f supabase/tests/workspace_access.sql`.
- Credentials: run `gitleaks git . --log-opts=--all --redact` with Gitleaks 8.30.1+.

Describe what changed, which checks you ran, and any device/provider behavior
that remains unverified. Never include local configuration, personal data,
private keys, signed release artifacts, or device captures in a pull request.

Use GitHub's private vulnerability reporting for security issues. If it is
unavailable, ask the maintainer for a private reporting channel without posting
exploit details publicly.
