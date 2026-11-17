# Komet

Minimal macOS app launcher.

## Install

Runs on Apple silicon and Intel Macs with macOS 13 or later.

```bash
brew install wickes1/tap/komet
open -a Komet
```

## Upgrade

```bash
brew upgrade wickes1/tap/komet
```

> **Note:** Komet is unsigned. The cask strips the Gatekeeper quarantine attribute on install. If you still see a Gatekeeper warning, go to **System Settings → Privacy & Security** and click **Open Anyway**.

## Permissions

None. Komet registers `Cmd+Space` as a system hotkey, which needs no Accessibility permission, so an upgrade has nothing to re-grant. If an older Komet is still listed under **System Settings → Privacy & Security → Accessibility**, you can remove it.

## Searching

- A name that starts with what you typed comes first (`te` → Terminal), then a word in the name (`teams` → Microsoft Teams), then the initials (`vsc` → Visual Studio Code), then the letters anywhere. Among equal matches a running app comes first.
- Both the app's own name and its file name count: VS Code calls itself "Code", and `vsc` still finds it.
- While Komet is open the keyboard switches to your Latin layout, so a Chinese or Japanese input method does not turn app names into candidates. The previous input method comes back when Komet closes.
- Komet closes when another app takes focus.
- Apps installed while Komet runs show up the next time you open it.

## Open at Login

To start Komet automatically when you log in:

**System Settings → General → Login Items → Click + → Select Komet**

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+Space` | Toggle window |
| `Cmd+,` | About |
| `Cmd+Q` | Quit Komet |
| `Cmd+R` | Restart Komet |
| `Cmd+W` | Quit selected app |
| `Tab` | Toggle Running/All filter |
| `Enter` | Launch app |
| `Escape` | Hide window |
| `↑/↓` | Navigate |

## Build from Source

```bash
make test
make app
make install
```

## Note

`Cmd+Space` is Spotlight's shortcut on a new Mac. Turn off **Show Spotlight search** in
**System Settings → Keyboard → Keyboard Shortcuts → Spotlight**, then quit and reopen Komet.
Until you do, Komet says so when it starts and still opens from its menu bar icon.

## License

MIT
