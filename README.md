# GitCast.nvim

A comprehensive git dashboard for Neovim that provides an intuitive interface for git operations.

### Dashboard
<img width="886" height="452" alt="Screenshot 2025-10-20 at 10 57 57" src="https://github.com/user-attachments/assets/38336467-ff7b-4d56-96ea-d83d8e8d5a63" />

### Commit detail
<img width="530" height="329" alt="Screenshot 2025-10-20 at 10 58 10" src="https://github.com/user-attachments/assets/6308a26d-2f2d-4e06-bfd0-abb0c41d8f6e" />

### Comparing against tracking branch
<img width="522" height="325" alt="Screenshot 2025-10-20 at 10 58 45" src="https://github.com/user-attachments/assets/25b39322-e97e-43d9-b2dd-a2d15de74c21" />

## Installation

### With [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "n1kben/gitcast.nvim",
  config = function()
    require("gitcast").setup()
  end,
  cmd = "GitCast",
  keys = {
    { "<leader>g", "<cmd>GitCast<cr>", desc = "Open GitCast dashboard" },
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
Or use your configured keybinding (e.g., `<leader>g`)

### Keybindings
`g?` Show help

## Configuration

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
- Delta (for file diff)

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
