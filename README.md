# GitCast.nvim

A comprehensive git dashboard for Neovim that provides an intuitive interface for git operations.

## Features

### 🚀 Core Features
- **Git Dashboard**: Unified view of git status, branches, commits, and staging
- **Interactive Branch Management**: Switch, create, and manage branches with ease
- **Smart Staging**: Stage/unstage files individually or by section
- **Commit History**: Browse and interact with recent commits
- **Conflict Detection**: Visual indicators for merge conflicts and potential issues
- **Performance Tracking**: Optional performance monitoring for git operations

### ⚡ Key Operations
- **Branch Operations**: Switch (`gsb`), create (`gcb`), rebase (`grm`), squash merge (`gsm`)
- **Staging Operations**: Stage (`<Tab>`), unstage (`<BS>`), stage all (`<S-Tab>`)
- **Commit Operations**: Commit (`gcm`), amend (`gca`), fixup (`gcf`)
- **Remote Operations**: Pull rebase (`gpr`), push (`gp`), force push (`gP`)

### 🎯 Smart Features
- **Configurable Tracking Branch**: Set per-repository tracking branch preferences
- **Ahead/Behind Indicators**: See how your branch compares to main/master
- **Conflict Warnings**: 🔥 for active conflicts, ⚠ for potential conflicts
- **File Diff Integration**: View detailed diffs with syntax highlighting

## Installation

### With [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "n1kben/gitcast.nvim",
  config = function()
    require("gitcast").setup({
      -- Optional: Enable performance tracking
      performance_tracking = false,
    })
  end,
  cmd = "GitCast",
  keys = {
    { "<leader>gg", "<cmd>GitCast<cr>", desc = "Open GitCast dashboard" },
  },
}
```

### With [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "n1kben/gitcast.nvim",
  config = function()
    require("gitcast").setup()
  end,
}
```

## Usage

### Opening the Dashboard
```vim
:GitCast
```
Or use your configured keybinding (e.g., `<leader>gg`)

### Dashboard Layout
```
Head: feature-branch (↑3 ↓1 ⚠2)
Tracking: main

Commits:
  abc1234 Add new feature +45 -12 (author) 2 hours ago
  def5678 Fix bug in parser +8 -3 (author) 1 day ago

Staged changes:
  M  src/main.lua
  A  src/new_file.lua

Unstaged changes:
  M  README.md
  D  old_file.lua

Untracked files:
  ?? temp.log
```

### Keybindings

#### Global Commands (available anywhere in dashboard)
| Key | Action |
|-----|--------|
| `g?` | Show help |
| `gcm` | Commit staged changes |
| `gca` | Commit amend (edit last commit) |
| `gcf` | Commit fixup (fixup to selected commit) |
| `gsb` | Switch to existing branch |
| `gcb` | Checkout new branch |
| `gpr` | Git pull rebase |
| `grm` | Rebase current branch onto tracking branch |
| `gsm` | Squash merge current branch into tracking branch |
| `gp` | Git push |
| `gP` | Git push force (with confirmation) |

#### Section-Specific Commands
| Key | Section | Action |
|-----|---------|--------|
| `<CR>` | Branch | Show branch details |
| `<CR>` | Tracking | Change tracking branch |
| `<CR>` | Commits | Show commit detail |
| `<CR>` | Files | Show file diff |
| `<Tab>` | Branch | Switch to existing branch |
| `<Tab>` | Files | Stage/unstage file |
| `<S-Tab>` | Files | Stage/unstage all in section |
| `<BS>` | Commits | Reset to commit |
| `<BS>` | Files | Checkout/unstage/delete file |
| `gf` | Files | Open file in editor |

## Configuration

### Basic Setup
```lua
require("gitcast").setup({
  -- Enable performance tracking for git operations
  performance_tracking = false,
})
```

### Tracking Branch Configuration
GitCast uses git config to store per-repository tracking branch preferences:

```bash
# Set tracking branch for current repository
git config --local gitcast.trackingbranch main

# View current setting
git config --local gitcast.trackingbranch
```

Or use the dashboard: navigate to "Tracking:" line and press `<CR>` to select a different branch.

## Requirements

- Neovim >= 0.8.0
- Git installed and accessible in PATH
- Terminal with Unicode support (for status icons)

## Status Indicators

| Icon | Meaning |
|------|---------|
| `↑3` | 3 commits ahead of tracking branch |
| `↓2` | 2 commits behind tracking branch |
| `🔥2` | 2 files with active merge conflicts |
| `⚠1` | 1 file with potential merge conflicts |
| `M` | Modified file |
| `A` | Added file |
| `D` | Deleted file |
| `??` | Untracked file |

## Performance Tracking

Enable performance tracking to monitor git operation times:

```lua
require("gitcast").setup({
  performance_tracking = true,
})
```

Performance data is displayed using Neovim's debug output with detailed timing information.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

MIT License - see LICENSE file for details.

## Credits

Developed by [@n1kben](https://github.com/n1kben) as a comprehensive git workflow solution for Neovim.