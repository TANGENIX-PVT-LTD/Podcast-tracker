# Daily learning loop and strict Focus Mode

Implemented in the unified macOS/iOS/Android sources and mirrored to the standalone iOS and Android workspaces. Existing history, achievements, goals, Rescue commitments, and platform configuration are retained. A signed development update has also been installed and launched on the connected iPhone. This is not a signed store release.

## What ships in the source

| Surface | Behavior |
| --- | --- |
| Today and Progress | Start today’s adaptive goal, three daily quests, protected streak, gems, rewards, cached recall, personal league, collectible badges, optional sound/haptics |
| Streak | Completing today’s adaptive goal protects today; two initial freezes preserve continuity without incrementing the streak; every seven actual learning days replenish one, capped at two |
| Quests | One five-minute block, the day's learning goal, and a recall review/takeaway/action; each awards 10 XP and 5 gems once |
| Daily chest | All three quests earn a persisted 5/10/20-gem draw with 60/30/10% odds and 900 seconds of future playback XP boost |
| Boost | Doubles playback XP only; merged offline contributions are capped to the earned boost budget, so concurrent devices cannot multiply it |
| Badges | Streak milestones at 3/7/14/30/50/100/365 days; five-day week; 20-quest month |
| Personal league | Bronze through Diamond against four clearly labeled historical weeks; Monday target stays fixed; target plus five active days promotes, 60% holds, otherwise demotes, with Bronze as floor |
| Shop | 100-gem freeze refill; optional 20-gem seven-day promise returns 40 for seven actual learning days. Purchases require authenticated sync; gems never unlock apps |
| Recall | Three Groq multiple-choice questions from a cached transcript, validated exact supporting passages, explanations, offline cache, stages 0/1/3/7, one reward per scheduled stage. Missing content/key shows a transcript or takeaway alternative |
| Reminders | Selected times and quiet hours, nearby recent-session timing, local novelty/success-aware copy, at most three motivation prompts per day; Rescue replaces a nearby slot; obsolete warnings cancel after protection/target; one final prompt after seven inactive days, then pause until return |
| Native cues | iOS momentum widget, new Android home-screen widget, Mac menu bar; original app identity and platform controls |

Playback uses monotonic elapsed time while the player is actually advancing. Pauses, buffering, seeking, duplicate callbacks, and suspended observation gaps do not count. Playback speed does not increase credit. Native AVPlayer/Media3 state and the Android Play flavor's YouTube IFrame API feed the same learning accounting. Existing background native audio continues to count while its player reports actual playback. Learning checkpoints occur every 15 credited seconds, at block boundaries and on interruption/background/shutdown when the OS permits a callback. Forced termination can lose the interval since the last checkpoint.

Old statistics seed the XP baseline. Old activity can preserve the existing streak, but does not mint new quests, chests, or milestone rewards. New receipt IDs deduplicate retries and merges. Listening, recall accuracy, and completed actions remain distinct signals.

## iPhone and iPad

Focus Mode and streaks use one dated adaptive target: start at five minutes, repeat each level for two successful learning days, then add one minute, capped at 60. Missed days hold the level. Existing historical streak days retain their original qualification; new adaptive days require their full goal. The target is frozen by its first successful server sync, and a stale device cannot lower it. Offline estimates reconcile to that canonical target when synchronized. Setup requires individual Screen Time authorization, Apple's app picker, and explicit selection review. Choose individual distracting apps only; leave PodTrackio and playback apps accessible.

The app and three extensions share opaque selections and a compact local snapshot through `group.com.tangenix.podtrackio`. Only the named `podtrackio.learning` ManagedSettings store is changed. Daily monitoring reapplies shields at local midnight without a network request or the main app running. Local playback removes them immediately at the target. Learning on Mac, iPhone, or Android contributes to the same owner’s daily ledger; **open PodTrackio on iPhone while online to sync remote completion and remove its shields**. Passive ledger merges and background saves do not admit new remote unlock credit. Previously admitted credit remains valid only for that date; midnight discards it for locking purposes. The shield opens PodTrackio on iOS 26.5+, with manual opening on earlier supported versions.

While today's target is incomplete there is no in-app pause, bypass, target reduction, selection edit, or disable action. Completing or cancelling Rescue, manually marking an episode complete, signing out, spending gems, importing statistics, or using a freeze does not grant unlock credit. Remote playback credit is admitted only after a successful foreground habit sync for the bound owner. After completion, selections and future blocking can be changed.

The device owner can revoke Screen Time authorization in Settings or remove the app. Apple does not provide an irrevocable self-control lock.

Targets: `PodTrackioFocusMonitor`, `PodTrackioFocusShield`, `PodTrackioFocusActions`. Family Controls and App Group entitlements are configured for all targets. The standalone development team is preserved. **Signed development provisioning is verified:** the app, widget, and all three Focus extensions include the connected iPhone in their profiles; the app and Focus extensions carry the Family Controls entitlement. The development build installed and launched successfully on an iPhone 14 Pro Max running iOS 27.0 on 2026-10-22. The user confirmed that a selected app was shielded after activation. Apple's Family Controls distribution approval remains separate. Daily callbacks, reboot behavior, and the full physical acceptance checklist still need verification.

## Mac

The gate observes application activation, midnight, and wake. Selected `.app` bundles are identified by bundle ID. During an incomplete target, PodTrackio requests that the distracting app hide and brings up its learning gate. Apps are never terminated, preserving open work. A failed hide request is reported. The existing menu-bar lifecycle keeps this active after closing the main window; existing launch-at-login settings are reused.

This is explicitly best effort and works only while PodTrackio runs. Quitting bypasses it. It does not claim native Mac Screen Time enforcement or protection against another desktop/Space/window being shown without an activation event.

## Celebrations

The Mac Today screen leads with Up Next and one Continue learning action. Streak, credited minutes, gems, quests, and Focus Mode occupy a compact status row; quest/reward details open on demand. The old oversized habit panel, large daily headline, and duplicated metric cards are removed.

Mac and iOS show a large completion check, an expanding ring and brief radial burst, a larger bouncing streak/flame, optional sound/haptics, and a dismissible completion card without stopping playback. Quest checks bounce once on completion. Reduce Motion removes scale, burst, and symbol bouncing; VoiceOver keeps the card open until dismissed. The existing app identity is retained. Android receives the shared goal policy; its larger animation pass is deferred as requested.

## Private sync and deployment

Migration: [`supabase/migrations/20261022060736_habit_loop.sql`](supabase/migrations/20261022060736_habit_loop.sql).

Owner-only `habit_accounts` and `habit_events` use RLS. Direct writes and anonymous access are denied. A public invoker RPC calls a private definer function with a fixed search path, derives the owner from `auth.uid()`, and serializes purchases with an account row lock. Device contributions merge monotonically. Immutable server receipts reconcile duplicate rewards and chest draws. Closed-week league results are derived from merged history, including late sync and inactive weeks.

Habit files are scoped to the signed-in owner. Guest earnings can be claimed once; switching accounts cannot copy those receipts into another wallet. Corrupt habit/workspace files are preserved rather than overwritten. Recall questions, transcripts, reminder history, and app selections remain local. Shared playback completes the account’s streak and learning target. Each Focus snapshot records only remote credit admitted by a foreground sync, alongside local playback. Another account cannot grant it credit. A failed unrelated workspace fetch cannot prevent habit completion sync.

The RPC exchanges the complete compact ledger. Add cursor-based batches if ledger size or sync latency becomes material. Offline reward balances may reconcile to the canonical receipt on reconnect. This is a private personal habit ledger, not a tamper-proof competitive economy.

**Applied to the live PodTrackio project on 2026-10-22** through the user-provided authenticated Comet session, after verifying project `flioaadbuwrpzmoyqypo` and its existing learning-table schema. The transaction completed successfully. Post-deployment checks verified RLS on both habit tables, denied anonymous table/RPC access and direct authenticated writes, and allowed the authenticated RPC. Real client sync subsequently created one owner profile and habit-event receipts. A later live query observed 13 receipts and 361.6 credited playback seconds for the current day, with all access-control checks still passing. No other project was changed. A full two-device physical unlock round trip and live shared purchases remain unverified.

Deployed migration SHA-256: `1869e8600aabc5ac5105f862982c1b9f6ec29986ffd60ca644b93564887fce6a` (byte-for-byte match with the locally tested file).

The project has no Supabase CLI migration-history table. This deployment applied the exact migration SQL through the dashboard; establish a baseline/repair migration history before adopting CLI `db push` against this existing project.

The adaptive follow-up migration is [`20261023080000_adaptive_daily_goal.sql`](supabase/migrations/20261023080000_adaptive_daily_goal.sql), applied to the same PodTrackio project on 2026-10-23. SHA-256: `9db2dd2bdbb4464a03f3507da4cc71d253e2f08e7f46807d82c8808dc4987291`. The live function body matches local PostgreSQL (`892d47205cc06bc53ad9b101ac87a115`); RLS, direct-write denial, and anonymous RPC denial remain verified. Canonical daily targets are derived transactionally from prior completed playback days, including reversed offline uploads. No new permissions or tables were added.

## Validation

2026-10-23 update: the full SwiftPM Mac app was packaged, verified, and relaunched in place with existing user data. Native UI inspection confirms Up Next first, the compact status row, and the working quest/reward popover. The shared compact view compiles for iOS. The signed adaptive-sync iPhone build was installed and launched; the later Mac-focused compact layout is in the iOS source but has not replaced that physical build. Physical Mac-to-iPhone unlock and overnight reblocking are still awaiting observation.

- macOS Swift policy suite: 76 tests, including elapsed playback/seek/gap behavior, strict target edits, next-day locking, unified adaptive streak/unlock targets, foreground shared credit, account binding, migration compatibility, freeze continuity/refill, wager payoff, chest persistence/deduplication, boost limits, late league results, legacy rewards, recall evidence/schedules, quiet hours/caps/inactivity pause.
- iOS app plus all three extensions: simulator builds and a signed physical-device development build pass. The existing team configuration is preserved; the development update installed in place under the original bundle ID and launched on the connected iPhone. The user confirmed selected-app shielding.
- macOS Xcode app bundle builds; Swift package tests exercise the full local implementation.
- Android full and Play: 26 unit tests per flavor and debug APK builds; lint passes with existing nonfatal warnings. Both standalone flavors build/test as well. Three isolated emulator persistence tests pass in each flavor, covering chest/recall round trips, one-time guest ownership, legacy defaults, and corrupt-file preservation.
- Local PostgreSQL migration checks: duplicate upload replay, stale contribution preservation, canonical baseline, purchase retry, overspending, RLS account isolation, direct-write/anonymous denial. Two concurrent 100-gem requests produced exactly one refill and rejected the second spend.
- iOS simulator app launch and Android emulator habit panel checked. Physical Screen Time authorization/selection/activation and selected-app shielding were then confirmed by the user on the connected iPhone. The live backend also received 361.6 credited playback seconds. Immediate unlock awaits physical confirmation after the selected target finishes; notification delivery remains unverified.

Reproduce core checks:

```sh
swift test --scratch-path .swift-build
xcodebuild -project ios/PodTrackio.xcodeproj -scheme PodTrackio \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
cd android
./gradlew testFullDebugUnitTest testPlayDebugUnitTest assembleFullDebug assemblePlayDebug lintFullDebug lintPlayDebug
./gradlew connectedFullDebugAndroidTest connectedPlayDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.class=com.tangenix.podtrackio.HabitPersistenceInstrumentedTest
```

SQL checks run in an isolated fixture database with test auth roles and tables, then roll back. Use [`supabase/tests/habit_loop.sql`](supabase/tests/habit_loop.sql) and [`supabase/tests/adaptive_daily_goal.sql`](supabase/tests/adaptive_daily_goal.sql); do not run fixture users against production.

## Remaining release checks

- Physical iPhone/iPad: authorization, picker review, activation, and selected-app shielding confirmed. Still check unselected apps, immediate unlock, midnight reblocking, force-quit/relaunch, reboot, background playback, revocation, token/picker failures, and Reduce Motion/VoiceOver/widget deep links.
- Mac: selected/unselected real apps, hide failures, closed main window, multiple Spaces, sleep/wake, login launch, quitting, keyboard and VoiceOver. No distracting apps on the user's Mac were hidden during automated checks.
- Real accounts: migration applied and initial real-client sync verified. Still check offline replay, concurrent devices, canonical rewards, shared purchases, sign-out/account switching, and shared playback unlocking only after foreground sync on the receiving device.
- Real providers: Groq generation with a user key and transcript, quiz accuracy against its evidence, real notification delivery/quiet hours, and sustained background playback. No paid API calls were made.
- Signed development build, entitlements, provisioning, physical installation, and launch verified. Distribution profiles, Family Controls distribution approval, TestFlight/store submission, and distribution-device behavior remain outstanding.

Android blocking, public competitors/social infrastructure, paid rewards, and hearts/energy limits remain outside the approved scope.
