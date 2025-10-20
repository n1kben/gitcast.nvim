-- delta-diff.lua - Beautiful diff rendering using delta in terminal windows
local M = {}
local sys = require('gitcast.system-utils')

-- Check if delta is available
local function is_delta_available()
  return vim.fn.executable("delta") == 1
end

-- Simple terminal wrapper that prevents exit messages
local function start_terminal_job(cmd, opts)
  opts = opts or {}
  opts.term = true
  return vim.fn.jobstart(cmd, opts)
end

-- Create and configure a terminal buffer for displaying delta output
local function create_delta_terminal(title, cmd)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  local win = vim.api.nvim_get_current_win()
  
  vim.api.nvim_buf_set_name(buf, title)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'buflisted', false)
  
  -- Start the terminal job
  local job_id = start_terminal_job(cmd, {
    on_exit = function(_, exit_code)
      if exit_code ~= 0 then
        vim.notify("Git command failed", vim.log.levels.ERROR)
      end
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_set_option(buf, 'modifiable', false)
          vim.api.nvim_buf_set_option(buf, 'modified', false)
        end
      end)
    end
  })
  
  vim.cmd('stopinsert')
  return buf, win
end

-- Show git diff using delta
function M.show_git_diff(file, opts)
  opts = opts or {}
  
  if not is_delta_available() then
    vim.notify("Delta not found. Install delta for better diff rendering.", vim.log.levels.WARN)
    return
  end
  
  local title = opts.title or ("Diff: " .. file)
  
  -- Determine git diff command based on options
  local git_cmd
  if opts.cached then
    git_cmd = string.format("git diff --cached %s", vim.fn.shellescape(file))
  elseif opts.commit then
    git_cmd = string.format("git show %s -- %s", vim.fn.shellescape(opts.commit), vim.fn.shellescape(file))
  else
    git_cmd = string.format("git diff %s", vim.fn.shellescape(file))
  end
  
  local full_cmd = string.format("exec %s | delta --paging=never", git_cmd)
  return create_delta_terminal(title, full_cmd)
end

-- Show commit diff using delta
function M.show_commit_diff(commit_hash, opts)
  opts = opts or {}
  
  if not is_delta_available() then
    vim.notify("Delta not found. Install delta for better diff rendering.", vim.log.levels.WARN)
    return
  end
  
  local title = opts.title or ("Commit: " .. commit_hash:sub(1, 8))
  local full_cmd = string.format("exec git show %s | delta --paging=never", vim.fn.shellescape(commit_hash))
  return create_delta_terminal(title, full_cmd)
end

-- Show diff for untracked files (show entire file content as added)
function M.show_untracked_diff(file, opts)
  opts = opts or {}
  
  if not is_delta_available() then
    vim.notify("Delta not found. Install delta for better diff rendering.", vim.log.levels.WARN)
    return
  end
  
  local title = opts.title or ("New file: " .. file)
  local full_cmd = string.format("exec git diff --no-index /dev/null %s | delta --paging=never", 
    vim.fn.shellescape(file)
  )
  return create_delta_terminal(title, full_cmd)
end

-- Show branch file diff using delta
function M.show_branch_file_diff(base_branch, file, opts)
  opts = opts or {}
  
  if not is_delta_available() then
    vim.notify("Delta not found. Install delta for better diff rendering.", vim.log.levels.WARN)
    return
  end
  
  local title = opts.title or (string.format("Branch diff: %s vs %s", base_branch, file))
  local git_cmd = string.format("git diff %s...HEAD -- %s", 
    vim.fn.shellescape(base_branch), 
    vim.fn.shellescape(file)
  )
  local full_cmd = string.format("exec %s | delta --paging=never", git_cmd)
  return create_delta_terminal(title, full_cmd)
end

return M