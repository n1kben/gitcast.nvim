-- gitcast/init.lua - GitCast initialization and setup
local M = {}

-- Setup all gitcast modules
function M.setup(opts)
  opts = opts or {}
  
  -- Setup all modules
  require("gitcast.git-branch").setup()
  require("gitcast.git-staging").setup()
  require("gitcast.git-commit-detail").setup()
  require("gitcast.git-commits").setup()
  require("gitcast.git-tracking").setup()
  require("gitcast.git-dashboard").setup(opts)
  
  -- Create single GitCast command that opens the dashboard
  vim.api.nvim_create_user_command("GitCast", function()
    require("gitcast.git-dashboard").open_dashboard()
  end, { desc = "Open GitCast dashboard" })
end

M.open = function()
  require("gitcast.git-dashboard").open_dashboard()
end

return M