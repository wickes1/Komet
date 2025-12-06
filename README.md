# Komet

Minimal macOS app launcher.

## Install

```bash
brew tap wickes1/tap
brew install --cask komet
```

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
