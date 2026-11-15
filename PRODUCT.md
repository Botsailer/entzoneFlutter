# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

One Flutter codebase ships to Android phone, Android TV, iOS, Windows, macOS, Linux and
web. The product deliberately carries **one custom design language to every target**
rather than impersonating each OS, the way a streaming app does — but it honors each
platform's real affordances: touch targets and safe areas on phone, D-pad focus and
overscan on TV, pointer hover, window chrome and keyboard shortcuts on desktop.

## Stack

Flutter 3.50 / Dart 3.14, chosen by the user as the replacement for the existing
React Native + Expo app (`C:\Users\anupm\Documents\GitHub\entzone`).

- Player engine: `media_kit` (libmpv). Chosen because it is the only Flutter player
  covering all six targets with real multi-audio-track, multi-subtitle-track, HLS and
  mid-stream source switching.
- State: Riverpod. Local persistence: `shared_preferences` for settings/history,
  `sqflite`/files for the download queue.

## Users

People who want to watch a specific movie or series now, in three distinct situations:

- **Phone, one hand, often on mobile data.** Browsing to decide, then watching in
  landscape. Cares about data use, resume position, and downloading for a commute.
- **Android TV, ten feet away, remote in hand.** No pointer, no keyboard. Every
  action must be reachable by D-pad, and text must read from the sofa.
- **Desktop (Windows primarily), mouse and keyboard, large window.** Expects hover
  affordances, keyboard shortcuts, and a layout that uses the width instead of
  stretching a phone screen.

The job is always the same shape: *find a title → judge whether to watch it → watch it,
and pick up where I left off.* Series watchers additionally live in the
season/episode switch, which is the single most-used control in the app after play.

## Product Purpose

A single client for an unofficial third-party streaming catalog (the MovieBox H5 API),
giving one coherent, fast interface to browse, search, inspect and play its movies and
series — plus offline downloads and resume across every device the user owns.

Success: the user gets from app launch to the right frame of the right title in as few
moves as possible, and never loses their place.

## Positioning

The differentiator is not catalog (which is borrowed) but **playback control and
continuity**: a fully custom player that changes quality, audio language and captions
*mid-stream without losing the frame*, with user-configurable skip intervals, an
auto-next-episode toggle, and a pause state that answers "wait, who is that?" with
cast and synopsis instead of a dimmed frame. Plus one identity and one set of habits
across phone, TV and desktop, which the catalog's own clients do not offer.

## Operating Context

- **Catalog API:** `https://h5-api.aoneroom.com/wefeed-h5api-bff` with
  `host=movie-box.co`. Anonymous bearer token arrives in the `x-user` response header
  from `/home`, is persisted, and must be refreshed roughly every 10 minutes and on any
  4xx. The native cookie jar must be cleared when the server stops issuing `x-user`.
- **Playback resolution:** `GET /media-player/get-domain` (authenticated, rotates
  frequently, cache ~10 min) → `GET <domain>/wefeed-h5api-bff/subject/play` with a
  constructed page `Referer`. The play call itself is unauthenticated; the Referer is
  what it checks. **Every media/CDN request must carry that same `Referer` header or
  the CDN answers HTTP 429.**
- Streams come back as a list of MP4 renditions, best-first, with height, codec and
  byte size. `vipLocked` and non-MP4 renditions are unplayable and must be dropped.
- Series play per episode (`se`, `ep`); movies use `se=0, ep=0`. Seasons and episode
  counts come from `detail.resource.seasons` as `{ se, maxEp }`.
- Entries flagged `isPornographic` or `webHighRisk` must be filtered out of every list.
- The catalog is volatile: titles disappear, some have only a trailer, some are
  paid/unavailable. The interface must treat "nothing playable" as a normal state.
- Offline: downloaded files live in app-private storage and must remain playable, and
  their detail pages openable, with no network at all.

## Capabilities and Constraints

**Confirmed in scope for this build:**

- Home feed: hero banner carousel, operating sections, trending, and filter-driven rows
  for Movies / TV / Anime / K-Drama.
- Search: suggestions, popular terms, "everyone searches" start screen, result grid,
  recent-search history, filters (genre, country, year, sort, type).
- Title detail: backdrop, metadata, synopsis, cast & crew, related titles, watchlist
  toggle, and for series a **season switcher plus episode grid with per-episode watched
  state and progress** — the control the user named as the thing that must be easiest.
- Player (custom, no stock controls): mid-stream quality switch keeping position;
  audio-language switch; subtitle/CC track switch with styling; **user-configurable
  skip interval**; **auto-next-episode toggle**; **Netflix-style pause overlay showing
  cast and description**; speed, fit/zoom, lock, PiP, background audio, media session,
  resume, progress saving.
- Library: watchlist, watch history grouped by day, continue-watching, downloads.
- Offline downloads: queue with pause/resume/cancel, quality picker showing real file
  sizes, foreground-service progress notification on Android, playback from disk.
- Settings: default stream quality, default download quality, skip-interval seconds,
  auto-next, auto-PiP, background play, media controls, subtitle appearance, cache.
- Input parity: touch, pointer+hover, **keyboard shortcuts** (space/K, J/L, arrows, F,
  Esc, M), **D-pad/remote media keys with visible focus** on Android TV, and gamepad.

**Constraints:**

- Stream availability, rendition list, track list and catalog contents are entirely
  controlled by upstream and change without notice.
- Playback quality depends on upstream bitrate, network, and the device decoder;
  the quality menu only chooses among what upstream returned.
- Android minimum API 24. Picture-in-picture needs API 26; automatic PiP needs API 31.
- Windows desktop builds need Visual Studio with the C++ workload installed.
- No account system: the session is anonymous and disposable.

## Brand Commitments

- Name and header brand text: **depressedzone** (user-confirmed; the existing RN
  identity is kept so this build replaces it rather than forking it).
- Android package / bundle id: `com.botsailer.depressedzone`.
- Existing icon asset: `assets/img/depressedzone-icon.png`,
  used for app icon, launcher, splash and the header mark. A matching TV banner exists
  for the leanback launcher.
- The user asked that the header **match the structure of the MovieBox browser
  prototype's header** (`E:\MovieBox-Browser-P2P-Prototype (1)\worker\ui.js`): brand
  mark + brand text, a segmented source switch, text nav with an active underline, and
  a compact inline search field, in one fixed band. That is a binding structural
  constraint on the desktop header; the visual world itself is to be designed fresh.

## Evidence on Hand

- **Working API client with hard-won details** — `entzone/lib/api.ts` (536 lines):
  token dance, cookie-jar clearing, two-level cache, the Referer requirement. This is
  verified-against-production behavior and must be ported faithfully, not re-derived.
- **Working player** — `entzone/components/player/PlayerScreen.tsx` (1013 lines):
  resume, quality switch with position restore, PiP handoff, media session, remote keys.
- **Working download queue** — `entzone/lib/downloads.ts`, `plugins/withDownloadService.js`.
- **Endpoint documentation** — `MovieBox-Browser-P2P-Prototype (1)\ENDPOINTS.md`.
- **Reference header implementation** — the prototype's `worker/ui.js`.
- No analytics, no user research, no real user counts, no testimonials, no press, and
  no licence for the catalog. Future work must not invent any of these.

## Product Principles

1. **Continuity beats everything.** The user's position in a title is sacred. Changing
   quality, language, episode, device orientation or window size must never cost the
   frame or the resume point.
2. **Season and episode switching is a primary control, not a sub-page.** Getting from
   "watching S1E4" to "start S2E1" is a two-move operation on every platform.
3. **The catalog will fail; the interface will not.** Missing streams, dead titles,
   absent subtitles and no network are expected states with designed answers, never
   error dialogs or blank screens.
4. **One identity, three sets of hands.** The same screens, tuned honestly for touch,
   remote and pointer — never a phone layout stretched to a TV, never a desktop layout
   crammed onto a phone.
5. **Artwork carries the mood; chrome stays out of the way.** The interface's job is to
   make posters and backdrops legible and the next action obvious.

## Accessibility & Inclusion

- Every action reachable without a pointer: full D-pad focus traversal on TV and full
  keyboard traversal on desktop and web, with a visible focus indicator at all times.
- Touch targets at least 48dp on phone; TV targets sized for 10-foot legibility.
- Subtitle appearance is user-adjustable (size, background opacity) because the catalog
  burns no captions in and the user base includes dub/sub switchers.
- Respect the OS reduced-motion setting: the RN app already did, and the hero reveal,
  rail morph and overlay transitions must all degrade to plain fades.
- Text contrast at WCAG AA against the dark surfaces it sits on, including over artwork.
