# Cove website

Static product site for Cove. No build step and no dependencies; serve the folder with any static HTTP server:

```sh
python3 -m http.server 8000 --bind 127.0.0.1
```

## What is on the page

- The download buttons read the latest GitHub release at runtime, link straight to the `.dmg` (falling back to the `.zip`, then to the Releases page) and show the tag. Nothing needs editing when a new version ships.
- The window in the hero is an HTML rebuild of the real app: the same palette as `Sources/Cove/Theme/Theme.swift`, the 5pt status squares and 4pt step indicator from `PixelViews.swift`, and the pixel crab ported cell by cell from `PetView.swift`. The projects and conversations in it are fictional examples.
- Page colors follow the app's light and dark palettes. The page follows the system appearance; the toggle under the window overrides it and is remembered per browser.

## Checks

- `node --check app.js`
- Look at 390, 1000 and 1440 px wide, in light and dark.
- In the window: the Claude Code session plays once when scrolled into view; Codex can be approved or declined; ended sessions can be resumed; the terminal toggle shows the same transcript.
- Reduced motion shows final states without animation.

## Assets and licenses

`cove-cup.png` and `cove-icon.png` are unmodified copies of `Resources/CupMark.png` and `docs/assets/icon.png`. Newsreader is bundled under the SIL OFL 1.1 (`assets/fonts/Newsreader-OFL.txt`). Website source is covered by the repository's MIT license.
