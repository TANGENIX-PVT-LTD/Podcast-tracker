# Security policy

## Reporting a vulnerability

Please use GitHub's private security-advisory flow for this repository. Do not
open a public issue for a suspected vulnerability or include credentials,
tokens, account data, or proof-of-concept access details in an issue.

## Credential handling

- Never commit API keys, Supabase service-role keys, OAuth secrets, signing
  certificates, or local configuration files.
- Groq and TranscriptAPI keys are supplied by each user and stored in their local Apple
  Keychain (macOS/iOS), or encrypted with Android Keystore. They are not part of this repository.
- The app's Supabase client identifier is not a service credential. Any
  deployment must enforce Row Level Security and keep privileged keys in the
  server environment only.

If a key is committed accidentally, revoke it at the provider first, then
remove it from every reachable Git ref before publishing a fix.

## Repository checks

Gitleaks scans all reachable Git history on pushes and pull requests. Its only
JWT exceptions are the exact pre-existing Supabase anon client identifiers in
the two Apple auth/database client files; these are not service-role or user
session tokens. Every other default credential rule remains enabled.

Ignore rules exclude local mobile configuration, signing keys, IDE user state,
build artifacts, and device captures. Review the staged file list before pushing.

A public client key is safe only when the backend denies anonymous access to
private data and enforces ownership for authenticated reads and writes. Test
those permissions in the live project as well as the migration definitions.
