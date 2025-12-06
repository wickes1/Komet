# Komet

Minimal macOS app launcher.

## Install

```bash
brew install --no-quarantine wickes1/tap/komet
```

## Upgrade

```bash
brew upgrade --no-quarantine wickes1/tap/komet
```

> **Note:** The `--no-quarantine` flag is required for unsigned apps. If you see a Gatekeeper warning, go to **System Settings → Privacy & Security** and click **Open Anyway**.

## After Upgrade

After upgrading, you need to re-grant Accessibility permission:

1. Quit Komet (`Cmd+Q` or click menu bar 🔍 icon)
2. Go to **System Settings → Privacy & Security → Accessibility**
3. Remove Komet from the list (select and click **−**)
4. Click **+** and add Komet back
5. Reopen Komet

This is a macOS limitation - permissions are tied to the app binary which changes on upgrade.

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
make app
make install
```

## Note

`Cmd+Space` conflicts with Spotlight. Disable it in:
**System Settings → Keyboard → Keyboard Shortcuts → Spotlight**

## License

MIT
