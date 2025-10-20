-- git-tracking.lua - Tracking branch management for gitcast
local M = {}
local sys = require('gitcast.system-utils')

-- Setup highlight groups for tracking module
function M.setup_highlights()
  vim.api.nvim_set_hl(0, "GitStatusHeader", { link = "Normal" })
end

-- Get virtual text configuration for tracking module
function M.get_virtual_text_config()
  return {
    default_hl_group = "Comment",
    namespace = "git_tracking_virtual_text"
  }
end

-- Get the configured tracking branch or default to main/master
function M.get_tracking_branch()
  -- First check git config for user preference
  local config_output = sys.system("git config --local gitcast.trackingbranch 2>/dev/null")
  if vim.v.shell_error == 0 and config_output ~= "" then
    local branch = config_output:gsub("%s+$", "")
    -- Verify the branch exists
    local verify_cmd = string.format("git show-ref --verify --quiet refs/heads/%s", vim.fn.shellescape(branch))
    sys.system(verify_cmd)
    if vim.v.shell_error == 0 then
      return branch
    end
  end
  
  -- Fall back to detecting main/master
  local branches_output = sys.system("git branch --format='%(refname:short)' 2>/dev/null")
  if vim.v.shell_error ~= 0 then
    return "main"
  end
  
  local has_main = false
  local has_master = false
  
  for line in branches_output:gmatch("[^\r\n]+") do
    if line == "main" then
      has_main = true
    elseif line == "master" then
      has_master = true
    end
  end
  
  -- Prefer main over master
  if has_main then
    return "main"
  elseif has_master then
    return "master"
  else
    return "main" -- fallback
  end
end

-- Set the tracking branch preference
function M.set_tracking_branch(branch_name)
  -- Validate the branch exists
  local verify_cmd = string.format("git show-ref --verify --quiet refs/heads/%s", vim.fn.shellescape(branch_name))
  sys.system(verify_cmd)
  if vim.v.shell_error ~= 0 then
    vim.notify(string.format("Branch '%s' does not exist", branch_name), vim.log.levels.ERROR)
    return false
  end
  
  -- Set the git config
  local config_cmd = string.format("git config --local gitcast.trackingbranch %s", vim.fn.shellescape(branch_name))
  sys.system(config_cmd)
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to set tracking branch preference", vim.log.levels.ERROR)
    return false
  end
  
  vim.notify(string.format("Set tracking branch to: %s", branch_name), vim.log.levels.INFO)
  return true
end

-- Get all local branches for tracking branch selection
local function get_local_branches()
  local branches_output = sys.system("git branch --format='%(refname:short)' 2>/dev/null")
  if vim.v.shell_error ~= 0 then
    return {}
  end
  
  local branches = {}
  for line in branches_output:gmatch("[^\r\n]+") do
    if line ~= "" then
      table.insert(branches, line)
    end
  end
  
  -- Sort branches with main/master first
  table.sort(branches, function(a, b)
    if a == "main" then return true end
    if b == "main" then return false end
    if a == "master" then return true end
    if b == "master" then return false end
    return a < b
  end)
  
  return branches
end

-- Show tracking branch picker
function M.show_tracking_branch_picker()
  local branches = get_local_branches()
  local current_tracking = M.get_tracking_branch()
  
  if #branches == 0 then
    vim.notify("No branches found", vim.log.levels.WARN)
    return
  end
  
  -- Create display with current selection marked
  local display_items = {}
  for _, branch in ipairs(branches) do
    local display_text = branch
    if branch == current_tracking then
      display_text = branch .. " (current)"
    end
    table.insert(display_items, display_text)
  end
  
  vim.ui.select(display_items, {
    prompt = "Select tracking branch:",
    format_item = function(item)
      return item
    end
  }, function(choice, idx)
    if choice and idx then
      local selected_branch = branches[idx]
      if selected_branch ~= current_tracking then
        if M.set_tracking_branch(selected_branch) then
          -- Refresh dashboard if callback is available
          if M._refresh_callback then
            M._refresh_callback()
          end
        end
      end
    end
  end)
end

-- Get tracking module for dashboard
function M.get_tracking_module()
  local tracking_branch = M.get_tracking_branch()
  
  -- Get current branch to compare
  local sys = require('gitcast.system-utils')
  local current_branch = sys.system("git rev-parse --abbrev-ref HEAD 2>/dev/null"):gsub("%s+$", "")
  
  -- Don't show tracking section if current branch equals tracking branch
  if current_branch == tracking_branch then
    return {
      lines = {},
      highlight_map = {},
      actions = {}
    }
  end
  
  local line_text = "Tracking: " .. tracking_branch
  
  return {
    lines = { line_text },
    highlight_map = {
      [1] = {
        { 1, 9, "Normal" },     -- "Tracking:"
        { 11, 10 + #tracking_branch, "Directory" } -- branch name
      }
    },
    actions = {
      [1] = function() M.show_tracking_branch_picker() end
    }
  }
end

-- Set refresh callback from dashboard
function M.set_refresh_callback(callback)
  M._refresh_callback = callback
end

-- Setup function
function M.setup()
  -- No user commands needed - only used through dashboard
end

return M