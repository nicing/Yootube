# Yootube

Yootube is a self-contained native macOS app for watching through a private local Invidious service. The DMG includes Invidious, PostgreSQL, Invidious Companion, and the required runtime libraries. It does not use Docker, Homebrew, `yewtu.be`, `inv.nadeko.net`, or another public Invidious instance at runtime.

The services bind only to `127.0.0.1`. On first launch, Yootube initializes its database in `~/Library/Application Support/Yootube`. Closing the app stops the services; subscriptions and preferences stay in that data directory. Outbound YouTube requests follow the active macOS HTTP/HTTPS or SOCKS proxy when one is configured.

## Build and run

The native toolbar keeps back, forward, home, and one search/link field available
on every page. Press Return to search, or paste a YouTube link to open its local
Invidious equivalent immediately. The home screen shows recent viewing history.
Standard video, short, Shorts, live, channel, and playlist links are supported;
video timestamps and playlist context are preserved for individual playback.
Pasting a YouTube link with a `list` parameter into home opens the collection
first, including `watch?v=...&list=...` links. YouTube Mix IDs starting with `RD`
open the local Mix page using the linked video as the seed; ordinary playlists
open the local playlist page. Select a video there to use the existing player.

Viewing history is saved locally after playback begins (up to 30 unique videos).
It starts with this version and does not import Google/YouTube account history.
Return home with the toolbar home button or Cmd-Shift-H; Cmd-L returns home and
focuses search. The toolbar and trackpad navigation follow one shared history
across home, collections, search, channel, playlist, and video pages.
The app icon and home mark use the red-and-white YouTube play symbol.

The native interface uses a Spotify-inspired desktop structure with a compact
toolbar, a local-library sidebar, and one rounded main content surface. Phosphor
SVG icons are bundled locally. Appearance offers Light, Dark and System (the
default), available in Settings. The dark appearance uses
near-black and charcoal surfaces while primary actions remain YouTube red. The
selected appearance and sidebar state persist across launches. Collapse/expand
the sidebar with its top button or Control-Command-S. Collapsed mode shows each
collection's initials and reveals its full name on hover. The title bar retains
its native macOS appearance and real system window controls.
Local search/channel pages follow the selected appearance without reloading;
the player retains its existing dark controls in both modes.

The window uses the standard macOS title bar with close, minimize and fullscreen
buttons. Video details are native SwiftUI: title, channel, expandable description,
comments loaded on demand, and recommendations. Only the embedded player uses
Invidious/Video.js, with controls adapted from the Eagle clip viewer: translucent
round buttons, a gray timeline that expands on hover, orange time previews, and
a frosted settings menu. Click the video to play/pause. Clicking or dragging the
timeline seeks and resumes playback; focus it and use Left/Right to move five
seconds, or Home/End to jump to either end. The menu offers 0.5–2x speed, supported
picture-in-picture, and the stream's available quality/caption/audio options.
The expand button fills the right content area without changing the macOS window;
Escape closes the menu first, then restores the player. The Back
button returns to the originating home or web page; switching videos or returning
home stops the old player. Search, channel and subscription pages still use the
local Invidious interface.

Favorites are independent of accounts and viewing history. The left sidebar
starts with two lists: Watch Later and Favorite. Select a name in the flat sidebar
to browse its videos in the main area. Use + to create a folder and right-click
a folder to rename or delete it. Deleting a folder requires confirmation
and affects only that folder. Default folders can also be renamed or deleted;
they are not recreated on restart.

Click 收藏 on a video detail page and select one or more folders. Uncheck a folder
to remove the video from it, or use the remove button in that folder's list.
Folder names and IDs, video titles, channel names, video IDs and save dates are stored only in
`~/Library/Application Support/Yootube/favorites.json`, using atomic writes.
Favorites persist across app restarts and have no 30-video history limit. The
list remains readable without network access; playing videos requires Internet.
On a local Playlist or Mix page, use 保存到本地收藏夹 to import the whole list
as one local folder. Re-importing the same source merges new videos without
duplicates and keeps the local folder name and any extra videos already in it.
Existing single-folder favorites are automatically moved into Favorite, with the
original file retained as `favorites.json.single-folder-backup` beside it.
No Invidious or Google login is needed for favorites. Back up the JSON file to
keep a separate copy of the collection (restore it while the app is closed).

Prepare the local runtime once, then run the app:

```bash
make runtime
swift run Yootube
```

## Build the DMG

```bash
chmod +x scripts/build-dmg.sh
./scripts/build-dmg.sh
```

The installer is written to `dist/Yootube.dmg`. The first build downloads and compiles pinned upstream runtime components, so it takes several minutes. Later builds reuse the verified cache. The app is ad-hoc signed for local use, so macOS may ask you to confirm opening it the first time.

This build currently targets Apple Silicon and requires macOS 14 or later. Internet access is still required to retrieve YouTube metadata and video streams, but all Invidious application traffic goes through the service running inside Yootube on this Mac.

Invidious is licensed under AGPL-3.0-only. PostgreSQL, OpenSSL, Crystal, and Invidious Companion retain their respective upstream licenses; see `THIRD_PARTY_NOTICES.md` and the licenses bundled inside the app.
