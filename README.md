# Terminal Dotfiles

These config are designed to my liking (can be kinda weird) so feel free to change stuff around. I tried making it as customizable as possible (while doing as less work as possible) so you might need to jump into the code to change some stuff (gl with that XD)

This repository contains configurations for **PowerShell** and **WezTerm**, designed to keep the existing Windows-native development environment intact.

## Important Note

This config requires **JetBrainsMono Nerd Font (Medium)** to be installed on the system.

If you are installing this config manually, download **JetBrainsMono Nerd Font** from the [this website](https://www.nerdfonts.com/font-downloads).

## Install (Windows)

### Automatic Setup

Run the bootstrap installer:

```powershell
irm https://raw.githubusercontent.com/itsWindi/terminal-rice/main/install.ps1 | iex
```

The installer configures PowerShell and WezTerm, backs up existing configurations before replacing them, and can optionally install WezTerm if it is not already present.

### Manual Setup

For PowerShell, copy:

```text
powershell/Microsoft.PowerShell_profile.ps1
```

to:

```text
$PROFILE
```

For WezTerm, copy the contents of:

```text
wezterm/
```

to:

```text
%USERPROFILE%\.config\wezterm\
```

See the component READMEs for their individual configuration details.

## Components

### PowerShell

Interactive PowerShell enhancements including predictive history, smart completion, word-by-word suggestion acceptance, and improved history search.

See [`powershell/README.md`](powershell/README.md).

### WezTerm

A modular, customizable terminal configuration with an interactive settings hub, themes, CWD inheritance, pane navigation, custom keybindings, and more.

See [`wezterm/README.md`](wezterm/README.md).
