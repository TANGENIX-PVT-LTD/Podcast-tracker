# Changelog

PodTrackio keeps every major version downloadable. 3.0 is a ground-up redesign, so 2.0 stays available for anyone who prefers the classic app.

| Version | Git tag | Source branch | Status |
|---|---|---|---|
| **3.0.0** | `v3.0.0` | `main` | Current |
| **2.0.0** | `v2.0.0` | `release/2.x` | Classic, maintained for downloads only |

Downloads for both live on the GitHub Releases page: the macOS app (`.dmg`) and Android APKs. The iOS app builds from source with Xcode for either tag.

### Running the classic version
- **macOS:** install `PodTrackio 2.0.app` next to `PodTrackio.app`. Both read the same local library, so **run one at a time**.
- **Android:** 2.0 and 3.0 use the same package name. Installing 2.0 over 3.0 is a downgrade, so uninstall 3.0 first. Your library comes back from cloud sync after you sign in.
- **iOS:** `git checkout v2.0.0`, open `ios/PodTrackio.xcodeproj` and run it on your device.

## 3.0.0: "Play"

A new app built around habit, motion and feel.

- **Play design system.** Tactile, game-like UI across iOS, macOS and Android, with a 3D lip on primary buttons, a semantic game palette and rounded heavy type.
  - iOS follows platform conventions: flat outlined containers, Dynamic Type, native sheets and lists, and Liquid Glass controls.
- **Echo.** A procedurally animated mascot with nine moods. It blinks, breathes, hops, and talks while Brain answers.
- **Choreographed moments.** Every haptic, sound and visual beat fires on one clock:
  - streak extended
  - daily chest
  - level up
  - session complete
  - streak freeze saved
- **Haptics and sound.** iOS uses Core Haptics patterns; Android uses VibrationEffect compositions. The sound cues are original synthesized sounds, and both respect the haptics and sounds toggles and Reduce Motion.
- **Streak.** A streak hero with a week strip and an evening at-risk state, a streak sheet with calendar, freezes, milestones and a streak-goal pledge, and a "freeze saved you" moment.
- **Habit loop.** Adaptive daily goal, three daily quests, chest rewards, a personal league, recall reviews and strict Focus Mode, all synced through Supabase.
- **Quiz.** Duolingo-style recall: one question at a time, Check, then a green or red feedback sheet with the source quote and a combo counter.
- **Brain, rebuilt.**
  - Model choice adapts to what your Groq key serves, with per-family reasoning parameters.
  - Streaming answers and lenient parsing, plus clear errors such as a network block or a missing key.
  - An inline key setup card.
  - Modes: Ask, Quiz me, Connect ideas, Action plan, Recap my week.
  - Tappable citations that open the episode at the quoted moment, and Save as note.
- **Session complete.** A results screen after five or more minutes of learning, plus a goal ring and "+1 XP" floaters in the player.
- **iOS widgets.**
  - Streak (small, medium), where Echo turns worried at 6pm if today isn't protected yet.
  - Daily Goal ring.
  - Up Next with full-bleed episode art.
  - Learning HQ with streak, week, quests and the next episode.
  - Lock Screen circular, rectangular and inline widgets.

## 2.0.0: Classic

The last release before the redesign, at commit `40f5f8f`, which open-sourced iOS and Android with unified setup and secured sync.

- macOS, iOS and Android apps with a shared Supabase library, playback sync, notes, summaries and collections
- Brain knowledge graph (D3 canvas) and per-episode Quirky chat
- Distraction Rescue commitments, goals, calendar and achievements
