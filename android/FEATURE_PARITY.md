# macOS to Android tablet parity

| Capability | Android tablet implementation | Verification |
| --- | --- | --- |
| Google and Apple auth | Supabase OAuth custom-tab flow, deep-link callback, encrypted rotating session | Entry UI/device manifest verified; live account authorization pending user interaction |
| Cross-device continuity | Same six owner-scoped tables; pull/merge/push plus debounced episode writes | Merge tests and payload contract verified; live two-device round trip pending account authorization |
| Library and categories | Search, filters, add/remove episodes, category create/edit/delete/reassign/reorder | Tablet journey and unit tests passed |
| Playlist collections | Preview/import/update and collection filters | Implemented in `full`; live public resolver covered by device test |
| Playback and progress | Media3 player, resume, real-playback watch accounting, 5s/15s controls, timestamp seek | Expanded tablet player and live resolve passed |
| Notes and schedules | Immediate local note persistence, debounced sync, presets/custom date-time, calendar management | Tablet journey passed |
| Downloads | 480p/720p/1080p, DownloadManager, 8 GB cap, never evict unfinished, expire completed after seven days | Real download/reconcile/delete device test passed |
| Transcript tools | TranscriptAPI, downloaded-media Groq Whisper, paste and Android file import | Request/parsing paths compile; live paid-provider calls need user keys |
| Learning brief | Groq JSON summary, topics, dynamic sections, timestamps, takeaways, action plan/XP | UI and serialization verified; live paid-provider call needs user key |
| Quirky | Three models, three answer depths, bounded transcript grounding, persisted local conversation | Context tests/UI passed; live paid-provider call needs user key |
| Focus rescue | 5-30 minute real-playback promises, completion win, +5/+10 extension | UI/model path verified |
| Goals and momentum | Daily/weekly goals, adaptive build-up, streaks, XP, levels, achievements, calendar | Unit tests and tablet journey passed |
| Notifications | Three daily times, weekdays, quiet hours, episode alarms, boot restore, adaptive rescue reminder | Settings/device manifest verified; delivery timing needs physical-device observation |
| Daily learning loop | Five-minute quests, freezes, gems/chests, earned boosts, solo historical leagues, badges, seven-day promises, cached transcript recall, widget | Policy tests and emulator checks; live account/provider gates in `../HABIT_LOOP.md` |
| Appearance | System, Ocean, Orchid, Forest, Sunset, Midnight | Tablet Settings journey passed |
| Security/offline | Atomic JSON cache, Android Keystore AES-GCM, HTTPS-only traffic, no backup | On-device round-trip passed |

## Intentional platform substitutions

- macOS navigation becomes a Material navigation rail and expanded two-pane
  tablet workspace.
- macOS keychain becomes Android Keystore-backed AES-GCM storage.
- macOS notifications become AlarmManager/notification-channel alarms restored
  after reboot.
- The App Store-safe macOS distinction maps to two Android product flavors. The
  Play-safe flavor embeds YouTube and omits external extraction; the full
  sideload flavor preserves local download and playlist functionality.

Raw transcripts, API keys, Quirky history, focus-rescue history, preferences and
download files stay device-local, matching the macOS privacy boundary. Synced
learning briefs remain readable on every signed-in device.
