# Soundboard (macOS)

A desktop soundboard for your Mac. You can:

- **Add your own sounds.** Click **+ Add Sounds** or drag audio files (mp3, wav, m4a, aac, ogg, opus, flac, aiff, caf, webm) onto the board.
- **Clip sounds from YouTube.** A built-in YouTube browser lets you search for a video, mark a start and end, and save that piece of audio as a new sound.
- **Play sounds** by clicking a tile, or with a **global hotkey** (such as ⌥⌘1) that works even when the app is in the background.
- **Choose an output device**, for example a virtual cable like BlackHole, so others hear your sounds on Discord or Zoom.
- Set per-sound **volume**, **color** and **name**, and drag tiles to reorder them. You can also filter sounds, use a master volume, and press **Stop All** (or Esc).

## Run it

You need [Node.js](https://nodejs.org) 20 or newer (`brew install node`).

```bash
cd soundboard-mac
npm install
npm start
```

## Build a real .app / .dmg

```bash
npm run dist
```

The DMG is written to `dist/`. Open it and drag **Soundboard** into Applications. The build isn't code-signed, so the first time you open the app, right-click it and choose **Open**.

## Making a sound from YouTube

1. Click **▶ YouTube** to open the browser panel.
2. Search, or paste a video link, and open a video.
3. Play the video. Click **Set Start** and **Set End** at the moments you want, or type times such as `1:23.5`.
4. Click **Preview** to hear your selection. Then give the sound a name (optional) and click **✂ Create Sound**.

The app plays the selected range once and records the video's audio while it plays, so a 5-second clip takes about 5 seconds. It then trims the recording to the exact range and saves it as a WAV. Clips can be up to 5 minutes long. If an ad starts playing, the capture stops so you can retry after the ad.

## Where sounds are stored

`~/Library/Application Support/Soundboard/sounds/`. This folder holds the audio files and a `library.json` index. You can open it from any sound's **⋯ → Show in Finder**.

## Notes

- Right-click a tile, or click its **⋯** button, to edit or delete it. ⌥-click a tile to stop it.
- A hotkey must include ⌘, ⌥ or ⌃, or be an F-key, so it doesn't block normal typing in other apps.
- Google sometimes blocks sign-in inside embedded browsers. YouTube works fine without signing in.
- Only clip audio you have the right to use.

## Development

```bash
npm test   # unit tests for the library store and audio helpers
```

| File | Purpose |
| --- | --- |
| `src/main.js` | Window, IPC, global hotkeys, `sound://` protocol |
| `src/library.js` | Sound storage (files + `library.json`) |
| `src/preload.js` | Safe API exposed to the UI |
| `src/youtube-preload.js` | Injected into the YouTube view; records the video's audio |
| `src/renderer/` | The UI, plus WAV encoding and trimming |
