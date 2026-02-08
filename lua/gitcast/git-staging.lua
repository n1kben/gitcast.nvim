-- git-staging.lua
local M = {}
local sys = require('gitcast.system-utils')
local utils = require('gitcast.utils')

-- Shared git status cache to avoid duplicate calls
local git_status_cache = nil
local cache_timestamp = 0
local CACHE_TTL = 100 -- milliseconds

-- Setup highlight groups for staging module
function M.setup_highlights()
  vim.api.nvim_set_hl(0, "GitStatusStaged", { link = "DiagnosticOk" })
  vim.api.nvim_set_hl(0, "GitStatusModified", { link = "DiagnosticWarn" })
  vim.api.nvim_set_hl(0, "GitStatusUntracked", { link = "DiagnosticError" })
  vim.api.nvim_set_hl(0, "GitStatusEmpty", { link = "Comment" })
  vim.api.nvim_set_hl(0, "GitFileAdded", { link = "DiffAdd" })
  vim.api.nvim_set_hl(0, "GitFileDeleted", { link = "DiffDelete" })
end

-- Get virtual text configuration for staging module
function M.get_virtual_text_config()
  return {
    default_hl_group = "Comment",
    namespace = "git_staging_virtual_text"
  }
end

-- Get line counts for untracked files (total lines as added)
local function get_untracked_line_counts(files)
  local untracked_counts = {}
  
  for _, file in ipairs(files) do
    local abs_file = utils.to_abs_path(file)
    if vim.fn.filereadable(abs_file) == 1 then
      local line_count = sys.system("wc -l < " .. vim.fn.shellescape(abs_file)):gsub("%s+", "")
      local count = tonumber(line_count) or 0
      untracked_counts[file] = { added = count, removed = 0 }
    else
      -- File doesn't exist or is not readable
      untracked_counts[file] = { added = 0, removed = 0 }
    end
  end
  
  return untracked_counts
end

-- Get line counts for files using git diff --numstat
local function get_line_counts()
  local staged_counts = {}
  local modified_counts = {}
  
  -- Get staged changes line counts
  local staged_output = sys.system("git diff --numstat --cached")
  if vim.v.shell_error == 0 and staged_output ~= "" then
    for line in staged_output:gmatch("[^\r\n]+") do
      local added, removed, file = line:match("^(%d+)\t(%d+)\t(.+)$")
      if added and removed and file then
        staged_counts[file] = { added = tonumber(added), removed = tonumber(removed) }
      end
    end
  end
  
  -- Get unstaged changes line counts
  local modified_output = sys.system("git diff --numstat")
  if vim.v.shell_error == 0 and modified_output ~= "" then
    for line in modified_output:gmatch("[^\r\n]+") do
      local added, removed, file = line:match("^(%d+)\t(%d+)\t(.+)$")
      if added and removed and file then
        modified_counts[file] = { added = tonumber(added), removed = tonumber(removed) }
      end
    end
  end
  
  return staged_counts, modified_counts
end

-- Get cached git status or fetch fresh data
local function get_git_status()
  local now = vim.loop.hrtime() / 1000000 -- Convert to milliseconds
  
  -- Return cached data if still fresh
  if git_status_cache and (now - cache_timestamp) < CACHE_TTL then
    return git_status_cache
  end
  
  -- Fetch fresh data
  local result = { staged = {}, modified = {}, untracked = {} }
  local staged_counts, modified_counts = get_line_counts()

  -- First pass: collect untracked files
  local untracked_files = {}
  local status_output = sys.system("git status -s")
  if vim.v.shell_error == 0 and status_output ~= "" then
    for line in status_output:gmatch("[^\r\n]+") do
      if line ~= "" and #line >= 3 then
        local index_status = line:sub(1, 1)
        local worktree_status = line:sub(2, 2)
        local file = line:sub(4)

        if index_status == "?" and worktree_status == "?" then
          table.insert(untracked_files, file)
        end
      end
    end
  end
  
  -- Get line counts for untracked files
  local untracked_counts = get_untracked_line_counts(untracked_files)

  -- Second pass: process all files with their line counts
  if vim.v.shell_error == 0 and status_output ~= "" then
    for line in status_output:gmatch("[^\r\n]+") do
      if line ~= "" and #line >= 3 then
        local index_status = line:sub(1, 1)
        local worktree_status = line:sub(2, 2)
        local file = line:sub(4)

        -- Handle staged changes (index status)
        if index_status ~= " " and index_status ~= "?" then
          local counts = staged_counts[file] or { added = 0, removed = 0 }
          table.insert(result.staged, { 
            status = index_status, 
            file = file,
            added = counts.added,
            removed = counts.removed
          })
        end

        -- Handle unstaged changes (worktree status)
        if worktree_status ~= " " and worktree_status ~= "?" then
          local counts = modified_counts[file] or { added = 0, removed = 0 }
          table.insert(result.modified, { 
            status = worktree_status, 
            file = file,
            added = counts.added,
            removed = counts.removed
          })
        end

        -- Handle untracked files
        if index_status == "?" and worktree_status == "?" then
          local counts = untracked_counts[file] or { added = 0, removed = 0 }
          table.insert(result.untracked, { 
            status = "??", 
            file = file,
            added = counts.added,
            removed = counts.removed
          })
        end

      end
    end
  end

  -- Update cache
  git_status_cache = result
  cache_timestamp = now
  
  return result
end

-- Clear cache when git operations modify state
function M.clear_cache()
  git_status_cache = nil
  cache_timestamp = 0
end

-- Fetch git status data without caching (for dashboard use)
function M.fetch_git_status()
  -- Fetch fresh data
  local result = { staged = {}, modified = {}, untracked = {} }

  -- Get staged files with counts
  local staged_output = sys.system("git diff --numstat --cached")
  
  if vim.v.shell_error == 0 and staged_output ~= "" then
    for line in staged_output:gmatch("[^\r\n]+") do
      if line ~= "" then
        local parts = vim.split(line, "\t")
        if #parts >= 3 then
          local added = parts[1] == "-" and 0 or tonumber(parts[1]) or 0
          local removed = parts[2] == "-" and 0 or tonumber(parts[2]) or 0
          local file = parts[3]
          table.insert(result.staged, { 
            status = "M", -- We could determine A/M/D but M is sufficient for display
            file = file,
            added = added,
            removed = removed
          })
        end
      end
    end
  end

  -- Get modified files with counts
  local modified_output = sys.system("git diff --numstat")
  
  if vim.v.shell_error == 0 and modified_output ~= "" then
    for line in modified_output:gmatch("[^\r\n]+") do
      if line ~= "" then
        local parts = vim.split(line, "\t")
        if #parts >= 3 then
          local added = parts[1] == "-" and 0 or tonumber(parts[1]) or 0
          local removed = parts[2] == "-" and 0 or tonumber(parts[2]) or 0
          local file = parts[3]
          table.insert(result.modified, { 
            status = "M",
            file = file,
            added = added,
            removed = removed
          })
        end
      end
    end
  end

  -- Get untracked files
  local untracked_output = sys.system("git ls-files --others --exclude-standard --full-name")
  
  if vim.v.shell_error == 0 and untracked_output ~= "" then
    for line in untracked_output:gmatch("[^\r\n]+") do
      if line ~= "" then
        -- Get line count for untracked file
        local added = 0
        local abs_line = utils.to_abs_path(line)
        if vim.fn.filereadable(abs_line) == 1 then
          local content = vim.fn.readfile(abs_line)
          added = #content
        end
        
        table.insert(result.untracked, { 
          status = "??", 
          file = line,
          added = added,
          removed = 0
        })
      end
    end
  end

  return result
end

-- Stage a file
function M.stage_file(file)
  local abs_file = utils.to_abs_path(file)
  local file_exists = vim.fn.filereadable(abs_file) == 1
  local dir_exists = vim.fn.isdirectory(abs_file) == 1

  local cmd_result
  if file_exists or dir_exists then
    cmd_result = sys.system("git add " .. vim.fn.shellescape(abs_file))
  else
    -- File is deleted, use git rm to stage the deletion
    cmd_result = sys.system("git rm " .. vim.fn.shellescape(abs_file))
  end

  if vim.v.shell_error ~= 0 then
    vim.notify("Git add failed: " .. cmd_result, vim.log.levels.ERROR)
    return false
  end
  return true
end

-- Unstage a file
function M.unstage_file(file)
  local abs_file = utils.to_abs_path(file)
  local has_commits = sys.system("git rev-parse --verify HEAD 2>/dev/null")
  local cmd_result

  if vim.v.shell_error == 0 then
    -- Has commits, can use reset HEAD
    cmd_result = sys.system("git reset HEAD " .. vim.fn.shellescape(abs_file))
  else
    -- No commits yet, use rm --cached
    cmd_result = sys.system("git rm --cached " .. vim.fn.shellescape(abs_file))
  end

  if vim.v.shell_error ~= 0 then
    vim.notify("Git unstage failed: " .. cmd_result, vim.log.levels.ERROR)
    return false
  end
  return true
end

-- Stage all changes (modified, deleted, and untracked files)
function M.stage_all()
  local cmd_result = sys.system("git add -A")
  
  if vim.v.shell_error ~= 0 then
    vim.notify("Git add -A failed: " .. cmd_result, vim.log.levels.ERROR)
    return false
  end
  
  vim.notify("All changes staged", vim.log.levels.INFO)
  if M._refresh_callback then M._refresh_callback() end
  return true
end

-- Stage all files in a specific section
function M.stage_all_in_section(section_type)
  local git_data = get_git_status()
  local files_to_stage = {}
  local action_description = ""
  
  if section_type == "untracked" then
    files_to_stage = git_data.untracked
    action_description = "untracked files"
  elseif section_type == "modified" then
    files_to_stage = git_data.modified
    action_description = "modified files"
  elseif section_type == "staged" then
    -- For staged files, we want to unstage them
    files_to_stage = git_data.staged
    action_description = "staged files"
  else
    vim.notify("Unknown section type: " .. section_type, vim.log.levels.ERROR)
    return false
  end
  
  if #files_to_stage == 0 then
    vim.notify("No " .. action_description .. " to process", vim.log.levels.INFO)
    return true
  end
  
  local success_count = 0
  local total_count = #files_to_stage
  
  for _, file_info in ipairs(files_to_stage) do
    local file = type(file_info) == "string" and file_info or file_info.file
    local success = false
    
    if section_type == "staged" then
      -- Unstage the file
      success = M.unstage_file(file)
    else
      -- Stage the file
      success = M.stage_file(file)
    end
    
    if success then
      success_count = success_count + 1
    end
  end
  
  if success_count == total_count then
    if section_type == "staged" then
      vim.notify(string.format("Unstaged %d files", success_count), vim.log.levels.INFO)
    else
      vim.notify(string.format("Staged %d %s", success_count, action_description), vim.log.levels.INFO)
    end
  else
    vim.notify(string.format("Processed %d/%d files successfully", success_count, total_count), vim.log.levels.WARN)
  end
  
  if M._refresh_callback then M._refresh_callback() end
  return success_count > 0
end

-- Checkout/discard changes to a file
function M.checkout_file(file)
  local abs_file = utils.to_abs_path(file)
  local cmd_result = sys.system("git checkout -- " .. vim.fn.shellescape(abs_file))

  if vim.v.shell_error ~= 0 then
    vim.notify("Git checkout failed: " .. cmd_result, vim.log.levels.ERROR)
    return false
  end
  return true
end

-- Delete an untracked file
function M.delete_untracked_file(file)
  local abs_file = utils.to_abs_path(file)
  local is_dir = vim.fn.isdirectory(abs_file) == 1
  local success

  if is_dir then
    success = vim.fn.delete(abs_file, "rf")
  else
    success = vim.fn.delete(abs_file)
  end

  if success == 0 then
    vim.notify("Deleted " .. file, vim.log.levels.INFO)
    return true
  else
    vim.notify("Failed to delete " .. file, vim.log.levels.ERROR)
    return false
  end
end

-- Format line counts for inline display (matching commit detail format)
local function format_line_counts_inline(added, removed)
  if added == 0 and removed == 0 then
    return "", {}
  end
  
  local text = string.format("+%d -%d", added, removed)
  local highlights = {}
  
  -- Find positions for highlighting
  local add_text = "+" .. added
  local rem_text = "-" .. removed
  
  local add_start, add_end = string.find(text, add_text, 1, true)
  local rem_start, rem_end = string.find(text, rem_text, 1, true)
  
  if add_start and add_end then
    table.insert(highlights, { add_start - 1, add_end, "GitFileAdded" })
  end
  if rem_start and rem_end then
    table.insert(highlights, { rem_start - 1, rem_end, "GitFileDeleted" })
  end
  
  return " " .. text, highlights
end

-- Generic module builder using composition
local function create_section_module(files, highlight_color, cr_action, tab_action, bs_action)
  local lines = {}
  local file_map = {}
  local highlight_map = {}
  local actions = {}

  for i, item in ipairs(files) do
    local line_num = #lines + 1
    local line_counts_text, line_counts_highlights = format_line_counts_inline(item.added or 0, item.removed or 0)
    local display_line = string.format("  %s%s %s", item.status, line_counts_text, item.file)
    table.insert(lines, display_line)
    file_map[line_num] = item.file
    
    -- Create highlight map with multiple ranges
    local highlights = {}
    
    -- Status character highlight (handle both single char and ?? status)
    local status_len = #item.status
    table.insert(highlights, { 3, 2 + status_len, highlight_color })
    
    -- Line count highlights (adjust offset based on status length)
    local status_end = 3 + status_len
    if #line_counts_highlights > 0 then
      for _, hl in ipairs(line_counts_highlights) do
        local start_col, end_col, hl_group = hl[1], hl[2], hl[3]
        table.insert(highlights, { status_end + start_col + 1, status_end + end_col, hl_group })
      end
    end
    
    -- File name highlight (adjust based on status length and line counts)
    local file_start = status_end + #line_counts_text + 1 
    table.insert(highlights, { file_start, #display_line, "Directory" })
    
    highlight_map[line_num] = highlights
    
    -- Action for <CR>
    actions[line_num] = function()
      cr_action(item.file)
    end
  end

  if #files == 0 then
    table.insert(lines, "  (no files)")
    highlight_map[#lines] = "GitStatusEmpty"
  end

  return {
    lines = lines,
    file_map = file_map,
    highlight_map = highlight_map,
    actions = actions,
    
    -- Add file open action for gf
    gf_action = function(line_num)
      local file = file_map[line_num]
      if file then
        vim.cmd('edit ' .. vim.fn.fnameescape(utils.to_abs_path(file)))
      end
    end,
    
    -- Add tab action
    tab_action = function(line_num)
      local file = file_map[line_num]
      if file then
        if tab_action(file) then
          if M._refresh_callback then M._refresh_callback() end
        end
      end
    end,
    
    -- Add backspace action 
    bs_action = function(line_num)
      local file = file_map[line_num]
      if file then
        bs_action(file)
      end
    end
  }
end

-- Get staged files module for dashboard
function M.get_staged_module(git_data)
  git_data = git_data or get_git_status()  -- Fallback for backward compatibility
  return create_section_module(
    git_data.staged,
    "GitStatusStaged",
    -- <CR> action: show cached diff
    function(file)
      local delta_diff = require('gitcast.delta-diff')
      delta_diff.show_git_diff(file, { cached = true, title = "Staged: " .. file })
    end,
    -- <Tab> action: unstage
    function(file)
      return M.unstage_file(file)
    end,
    -- <BS> action: unstage with confirmation
    function(file)
      vim.ui.confirm({
        msg = "Unstage " .. file .. "?",
        default = false
      }, function(confirmed)
        if confirmed and M.unstage_file(file) then
          if M._refresh_callback then M._refresh_callback() end
        end
      end)
    end
  )
end

-- Get modified files module for dashboard
function M.get_modified_module(git_data)
  git_data = git_data or get_git_status()  -- Fallback for backward compatibility
  return create_section_module(
    git_data.modified,
    "GitStatusModified",
    -- <CR> action: show diff
    function(file)
      local delta_diff = require('gitcast.delta-diff')
      delta_diff.show_git_diff(file, { title = "Modified: " .. file })
    end,
    -- <Tab> action: stage
    function(file)
      return M.stage_file(file)
    end,
    -- <BS> action: checkout with confirmation
    function(file)
      vim.ui.confirm({
        msg = "Checkout " .. file .. "? This will discard all changes.",
        default = false
      }, function(confirmed)
        if confirmed and M.checkout_file(file) then
          if M._refresh_callback then M._refresh_callback() end
        end
      end)
    end
  )
end

-- Get untracked files module for dashboard
function M.get_untracked_module(git_data)
  git_data = git_data or get_git_status()  -- Fallback for backward compatibility
  return create_section_module(
    git_data.untracked,
    "GitStatusUntracked",
    -- <CR> action: show diff or edit new file
    function(file)
      local abs_file = utils.to_abs_path(file)
      if vim.fn.filereadable(abs_file) == 1 then
        local delta_diff = require('gitcast.delta-diff')
        delta_diff.show_untracked_diff(abs_file, { title = "New file: " .. file })
      else
        vim.cmd('edit ' .. vim.fn.fnameescape(abs_file))
      end
    end,
    -- <Tab> action: stage
    function(file)
      return M.stage_file(file)
    end,
    -- <BS> action: delete with confirmation
    function(file)
      local is_dir = vim.fn.isdirectory(file) == 1
      local item_type = is_dir and "folder" or "file"
      vim.ui.confirm({
        msg = "Delete untracked " .. item_type .. " " .. file .. "? This cannot be undone.",
        default = false
      }, function(confirmed)
        if confirmed and M.delete_untracked_file(file) then
          if M._refresh_callback then M._refresh_callback() end
        end
      end)
    end
  )
end

-- Set refresh callback from dashboard
function M.set_refresh_callback(callback)
  M._refresh_callback = callback
end




-- Check if there are staged changes for committing
function M.has_staged_changes()
  local status_output = sys.system("git status --porcelain")
  
  if vim.v.shell_error == 0 and status_output ~= "" then
    for line in status_output:gmatch("[^\r\n]+") do
      if line ~= "" and #line >= 2 then
        local index_status = line:sub(1, 1)
        if index_status ~= " " and index_status ~= "?" then
          return true
        end
      end
    end
  end
  return false
end

-- Commit staged changes
function M.commit_staged_changes()
  if not M.has_staged_changes() then
    vim.notify("No staged changes to commit", vim.log.levels.WARN)
    return false
  end

  -- Force a redraw to ensure clean screen state after system calls in has_staged_changes(),
  -- otherwise vim.ui.input() may render with a stale/corrupt command line display
  vim.cmd('redraw')

  vim.ui.input({ prompt = "Commit message: " }, function(commit_message)
    if not commit_message or commit_message == "" then
      vim.notify("Commit cancelled - no message provided", vim.log.levels.INFO)
      return
    end

    local cmd_result = sys.system("git commit --no-verify -m " .. vim.fn.shellescape(commit_message))

    if vim.v.shell_error ~= 0 then
      vim.notify("Git commit failed: " .. cmd_result, vim.log.levels.ERROR)
      return
    end

    vim.notify("Commit created successfully", vim.log.levels.INFO)
    if M._refresh_callback then M._refresh_callback() end
  end)
  
  return true
end

-- Commit amend (edit last commit)
function M.commit_amend()
  if not M.has_staged_changes() then
    vim.notify("No staged changes for amend", vim.log.levels.WARN)
    return false
  end

  local cmd_result = sys.system("git commit --amend --no-edit --no-verify")

  if vim.v.shell_error ~= 0 then
    vim.notify("Git commit amend failed: " .. cmd_result, vim.log.levels.ERROR)
    return false
  end

  vim.notify("Commit amended successfully", vim.log.levels.INFO)
  if M._refresh_callback then M._refresh_callback() end
  return true
end

-- Commit fixup to a specific commit
function M.commit_fixup()
  if not M.has_staged_changes() then
    vim.notify("No staged changes for fixup", vim.log.levels.WARN)
    return false
  end

  -- Get recent commits for selection
  local commits_output = sys.system("git log --oneline -n 20")
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to get commit list", vim.log.levels.ERROR)
    return false
  end

  local commits = {}
  for line in commits_output:gmatch("[^\r\n]+") do
    if line ~= "" then
      local hash, message = line:match("^([a-f0-9]+)%s+(.+)$")
      if hash and message then
        table.insert(commits, string.format("%s %s", hash, message))
      end
    end
  end

  if #commits == 0 then
    vim.notify("No commits found for fixup", vim.log.levels.ERROR)
    return false
  end

  vim.ui.select(commits, {
    prompt = "Select commit to fixup:",
    format_item = function(item)
      return item
    end
  }, function(choice)
    if not choice then
      return
    end

    local commit_hash = choice:match("^([a-f0-9]+)")
    if not commit_hash then
      vim.notify("Invalid commit selection", vim.log.levels.ERROR)
      return
    end

    local cmd_result = sys.system(string.format("git commit --fixup=%s --no-verify", commit_hash))

    if vim.v.shell_error ~= 0 then
      vim.notify("Git commit fixup failed: " .. cmd_result, vim.log.levels.ERROR)
      return
    end

    vim.notify(string.format("Fixup commit created for %s", commit_hash:sub(1, 8)), vim.log.levels.INFO)
    if M._refresh_callback then M._refresh_callback() end
  end)

  return true
end

-- Setup function
function M.setup()
  -- No user commands, functionality accessed through dashboard
end

return M