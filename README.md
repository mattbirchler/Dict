# Dict

Private dictation for the Mac. This is the (private) source. The public
page, downloads, update feed, and privacy statement live in
[mattbirchler/Dict-releases](https://github.com/mattbirchler/Dict-releases);
edit `README.md` and `PRIVACY.md` there.

Dict is Swift 6 and SwiftUI, built with Xcode 27 or later. The speech
engines are Apple's `SpeechAnalyzer` and
[FluidAudio](https://github.com/FluidInference/FluidAudio) running Parakeet
TDT through Core ML. Formatting uses Apple's Foundation Models framework.

```bash
make build        # Debug build
make test         # unit tests (add E2E=1 to include the Parakeet model test)
make install      # Release build into /Applications
```

The app has preview modes for looking at the panel and windows without
dictating, for example `Dict --preview-hud recording --snapshot out.png` or
`Dict --preview-window license`. See `HUDPreview.swift`.

- Shipping a version: [RELEASING.md](RELEASING.md)
- Sales, license keys and the store site (`server/`): [SELLING.md](SELLING.md)

Copyright (c) 2026 Matt Birchler. All rights reserved. See [LICENSE](LICENSE).
