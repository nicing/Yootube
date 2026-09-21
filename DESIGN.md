# Yootube Design Direction

## Spotify-inspired native shell

Use Spotify's desktop information structure as the reference: a compact native
toolbar, a library sidebar, and one rounded content surface. The app remains
native SwiftUI/AppKit. Shared styles live in KumoTheme.swift for compatibility
with the existing source layout, and local Invidious pages use KumoWebTheme.
Neither file changes the embedded video player.

## Appearance and components

Support light, dark, and system appearance, persisted locally. Dark mode uses
near-black shell surfaces, a #121212-equivalent content canvas, and stepped
charcoal controls. Light mode keeps the same hierarchy with warm neutral steps.
Appearance is selected in Settings.
Use YouTube red for primary actions and preserve the red-and-white brand mark.
Controls use an 8/10/14-point radius scale, 36-point minimum button height, and
consistent hover, pressed, disabled, and focus states. Use the native system
font and the existing locally bundled Phosphor SVG icons; no remote visual assets
are runtime dependencies.

## Window and layout

Keep one standard macOS main window for home, collections, search, channel, and
video details. Its opaque native title bar retains the system appearance,
separator, and real close/minimize/fullscreen buttons. The native toolbar places
back/forward as one group, home as a separate control, the search/link field in
the center, and the Yootube title at the far right. Content stays below the title
bar. Do not introduce transparent chrome, full-size content,
custom window controls, or title-bar background layers. User-initiated fullscreen
remains owned by macOS and the existing player behavior.

The sidebar is 232 points expanded and 48 points collapsed. Expanded mode shows
flat collection names; collapsed mode shows one- or two-letter monograms with the
full name in the hover help. There are no disclosure controls or nested video
rows. Creation is always reachable, and right-clicking any collection exposes
rename and delete actions. Selecting a collection opens its videos in the main
area. Sidebar visibility persists locally.

The home page uses the YouTube mark and recent viewing history. Search is kept in
the toolbar on every page, so it is not duplicated in the content area. History
and collection rows use thumbnails, readable metadata, and consistent action
controls. Extra width becomes whitespace. The minimum supported window size is
760 by 520.

## Player boundary

Preserve PlayerSkin.js, PlayerSkin.swift, VideoDetailModel.swift, and the current
player interactions. Only the native detail surroundings adopt Kumo components.
The same player web view survives sidebar and appearance changes. Its loading
and error overlays retain their dark styling. The expanded player fills the
available content area without modifying standard window chrome.

## Interaction and data

Complete pasted YouTube links open immediately through the local service;
search text submits on Return. Home pauses playback. Cmd-L focuses search,
Cmd-Shift-H returns home, and Ctrl-Cmd-S toggles the sidebar. Theme changes update
native and web content without navigating or reloading the current page.

Favorites remain account-free and local, including the default Watch Later and
Favorite collections. Create, rename, delete, and multi-collection save behavior
remain available. Playlist and Mix pages expose one bottom-right action that
imports the whole source into one local collection and then opens it. Re-imports
merge without duplicates or deleting existing local entries. Only successful local file writes update saved collection
state; failed reads must never overwrite existing data. History contains real
playing events. No public Invidious instance is introduced.
