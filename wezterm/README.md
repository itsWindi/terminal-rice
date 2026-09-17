# WezTerm Config

## Install (Windows)

1. Make sure WezTerm is installed: https://wezterm.org/installation.html
2. Copy the files into:
   `%USERPROFILE%\.config\wezterm\`
   (create the folder if it doesn't exist)
3. Launch WezTerm. It picks up the config automatically.

## Modular Config Architecture

Settings, themes, and keybindings are decoupled into clean JSON files with automatic corruption recovery:
- `settings.json` — User preferences (active theme, default directory, shell, window size, font and spacing, typing indicator, pane navigation, toast notifications, opacity, backdrop blur).
- `themes.json` — Color schemes and accent palettes (built-in + custom themes).
- `keybinds.json` — Action keybindings.
- `settings.lua` — Settings manager, shell detector, key recorder, directory autocomplete browser, and corruption auto-recovery.
- `wezterm.lua` — Core window behavior, mouse bindings, link handlers.
- `keys.lua` — Action dispatcher, CWD inheritance, and Hyprland dwindle tiling logic.
- `theme.lua` — Theme and tab bar palette loader.
- `startup.lua` — Startup geometry and default working directory loader.
- `fonts.lua` — Font configurations.
- `tab.lua` — Lightweight tab titles with process labels and privilege status.

> **Corruption Auto-Recovery:** If any JSON file (`settings.json`, `themes.json`, `keybinds.json`) becomes corrupted with invalid syntax, WezTerm automatically backs up the damaged file to `<filename>_corrupted_<timestamp>.json`, restores a clean default configuration, and displays a desktop toast notification.

## Window Management & Title Bar Controls

- **Integrated Title Bar Buttons:** `window_decorations = "INTEGRATED_BUTTONS|RESIZE"` places fully functional Close, Maximize, and Minimize buttons cleanly in the tab bar.
- **Window Dragging:** Hold **Ctrl+Shift** and **Left Click Drag** anywhere in the terminal to move the window.
- **Hyperlinks:** URLs and links in the terminal open **only on `Ctrl + Click`**, preventing accidental clicks while highlighting text.

## Unified Settings Hub (`Alt+,`)

Press **`Alt+,`** to open the interactive settings hub:
1. **Color Theme:** Switch color schemes instantly and permanently.
2. **Window Size:** The default is `120x20` cells; enter custom dimensions (`'max'` or `<cols>x<rows>` e.g. `120x35`).
3. **Default Directory:** Interactive directory autocomplete browser (supports drill-down folder navigation, prefix typing, manual entry, or Windows folder dialog).
4. **Default Shell:** Detects all available shells on your PC (PowerShell 7, Windows PowerShell 5, Command Prompt, Git Bash, WSL, Nushell) and lets you set your default. Detection checks common install locations for each shell, scans your `PATH`, *and* falls back to `where.exe` for Microsoft Store / WindowsApps installs — so it finds shells installed via any method.
5. **Opacity & Blur:** Adjust window transparency (0%–100%, in 10% steps, plus a custom entry) and Windows 11 backdrop effects (Acrylic, Mica, Tabbed, Disabled). See "Opacity & Blur" below — the two settings interact in a way that isn't obvious from the numbers alone.
6. **Font & Spacing:** Enter custom font size (6–72pt), line height (0.5–3.0), and cell width (0.5–2.0) values. Changes apply and save immediately.
7. **Keybindings:** Customize any shortcut interactively, choose pane navigation keys, and record changes directly into `keybinds.json`. Conflicting shortcuts are rejected without changing the existing binding.
8. **Toast Notifications:** Enable or disable normal toast messages. JSON corruption and recovery warnings always remain enabled.
9. **Typing Indicator:** Choose the bar (`|`), underline (`_`), or block cursor style.

The right side of the tab bar shows `PRIV: ADMIN` for an elevated terminal or `PRIV: STANDARD` otherwise.

## Hyprland Dwindle Auto-Split

- **`Alt+P`** — Hyprland dwindle auto-split (opens in default directory).
- **`Alt+Shift+P`** — Hyprland dwindle auto-split with **current-directory inheritance** (opens in the exact working directory of the active pane).

Both keys now tile in the same direction for a given pane shape — they differ
only in whether the new pane inherits the focused pane's directory.

## Pane Navigation

Open **Alt+, → Keybindings → Pane Navigation** to choose one of these modes:

- **Alt + Arrow Keys:** The default layout.
- **Alt + HJKL:** Vim-style pane navigation.
- **Custom:** Choose the modifier and key for Left, Down, Up, and Right one at a time.

Custom navigation is checked only after all four directions are entered. Any
duplicate or invalid shortcut is rejected, the previous navigation settings are
kept, and the keybindings page shows a red error message above the reset option.

## CWD Inheritance (`Ctrl+Shift+T`, `Alt+Shift+P`)

`Ctrl+Shift+T` and `Alt+Shift+P` ask WezTerm for the *focused pane's* current
working directory and open the new tab/pane there.

**File manager (`Alt+E`):** Opens the focused pane's current working directory
with the operating system's registered default file manager. It does not call a
specific application, so File Pilot or another registered folder handler can
own the shortcut. If WezTerm cannot report the pane's CWD, it opens the
configured default directory (or the home directory) and shows a toast.

If CWD can't be determined, the new pane falls back to the default directory
and, when toast notifications are enabled.

**Administrator terminal (`Alt+Shift+A`):** Starts a new elevated `wezterm-gui.exe`
process with the focused pane's CWD. Windows displays the normal UAC prompt.

## Keybindings

| Keys | Action |
|---|---|
| Configured pane-navigation keys | Move between panes (forwards to Neovim automatically if running) |
| `Shift+Alt` + Arrow keys | Resize current pane |
| `Alt+\` | Split pane horizontally |
| `Alt+-` | Split pane vertically |
| `Shift+Alt+\|` | Split full window right |
| `Shift+Alt+_` | Split full window down |
| `Alt+P` | Hyprland dwindle auto-split |
| `Alt+Shift+P` | Hyprland auto-split (**Inherit Current CWD**) |
| `Ctrl+T` | New tab (Default directory) |
| `Ctrl+Shift+T` | New tab (**Inherit Current CWD**) |
| `Alt+E` | Open the active pane's CWD in the default file manager |
| `Alt+Shift+A` | Open a new elevated administrator terminal in the active pane's CWD |
| `Alt+Q` | Close current tab |
| `Ctrl+W` | Close current pane |
| `Alt+Z` | Zoom/unzoom current pane |
| `F11` | Toggle fullscreen |
| `Alt+[` / `Alt+]` | Previous / next tab |
| `Alt+Shift+{` / `Alt+Shift+}` | Move tab left / right |
| `Ctrl+1`–`Ctrl+9` | Jump to tab 1–9 |
| `Ctrl+C` | Smart copy / interrupt |
| `Ctrl+V` while Microsoft Edit is active | Paste from the clipboard into Edit |
| `Ctrl+=` / `Ctrl+-` | Increase / decrease font size |
| `Ctrl+Shift+P` | Open command palette |
| `Alt+,` | Unified Settings Hub |
| `Ctrl+Shift` + Left Drag | Drag & move window |
| `Ctrl` + Click | Open hyperlink |

## Unified Keybind Case Handling

WezTerm treats an uppercase single-letter `key` (e.g. `"Q"`) as implicitly
requiring Shift, regardless of what's in `mods` — so `{ key = "Q", mods =
"ALT" }` actually required `Alt+Shift+Q` to trigger, while the settings hub
displayed it as just `ALT + Q`. All single-letter keys are now normalized to
lowercase on load/save, so `mods` is the only thing that determines whether
Shift is needed, and the displayed combo always matches what you actually
need to press.
