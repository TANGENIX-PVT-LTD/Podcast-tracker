# PodTrackio Brain

Brain is a workspace on macOS, iOS, and Android with distinct Canvas, Chat, and Sources views, a bottom composer, source inspection, and editable personal context.

## Evidence pipeline

- Indexes available summaries, full saved transcripts, episode Quirky chats, and source-linked Brain replies. No transcript-fetching charge is incurred merely by opening Brain.
- Builds a local inverted term-frequency representation off the UI thread. Passages overlap: 200 words, 160-word stride.
- BM25 ranking retrieves at most 10 passages, at most 3 per episode, within a 12,000-character passage budget. Prior user turns help resolve follow-ups. Broad overview questions select summaries across episodes.
- This is lexical retrieval, not embedding/vector search. Synonyms and ambiguous topic references can miss evidence. The system prompt requires acknowledging missing evidence, distinguishing inference from source claims, and treating retrieved text as untrusted data.
- Requests use the existing configured Groq key. Brain has its own prompt and JSON response contract; existing episode Quirky behavior is preserved. Only bounded recent history and retrieved sources are transmitted.
- Every answer retains the exact retrieved source snapshot. Citation IDs are validated against that snapshot; UI source cards open the passage and its episode. ID validation cannot prove every claim is supported.
- The bundled offline D3 canvas groups summary, transcript, and chat documents around their episode anchors. It supports pan, pinch/scroll zoom, dragging/pinning, node focus, document filters, labels, fit, and rearrange. Shared-vocabulary connections are sparse and appear on focus or through the connections control; they do not claim factual relationships. Source text stays outside the canvas bridge. Layout settles, stops, and respects reduced motion.

## Composer

- Deep Reasoning, Balanced, and Instant select the actual provider model and reasoning effort.
- Concise, Default, and Detailed select writing instructions and completion budgets. Both selections persist locally.
- Native menus, an expanding input, and a compact send button share the same presentation across platforms.

## Personal context

- Settings exposes goals, use-memory and learn-memory toggles, add/edit/forget controls, and conversation clearing.
- Automatic extraction considers only explicit durable self-descriptions in the latest user question. The source quote must be present verbatim, at most 300 characters. The app stores the quote rather than an unverified AI paraphrase.
- The prompt excludes sensitive traits, secrets and inferred beliefs. Watching an episode does not create a personality claim.
- Personal context is capped at 30 memories of 300 characters per request. Up to 100 memories are retained.
- Brain state is local to the installation. macOS/iOS use atomic `brain_v1.json` writes and refuse to overwrite unreadable state. Android adds a backwards-compatible Brain field to its existing atomic app snapshot.
- Brain conversations and personal memories do not yet sync through Supabase. Existing podcast/summary sync continues independently. Existing library and account storage behavior is unchanged.
- Forgetting a memory removes it from future personal context; conversation text must also be cleared if it contains the same information.

## Verification

- Swift retrieval and persistence tests cover late transcript evidence, absent evidence, source diversity, request bounds, prompt boundaries, corruption preservation and relaunch persistence.
- Android tests cover retrieval, diversity, broad overviews, old snapshot defaults and prompt boundaries.
- Earlier Brain version live library check: 15 episodes / 473 searchable passages. Final redesigned macOS UI inspection was blocked at launch by a synchronous Keychain access call. Canvas gesture behavior and physical-device appearance still need runtime acceptance.
- Live cross-podcast request returned `Access denied. Please check your network settings.` Successful provider synthesis and automatic memory extraction remain unverified.
- Final redesign: 61 Swift tests and 14 Android tests passed, including all nine composer combinations and valid episode-anchor connections. iOS simulator build, macOS package/signature verification, and Android full-debug APK/signature verification succeeded. Physical-device UX and cross-device behavior are not verified.
