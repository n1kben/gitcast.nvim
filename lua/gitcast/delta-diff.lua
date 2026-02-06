-- delta-diff.lua - Beautiful diff rendering using delta in terminal windows
local M = {}

-- Check if delta is available
local function is_delta_available()
  return vim.fn.executable("delta") == 1
end

-- Create and configure a terminal buffer for displaying delta output
local function create_delta_terminal(title, cmd)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  local win = vim.api.nvim_get_current_win()

  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'buflisted', false)

  -- Append sleep to keep the process alive so Neovim doesn't show [process exited 0].
  local full_cmd = cmd .. "; sleep 86400"
  local job_id = vim.fn.jobstart(full_cmd, { term = true })

  -- Set buffer name after terminal starts so it overrides the command string
  vim.api.nvim_buf_set_name(buf, title)

  -- Close helper: stop the job then force-wipe the buffer
  local function close_buffer()
    pcall(vim.fn.jobstop, job_id)
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  vim.keymap.set('n', 'q', close_buffer, { buffer = buf, silent = true })
  vim.keymap.set('n', '<Esc>', close_buffer, { buffer = buf, silent = true })

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
  
  local full_cmd = string.format("%s | delta --paging=never", git_cmd)
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
  local full_cmd = string.format("git show %s | delta --paging=never", vim.fn.shellescape(commit_hash))
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
  local full_cmd = string.format("git diff --no-index /dev/null %s | delta --paging=never", 
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
  local full_cmd = string.format("%s | delta --paging=never", git_cmd)
  return create_delta_terminal(title, full_cmd)
end

return M