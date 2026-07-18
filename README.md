# Alinière

Alinière is a tiny macOS utility for making wigglegrams from sequenced images.

## Workflow

- Import multiple sequenced images.
- Choose an anchor frame and draw a rectangular alignment zone in Auto mode, or select matching reference points in Manual mode.
- Preview a looping ping-pong sequence: `1 2`, `1 2 3 2`, `1 2 3 4 3 2`, etc.
- Crop to the shared aligned area automatically, or manually adjust the crop edges.
- Export the result as a GIF or MP4.

## Run

Open `Package.swift` in Xcode 16 or newer and run the `Alinière` executable target on macOS 14 or newer.

From Terminal:

```bash
swift run Aliniere
```

Run tests:

```bash
swift test
```
