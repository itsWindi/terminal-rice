# PowerShell Profile

Tried to make this similar to bash autocomplete. 

## Install (Windows)

1. Make sure PowerShell and PSReadLine are installed.
2. Copy `Microsoft.PowerShell_profile.ps1` to:
   `$PROFILE`
3. Restart PowerShell or reload the profile.

## Features

- **Inline history predictions:** Shows previous commands as inline suggestions.
- **Smart Tab:** Accepts an inline suggestion, otherwise uses normal PowerShell completion.
- **Longest completion:** Preserves PowerShell's longest unambiguous prefix completion.
- **Word-by-word suggestions:** `Right Arrow` accepts the next word of an inline suggestion.
- **History search:** `Up` / `Down` search command history and place the cursor at the end.
- **Clean history:** Removes duplicate history entries.
- **Quiet terminal:** Disables the terminal bell.

## Keybindings

| Keys | Action |
|---|---|
| `Tab` | Accept suggestion / normal completion |
| `Shift+Tab` | Previous completion |
| `Right Arrow` | Accept next suggestion word |
| `Up Arrow` | Search history backward |
| `Down Arrow` | Search history forward |
