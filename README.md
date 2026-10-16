# SpotifyBar

A small Mac menu bar extra (next to Wi-Fi) for searching a song and play/pausing Spotify.

It talks to the **Spotify Mac app** with AppleScript. No Spotify Developer account and **no Premium** are required. Audio still comes from Spotify; if Spotify is quit, it is launched hidden in the background.

Spotify’s Web API (search results list, recommended playlists) is blocked for Free accounts, so this app does not use it.

## Build and run

```bash
chmod +x scripts/package-app.sh
./scripts/package-app.sh
open dist/SpotifyBar.app
```

A note icon appears in the menu bar.

macOS will ask for permission to control **Spotify** and **System Events** (used to hide Spotify’s window). For headset play while nothing else is using audio, allow **Accessibility** for SpotifyBar.

Optional: System Settings → General → Login Items → add SpotifyBar so it is already in the menu bar after you restart.

## Use

- Play / pause from the popover. That always targets Spotify (bundle ID), not Apple Music.
- Type a song and press Search — results appear in the popover. Click one to play it in Spotify in the background.
- If nothing else is playing, headset **play** starts Spotify in the background. If Opera, Disney+, YouTube, or similar is using the speakers, the headset button is left alone.

Quit from the tiny **Quit** link at the bottom of the popover.
