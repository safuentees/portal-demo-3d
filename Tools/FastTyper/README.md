# Fast Typer

A standalone macOS utility with a text box and a global typing shortcut. No Python packages or network connection needed. Requires Apple's Command Line Tools or Xcode.

1. Double-click `Launch.command`. The first launch compiles a small native app.
2. Click **Enable Accessibility…**, then enable **Fast Typer** in **System Settings → Privacy & Security → Accessibility**. If it is not listed, add `~/Library/Application Support/FastTyper/Fast Typer.app` with the + button.
3. Paste your text into the box. Leave **Exact text** enabled for code: it sends one plain-text paste, avoiding the extra indentation and closing braces that editors add while typing.
4. Click the destination text field in another app. Press and release **Control + Option + T** to insert. To replace a previous broken snippet, select that snippet in the destination first.
5. For randomized character-by-character typing, turn off **Exact text** and select a speed. Press the same shortcut again, or **Escape**, to stop timed typing. Switching to another app also stops typing. An exact paste is a single operation and cannot be canceled after it is sent.

Click the Dock icon to reopen the text box. Closing or hiding the window keeps the shortcut available; **Command + Q** quits. Text is kept only in memory and is discarded when the app quits. Exact text temporarily uses the clipboard and restores its previous contents after one second, unless something else has changed the clipboard. Timed typing does not use the clipboard.

The default delay is randomly selected between 8 and 22 milliseconds per character (about 67 characters/second before app overhead). Very fast uses 3–10 ms; Slower uses 25–50 ms. This is timing variation, not a realistic simulation of a person. If a destination drops characters, select Slower.

In timed typing mode, Unicode characters are sent as keyboard text. Newlines and tabs send actual Return and Tab keys, so the destination controls submission, focus, and automatic indentation. If you use timed typing for code, disable both auto-indentation and automatic bracket/quote completion in the destination editor. Exact text avoids these typing triggers, but websites can still format or reject pastes. The tool does not override website paste restrictions. Some secure fields and applications ignore simulated input.

After an update, quit the old Fast Typer app with **Command + Q**, then double-click `Launch.command` to rebuild and reopen it. If macOS asks again, re-enable its Accessibility permission.

The launcher builds outside the source tree in `~/Library/Application Support/FastTyper`. To build without opening a window:

```sh
FAST_TYPER_BUILD_DIR=/tmp/fast-typer-build ./Launch.command --build-only
```

Run `./Check.command` to build the utility and verify exact-text clipboard round trips on a separate test clipboard, including the reported Java snippet, Unicode, multiple formats, and concurrent clipboard changes. This does not send keys into other apps.

The tool is independent of the Swift/Metal portal app. No portal settings or scene code are changed.
