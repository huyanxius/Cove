# Cove website

A dependency-free product website for the current development branch. Run with any static HTTP server.

This website does not modify the native application or run an agent. Its interactive app illustration uses explicitly fictional sample content and is labelled as an illustration, not a product screenshot. Product copy is based on feat/m0-shell at 031d4d4d92344bc8eec8e360023385c944df867e.

The app is still in development. There is no signed/notarized release download. Source links intentionally target feat/m0-shell rather than main, which currently contains only the initial README.

## Checks

- node --check website/app.js
- Check at 320, 390, 768 and 1440 pixels.
- Check both illustration modes, light/dark appearance, keyboard tab arrows/Home/End, build details, copy success/failure, focus and reduced motion.

## Assets and licenses

Cove cup and icon are unmodified copies of this repository's Resources/CupMark.png and docs/assets/icon.png. Website source remains covered by the repository's MIT license.

Instrument Serif is bundled with its original SIL OFL 1.1 license in assets/fonts/OFL.txt. No third-party character artwork or external fonts are loaded.
