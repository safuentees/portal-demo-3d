# Fast Typer

A standalone macOS utility with a text box and a global typing shortcut. No Python packages or network connection needed. Requires Apple's Command Line Tools or Xcode.

1. Double-click `Launch.command`. The first launch compiles a small native app.
2. Click **Enable Accessibility…**, then enable **Fast Typer** in **System Settings → Privacy & Security → Accessibility**. If it is not listed, add `~/Library/Application Support/FastTyper/Fast Typer.app` with the + button.
3. Paste your text into the box and select a speed.
4. Click the destination text field in another app. Press and release **Control + Option + T** to type.
5. Press the same shortcut again, or **Escape**, to stop. Switching to another app also stops typing.

Click the Dock icon to reopen the text box. Closing or hiding the window keeps the shortcut available; **Command + Q** quits. Text is kept only in memory and is discarded when the app quits. The clipboard is not used for output.

The default delay is randomly selected between 8 and 22 milliseconds per character (about 67 characters/second before app overhead). Very fast uses 3–10 ms; Slower uses 25–50 ms. This is timing variation, not a realistic simulation of a person. If a destination drops characters, select Slower.

Unicode characters are sent as keyboard text. Newlines and tabs send actual Return and Tab keys, so the destination controls submission, focus, and automatic indentation. For code editors, turn off automatic indentation if it would duplicate indentation already in your text. Some secure fields and applications ignore simulated input.

The launcher builds outside the source tree in `~/Library/Application Support/FastTyper`. To build without opening a window:

```sh
FAST_TYPER_BUILD_DIR=/tmp/fast-typer-build ./Launch.command --build-only
```

The tool is independent of the Swift/Metal portal app. No portal settings or scene code are changed.
