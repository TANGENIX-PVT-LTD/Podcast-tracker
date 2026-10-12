# Third-party notice

The `full` Android flavor includes `youtubedl-android` to preserve PodTrackio's
local download and YouTube playlist features. That library is GPL-3.0 licensed
and bundles yt-dlp/Python components. Distribution of the `full` flavor must
meet those license obligations and must be reviewed for YouTube/Play policy
compliance.

The `play` flavor excludes that component. It retains account sync, learning,
AI, notes, scheduling, and embedded playback, but intentionally disables local
YouTube download and bulk playlist extraction until a store-compliant media
backend is provided.
