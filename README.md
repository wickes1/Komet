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
