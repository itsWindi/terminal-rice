# ==========================================
# PowerShell interactive setup
# ==========================================

Import-Module PSReadLine

# ------------------------------------------
# Predictive history
# ------------------------------------------

Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle InlineView

# No annoying terminal bell
Set-PSReadLineOption -BellStyle None

# Keep history clean
Set-PSReadLineOption -HistoryNoDuplicates

# When recalling history, put cursor at the end
Set-PSReadLineOption -HistorySearchCursorMovesToEnd

# ------------------------------------------
# TAB
# ------------------------------------------
#
# First:
#   accept an inline history suggestion
#
# If there is no suggestion:
#   perform normal PowerShell completion
#
# This gives us:
#
#   cl<Tab>
#       -> clear        (if "clear" is a history suggestion)
#
#   cd bu<Tab>
#       -> cd buil      (longest unambiguous completion)
#

Set-PSReadLineKeyHandler -Key Tab `
    -BriefDescription "AcceptSuggestionOrComplete" `
    -LongDescription "Accept history suggestion, otherwise perform completion" `
    -ScriptBlock {
        param($key, $arg)

        $before = $null
        $cursor = $null

        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState(
            [ref]$before,
            [ref]$cursor
        )

        # Try to accept the inline prediction
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptSuggestion(
            $key,
            $arg
        )

        # See whether the prediction actually changed the line
        $after = $null
        $cursor = $null

        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState(
            [ref]$after,
            [ref]$cursor
        )

        # No prediction was accepted -> do normal completion
        if ($after -eq $before) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Complete(
                $key,
                $arg
            )
        }
    }

# Shift+Tab = previous completion
Set-PSReadLineKeyHandler -Key Shift+Tab -Function TabCompletePrevious

# ------------------------------------------
# RIGHT ARROW
# ------------------------------------------
#
# Normal behavior:
#   move one character right
#
# At the end of the typed text:
#   accept ONE WORD of the inline prediction
#
# Example:
#
#   gi[ t clone https://github.com/... ]
#     ↓ Right
#   git
#     ↓ Right
#   git clone
#     ↓ Right
#   git clone https://github.com/...
#

Set-PSReadLineKeyHandler -Key RightArrow `
    -BriefDescription "ForwardCharOrAcceptSuggestionWord" `
    -LongDescription "Move right, or accept the next prediction word" `
    -ScriptBlock {
        param($key, $arg)

        $line = $null
        $cursor = $null

        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState(
            [ref]$line,
            [ref]$cursor
        )

        if ($cursor -lt $line.Length) {
            [Microsoft.PowerShell.PSConsoleReadLine]::ForwardChar(
                $key,
                $arg
            )
        }
        else {
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptNextSuggestionWord(
                $key,
                $arg
            )
        }
    }

# ------------------------------------------
# HISTORY SEARCH
# ------------------------------------------

Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward