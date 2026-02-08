-- git-branch.lua
local M = {}
local sys = require('gitcast.system-utils')
local async_sys = require('gitcast.async-system')

-- Setup highlight groups for branch module
function M.setup_highlights()
  vim.api.nvim_set_hl(0, "GitStatusHeader", { link = "Normal" })
end

-- Get virtual text configuration for branch module
function M.get_virtual_text_config()
  return {
    default_hl_group = "Comment",
    namespace = "git_branch_virtual_text"
  }
end

-- Get current branch and status info efficiently in one call
local function get_branch_info()
  local status_output = sys.system("git status -b --porcelain=v1 2>/dev/null")
  
  if vim.v.shell_error ~= 0 then
    return {
      branch = "HEAD",
      ahead = 0,
      behind = 0,
      tracking = nil
    }
  end
  
  local first_line = status_output:match("([^\r\n]+)")
  if not first_line then
    return {
      branch = "HEAD", 
      ahead = 0,
      behind = 0,
      tracking = nil
    }
  end
  
  -- Parse branch line: "## branch...tracking [ahead X, behind Y]"
  local branch = first_line:match("## ([^%.%s]+)")
  local tracking = first_line:match("%.%.%.([^%s%[]+)")
  local ahead = tonumber(first_line:match("ahead (%d+)")) or 0
  local behind = tonumber(first_line:match("behind (%d+)")) or 0
  
  return {
    branch = branch or "HEAD",
    ahead = ahead,
    behind = behind,
    tracking = tracking
  }
end

-- Get all local branches for branch switching
local function get_local_branches()
  local branch_info = get_branch_info()
  local current_branch = branch_info.branch
  local local_branches_output = sys.system("git branch --format='%(refname:short)'")
  if vim.v.shell_error ~= 0 then
    return {}
  end

  local all_local_branches = {}
  for line in local_branches_output:gmatch("[^\r\n]+") do
    if line ~= "" and line ~= current_branch then
      all_local_branches[line] = true
    end
  end

  -- Get recent checkout history from reflog
  local reflog_output = sys.system("git reflog --grep-reflog='checkout: moving from' --format='%gs' -n 30")

  local branches = {}
  local seen = {}

  if vim.v.shell_error == 0 and reflog_output ~= "" then
    for line in reflog_output:gmatch("[^\r\n]+") do
      local from_branch = line:match("checkout: moving from ([^%s]+) to")

      if from_branch and
          all_local_branches[from_branch] and
          not seen[from_branch] and
          not from_branch:match("^[0-9a-f]+$") then
        table.insert(branches, from_branch)
        seen[from_branch] = true
      end
    end
  end

  -- Add remaining local branches not in reflog
  for branch, _ in pairs(all_local_branches) do
    if not seen[branch] then
      table.insert(branches, branch)
    end
  end

  return branches
end

-- Switch to a branch
function M.switch_branch(branch_name)
  local result = sys.system("git checkout " .. vim.fn.shellescape(branch_name))
  
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to checkout branch: " .. result, vim.log.levels.ERROR)
    return false
  else
    vim.notify("Switched to branch: " .. branch_name, vim.log.levels.INFO)
    -- Refresh dashboard if callback is available
    if M._refresh_callback then
      M._refresh_callback()
    end
    return true
  end
end

-- Create new branch
function M.create_branch(branch_name)
  -- Validate branch name
  if branch_name:match("[^%w%-_/]") then
    vim.notify("Invalid branch name. Use only letters, numbers, hyphens, underscores, and slashes.", vim.log.levels.ERROR)
    return false
  end

  local cmd = "git checkout -b " .. vim.fn.shellescape(branch_name)
  local result = sys.system(cmd)

  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to create branch: " .. result, vim.log.levels.ERROR)
    return false
  else
    vim.notify("Created and switched to branch: " .. branch_name, vim.log.levels.INFO)
    return true
  end
end

-- Show branch picker using vim.ui.select
function M.show_branch_picker()
  local branches = get_local_branches()
  
  if #branches == 0 then
    vim.notify("No other branches found", vim.log.levels.WARN)
    return
  end

  vim.ui.select(branches, {
    prompt = "Switch to branch:",
  }, function(choice)
    if choice then
      M.switch_branch(choice)
    end
  end)
end

-- Show create branch prompt
function M.show_create_branch_prompt()
  vim.ui.input({ prompt = "New branch name: " }, function(branch_name)
    if not branch_name or branch_name == "" then
      vim.notify("Branch creation cancelled", vim.log.levels.INFO)
      return
    end
    M.create_branch(branch_name)
  end)
end

-- Get current branch name
local function get_current_branch()
  local branch_info = get_branch_info()
  return branch_info.branch
end

-- Get branch status compared to tracking branch or configured base
local function get_branch_status(current_branch, tracking_branch)
  local branch_info = get_branch_info()
  
  -- If we have tracking branch info, use it
  if branch_info.tracking and (branch_info.ahead > 0 or branch_info.behind > 0) then
    return {
      ahead = branch_info.ahead,
      behind = branch_info.behind,
      tracking = branch_info.tracking
    }
  end
  
  -- Otherwise, compare with configured tracking branch if we're not on it
  if current_branch ~= tracking_branch then
    local count_cmd = string.format("git rev-list --left-right --count %s...%s 2>/dev/null", 
      vim.fn.shellescape(current_branch), vim.fn.shellescape(tracking_branch))
    local count_output = sys.system(count_cmd):gsub("%s+$", "")
    
    if vim.v.shell_error == 0 and count_output ~= "" then
      local ahead, behind = count_output:match("(%d+)%s+(%d+)")
      if ahead and behind then
        return {
          ahead = tonumber(ahead),
          behind = tonumber(behind),
          tracking = tracking_branch
        }
      end
    end
  end
  
  -- Fallback to original tracking info
  return {
    ahead = branch_info.ahead,
    behind = branch_info.behind,
    tracking = branch_info.tracking
  }
end

-- Get the main branch name (main, master, or default) - simplified version
local function get_main_branch()
  -- Get all local branches in one call and check which exists
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

-- Check for potential merge/rebase conflicts
local function get_conflict_details(current_branch, main_branch)
  local conflict_info = {
    active_conflicts = {},
    potential_conflicts = {}
  }
  
  -- Check for active conflicts (currently unresolved)
  local status_output = sys.system("git status --porcelain")
  if vim.v.shell_error == 0 then
    for line in status_output:gmatch("[^\r\n]+") do
      if line:match("^UU ") or line:match("^AA ") or line:match("^DD ") then
        local file = line:sub(4)
        table.insert(conflict_info.active_conflicts, file)
      end
    end
  end
  
  -- Check for potential conflicts using merge-tree (dry-run merge)
  local merge_base_cmd = string.format("git merge-base %s %s", 
    vim.fn.shellescape(current_branch), vim.fn.shellescape(main_branch))
  local merge_base = sys.system(merge_base_cmd):gsub("%s+$", "")
  
  if vim.v.shell_error == 0 and merge_base ~= "" then
    -- Use merge-tree to detect potential conflicts
    local merge_tree_cmd = string.format("git merge-tree %s %s %s 2>/dev/null", 
      vim.fn.shellescape(merge_base), 
      vim.fn.shellescape(current_branch), 
      vim.fn.shellescape(main_branch))
    local merge_tree_output = sys.system(merge_tree_cmd)
    
    if vim.v.shell_error == 0 and merge_tree_output ~= "" then
      -- Parse merge-tree output for conflict markers
      local has_conflicts = false
      local current_file = nil
      
      for line in merge_tree_output:gmatch("[^\r\n]+") do
        -- Look for conflict markers or file headers indicating conflicts
        if line:match("^<<<<<<< ") or line:match("^=======$") or line:match("^>>>>>>> ") then
          has_conflicts = true
        elseif line:match("^@@ ") and current_file then
          -- We're in a diff section, conflicts possible
          has_conflicts = true
        elseif line:match("^%+%+%+ b/(.+)") then
          current_file = line:match("^%+%+%+ b/(.+)")
          if has_conflicts and current_file then
            -- Only add if not already in active conflicts
            local already_active = false
            for _, active_file in ipairs(conflict_info.active_conflicts) do
              if active_file == current_file then
                already_active = true
                break
              end
            end
            if not already_active then
              table.insert(conflict_info.potential_conflicts, current_file)
            end
            has_conflicts = false
          end
        end
      end
    end
  end
  
  return conflict_info
end

-- This function is no longer needed since we get status info from git status command

-- Get branch module for dashboard (optimized version)
function M.get_branch_module()
  -- Get all branch info in one efficient call
  local branch_info = get_branch_info()
  
  -- Get configured tracking branch
  local git_tracking = require('gitcast.git-tracking')
  local tracking_branch = git_tracking.get_tracking_branch()
  
  -- Don't show status if we're on the tracking branch
  local show_status = branch_info.branch ~= tracking_branch
  local head_line = "Head: " .. branch_info.branch
  
  if show_status then
    local status_parts = {}
    
    -- Get enhanced branch status (tracking or vs configured base)
    local branch_status = get_branch_status(branch_info.branch, tracking_branch)
    
    if branch_status.ahead > 0 then
      table.insert(status_parts, string.format("↑%d", branch_status.ahead))
    end
    if branch_status.behind > 0 then
      table.insert(status_parts, string.format("↓%d", branch_status.behind))
    end
    
    -- Temporarily disable expensive conflict detection for performance
    -- TODO: Make this async or cache results
    -- local conflict_info = get_conflict_details(branch_info.branch, tracking_branch)
    -- local total_conflicts = #conflict_info.active_conflicts + #conflict_info.potential_conflicts
    -- if total_conflicts > 0 then
    --   local conflict_icon = #conflict_info.active_conflicts > 0 and "🔥" or "⚠"
    --   table.insert(status_parts, string.format("%s%d", conflict_icon, total_conflicts))
    -- end
    
    if #status_parts > 0 then
      head_line = head_line .. " (" .. table.concat(status_parts, " ") .. ")"
    end
  end
  
  -- Create highlight map
  local highlights = {
    { 1, 5, "Normal" },      -- "Head:"
    { 7, 6 + #branch_info.branch, "Directory" } -- branch name
  }
  
  -- Add highlighting for status indicators if present
  if show_status and head_line:find("%(") then
    local status_start = head_line:find("%(")
    local status_text = head_line:sub(status_start)
    
    -- Highlight different parts of the status
    highlights[3] = { status_start, status_start, "Comment" } -- opening paren
    
    -- Find and highlight conflict indicators
    local conflict_pos = status_text:find("[🔥⚠]")
    if conflict_pos then
      local conflict_char_pos = status_start + conflict_pos - 1
      local conflict_end = conflict_char_pos + 1
      
      -- Find the number after the conflict icon
      local number_match = status_text:match("([🔥⚠])(%d+)", conflict_pos)
      if number_match then
        conflict_end = conflict_char_pos + #number_match + 1
      end
      
      local conflict_color = status_text:match("🔥") and "DiagnosticError" or "DiagnosticWarn"
      highlights[4] = { conflict_char_pos, conflict_end, conflict_color }
    end
    
    highlights[5] = { #head_line, #head_line, "Comment" } -- closing paren
  end
  
  return {
    lines = { head_line },
    highlight_map = {
      [1] = highlights
    },
    actions = {
      [1] = function() M.show_branch_detail() end
    },
    tab_action = function(line_num)
      if line_num == 1 then
        M.show_branch_picker()
      end
    end
  }
end

-- Create new branch and checkout
function M.show_create_branch_prompt()
  vim.cmd('redraw')
  vim.ui.input({ prompt = "New branch name: " }, function(branch_name)
    if not branch_name or branch_name == "" then
      vim.notify("Branch creation cancelled - no name provided", vim.log.levels.INFO)
      return
    end

    -- Check if branch name is valid
    if branch_name:match("[^%w%-_/]") then
      vim.notify("Invalid branch name. Use only letters, numbers, hyphens, underscores, and slashes.", vim.log.levels.ERROR)
      return
    end

    -- Check if branch already exists
    local check_cmd = string.format("git show-ref --verify --quiet refs/heads/%s", branch_name)
    sys.system(check_cmd)
    if vim.v.shell_error == 0 then
      vim.notify(string.format("Branch '%s' already exists", branch_name), vim.log.levels.ERROR)
      return
    end

    -- Create and checkout new branch
    local cmd_result = sys.system(string.format("git checkout -b %s", vim.fn.shellescape(branch_name)))

    if vim.v.shell_error ~= 0 then
      vim.notify("Failed to create branch: " .. cmd_result, vim.log.levels.ERROR)
      return
    end

    vim.notify(string.format("Created and switched to branch '%s'", branch_name), vim.log.levels.INFO)
    
    -- Refresh dashboard if callback is available
    if M._refresh_callback then
      M._refresh_callback()
    end
  end)
end

-- Rebase current branch onto main/master
function M.rebase_onto_main()
  local current_branch = get_current_branch()
  if not current_branch then
    vim.notify("Could not determine current branch", vim.log.levels.ERROR)
    return false
  end
  
  local main_branch = get_main_branch()
  
  -- Don't rebase if already on main branch
  if current_branch == main_branch then
    vim.notify(string.format("Already on %s branch", main_branch), vim.log.levels.WARN)
    return false
  end
  
  -- Check if working directory is clean
  local status_output = sys.system("git status --porcelain")
  if vim.v.shell_error == 0 and vim.trim(status_output) ~= "" then
    vim.notify("Working directory has uncommitted changes. Please commit or stash them first.", vim.log.levels.WARN)
    return false
  end
  
  vim.notify(string.format("Rebasing %s onto %s...", current_branch, main_branch), vim.log.levels.INFO)
  
  -- Perform the rebase asynchronously
  async_sys.git_rebase_async(main_branch, {
    on_complete = function(success)
      if success then
        vim.notify(string.format("Successfully rebased %s onto %s", current_branch, main_branch), vim.log.levels.INFO)
        -- Refresh dashboard if callback is available
        if M._refresh_callback then
          M._refresh_callback()
        end
      end
    end
  })
  
  return true
end

-- Squash merge current branch into tracking branch
function M.squash_merge_into_tracking()
  local current_branch = get_current_branch()
  if not current_branch then
    vim.notify("Could not determine current branch", vim.log.levels.ERROR)
    return false
  end
  
  -- Get configured tracking branch
  local git_tracking = require('gitcast.git-tracking')
  local tracking_branch = git_tracking.get_tracking_branch()
  
  -- Don't squash if already on tracking branch
  if current_branch == tracking_branch then
    vim.notify(string.format("Already on %s branch", tracking_branch), vim.log.levels.WARN)
    return false
  end
  
  -- Check if working directory is clean
  local status_output = sys.system("git status --porcelain")
  if vim.v.shell_error == 0 and vim.trim(status_output) ~= "" then
    vim.notify("Working directory has uncommitted changes. Please commit or stash them first.", vim.log.levels.WARN)
    return false
  end
  
  -- Generate default squash message from commit range
  local log_cmd = string.format("git log --oneline %s..%s", 
    vim.fn.shellescape(tracking_branch), vim.fn.shellescape(current_branch))
  local commit_output = sys.system(log_cmd)
  
  local default_message = string.format("Squash merge %s", current_branch)
  if vim.v.shell_error == 0 and commit_output ~= "" then
    local commit_count = 0
    for _ in commit_output:gmatch("[^\r\n]+") do
      commit_count = commit_count + 1
    end
    if commit_count > 0 then
      default_message = string.format("Squash merge %s (%d commits)", current_branch, commit_count)
    end
  end
  
  -- Get squash commit message from user
  vim.cmd('redraw')
  vim.ui.input({
    prompt = "Squash commit message: ",
    default = default_message
  }, function(commit_message)
    if not commit_message or commit_message == "" then
      vim.notify("Squash merge cancelled - no commit message provided", vim.log.levels.INFO)
      return
    end
    
    -- Use vim.schedule to avoid blocking the UI
    vim.schedule(function()
      vim.notify(string.format("Squash merging %s into %s...", current_branch, tracking_branch), vim.log.levels.INFO)
      
      -- Switch to tracking branch
      local checkout_cmd = string.format("git checkout %s", vim.fn.shellescape(tracking_branch))
      local checkout_result = sys.system(checkout_cmd)
      if vim.v.shell_error ~= 0 then
        vim.notify("Failed to checkout tracking branch: " .. checkout_result, vim.log.levels.ERROR)
        return
      end
      
      -- Perform squash merge
      local merge_cmd = string.format("git merge --squash %s", vim.fn.shellescape(current_branch))
      local merge_result = sys.system(merge_cmd)
      if vim.v.shell_error ~= 0 then
        vim.notify("Squash merge failed: " .. merge_result, vim.log.levels.ERROR)
        -- Try to return to original branch
        sys.system(string.format("git checkout %s", vim.fn.shellescape(current_branch)))
        return
      end
      
      -- Commit the squashed changes
      local commit_cmd = string.format("git commit -m %s", vim.fn.shellescape(commit_message))
      local commit_result = sys.system(commit_cmd)
      if vim.v.shell_error ~= 0 then
        vim.notify("Failed to commit squashed changes: " .. commit_result, vim.log.levels.ERROR)
        -- Reset and return to original branch
        sys.system("git reset --hard HEAD")
        sys.system(string.format("git checkout %s", vim.fn.shellescape(current_branch)))
        return
      end
      
      -- Stay on tracking branch instead of returning to original branch
      vim.notify(string.format("Successfully squash merged %s into %s (now on %s)", 
        current_branch, tracking_branch, tracking_branch), vim.log.levels.INFO)
      
      -- Refresh dashboard if callback is available
      if M._refresh_callback then
        M._refresh_callback()
      end
    end)
  end)
end

-- Setup highlight groups for branch detail (branch specific)
local function setup_branch_detail_highlights()
  vim.api.nvim_set_hl(0, "GitBranchDetailInfo", { link = "Comment" })
  -- Reuse existing highlight groups for file status
  vim.api.nvim_set_hl(0, "GitFileAdded", { link = "DiffAdd" })
  vim.api.nvim_set_hl(0, "GitFileDeleted", { link = "DiffDelete" })
  vim.api.nvim_set_hl(0, "GitFileModified", { link = "DiagnosticWarn" })
end

-- Get file changes with stats and status for branch comparison
local function get_branch_files(main_branch)
  -- Get file status (A/M/D) and line counts separately
  local status_cmd = string.format("git diff --name-status %s...HEAD", vim.fn.shellescape(main_branch))
  local numstat_cmd = string.format("git diff --numstat %s...HEAD", vim.fn.shellescape(main_branch))
  
  -- Get file statuses
  local status_output = sys.system(status_cmd)
  local numstat_output = sys.system(numstat_cmd)
  
  if vim.v.shell_error ~= 0 then
    return {}
  end

  -- Parse status data
  local file_statuses = {}
  for line in status_output:gmatch("[^\r\n]+") do
    if line ~= "" then
      local status, filepath = line:match("^([AMD])\t(.+)$")
      if status and filepath then
        file_statuses[filepath] = status
      end
    end
  end
  
  -- Parse numstat data and combine with status
  local files = {}
  for line in numstat_output:gmatch("[^\r\n]+") do
    if line ~= "" then
      local parts = vim.split(line, "\t")
      if #parts >= 3 then
        local added = parts[1] == "-" and 0 or tonumber(parts[1]) or 0
        local deleted = parts[2] == "-" and 0 or tonumber(parts[2]) or 0
        local filepath = parts[3]
        local status = file_statuses[filepath] or "M" -- Default to M if not found

        table.insert(files, {
          path = filepath,
          status = status,
          added = added,
          deleted = deleted,
          total_changes = added + deleted
        })
      end
    end
  end

  return files
end

-- Format line counts inline (same as commit detail)
local function format_line_counts_inline(added, removed)
  if added == 0 and removed == 0 then
    return "", {}
  end
  
  local text = string.format(" +%d -%d", added, removed)
  local highlights = {}
  
  -- Find positions for highlighting
  local add_start, add_end = string.find(text, string.format("+%d", added), 1, true)
  local rem_start, rem_end = string.find(text, string.format("-%d", removed), 1, true)
  
  if add_start and add_end then
    table.insert(highlights, { add_start, add_end, "GitFileAdded" })
  end
  if rem_start and rem_end then
    table.insert(highlights, { rem_start, rem_end, "GitFileDeleted" })
  end
  
  return text, highlights
end

-- Get main branch last commit info
local function get_main_branch_info(main_branch)
  local cmd = string.format("git log -1 --format='%%h %%s (%%an, %%ar)' %s 2>/dev/null", vim.fn.shellescape(main_branch))
  local output = sys.system(cmd):gsub("%s+$", "")
  
  if vim.v.shell_error == 0 and output ~= "" then
    return output
  end
  return nil
end

-- Get commits that current branch is behind
local function get_commits_behind(current_branch, main_branch)
  local cmd = string.format("git log --format='%%h %%s (%%an, %%ar)' %s..%s 2>/dev/null", 
    vim.fn.shellescape(current_branch), vim.fn.shellescape(main_branch))
  local output = sys.system(cmd)
  
  if vim.v.shell_error ~= 0 or output == "" then
    return {}
  end
  
  local commits = {}
  for line in output:gmatch("[^\r\n]+") do
    if line ~= "" then
      table.insert(commits, line)
    end
  end
  
  return commits
end

-- Format branch detail content (B + D style)
local function format_branch_detail_content(current_branch, main_branch, files)
  local lines = {}
  local file_map = {}
  local highlight_map = {}

  -- Branch comparison header
  table.insert(lines, "Comparing branches:")
  table.insert(lines, string.format("%s...%s", current_branch, main_branch))
  highlight_map[#lines] = {
    { 1, #current_branch, "Directory" },
    { #current_branch + 4, #current_branch + 3 + #main_branch, "Directory" }
  }
  
  table.insert(lines, "")
  
  -- Show commits behind if any
  local branch_status = get_branch_status(current_branch, main_branch)
  if branch_status.behind > 0 then
    local commits_behind = get_commits_behind(current_branch, main_branch)
    if #commits_behind > 0 then
      table.insert(lines, string.format("Commits behind (%d):", #commits_behind))
      for i, commit in ipairs(commits_behind) do
        local line_num = #lines + 1
        table.insert(lines, string.format("  %s", commit))
        
        -- Create highlighting like commits module
        local ranges = {}
        
        -- Extract and highlight hash (same as commits module)
        local hash = commit:match("^([a-f0-9]+)")
        if hash then
          table.insert(ranges, { 3, 2 + #hash, "Identifier" })
          file_map[line_num] = { type = "commit", hash = hash }
        end
        
        -- Highlight author/date info in parentheses
        local author_date_start, author_date_end = string.find(commit, "%(.*%)")
        if author_date_start and author_date_end then
          table.insert(ranges, { author_date_start + 1, author_date_end + 1, "Comment" }) -- +1 for line offset
        end
        
        highlight_map[line_num] = ranges
      end
      table.insert(lines, "")
    end
  end
  
  -- Merge conflicts section (always shown)
  table.insert(lines, "Merge conflicts:")
  
  local conflict_info = get_conflict_details(current_branch, main_branch)
  local has_any_conflicts = #conflict_info.active_conflicts > 0 or #conflict_info.potential_conflicts > 0
  
  if has_any_conflicts then
    -- Show active conflicts (currently unresolved)
    if #conflict_info.active_conflicts > 0 then
      table.insert(lines, string.format("  Active conflicts (%d files):", #conflict_info.active_conflicts))
      for _, file in ipairs(conflict_info.active_conflicts) do
        table.insert(lines, string.format("    🔥 %s", file))
        local line_highlights = {
          { 5, 6, "DiagnosticError" }, -- fire symbol
          { 8, #lines[#lines], "Directory" } -- file path
        }
        highlight_map[#lines] = line_highlights
      end
    end
    
    -- Show potential conflicts (would occur on merge)
    if #conflict_info.potential_conflicts > 0 then
      table.insert(lines, string.format("  Potential conflicts (%d files):", #conflict_info.potential_conflicts))
      for _, file in ipairs(conflict_info.potential_conflicts) do
        table.insert(lines, string.format("    ⚠ %s", file))
        local line_highlights = {
          { 5, 5, "DiagnosticWarn" }, -- warning symbol
          { 7, #lines[#lines], "Directory" } -- file path
        }
        highlight_map[#lines] = line_highlights
      end
    end
  else
    -- No conflicts
    table.insert(lines, "  No conflicts")
    highlight_map[#lines] = "GitBranchDetailInfo"
  end
  
  table.insert(lines, "")
  
  -- Files changed section
  if #files > 0 then
    local total_added = 0
    local total_deleted = 0
    for _, file in ipairs(files) do
      total_added = total_added + file.added
      total_deleted = total_deleted + file.deleted
    end
    
    -- Summary line with color highlighting
    local summary_line = string.format("%d files, +%d -%d", #files, total_added, total_deleted)
    table.insert(lines, summary_line)
    
    local summary_highlights = {}
    local added_text = string.format("+%d", total_added)
    local deleted_text = string.format("-%d", total_deleted)
    
    local added_start, added_end = string.find(summary_line, added_text, 1, true)
    local deleted_start, deleted_end = string.find(summary_line, deleted_text, 1, true)
    
    if added_start and added_end then
      table.insert(summary_highlights, { added_start, added_end, "GitFileAdded" })
    end
    if deleted_start and deleted_end then
      table.insert(summary_highlights, { deleted_start, deleted_end, "GitFileDeleted" })
    end
    
    if #summary_highlights > 0 then
      highlight_map[#lines] = summary_highlights
    end
    
    table.insert(lines, "")
    table.insert(lines, "Files changed:")

    -- File list with dashboard-style formatting
    for _, file in ipairs(files) do
      local line_num = #lines + 1
      local status_icon = file.status or "M"
      local status_highlight = "GitFileModified"

      -- Set highlight based on actual git status
      if status_icon == "A" then
        status_highlight = "GitFileAdded"
      elseif status_icon == "D" then
        status_highlight = "GitFileDeleted"
      else -- M or any other status
        status_highlight = "GitFileModified"
      end

      local line_counts_text, line_counts_highlights = format_line_counts_inline(file.added, file.deleted)
      local display_line = string.format("  %s%s %s", status_icon, line_counts_text, file.path)
      
      table.insert(lines, display_line)
      file_map[line_num] = { type = "file", path = file.path }

      -- Apply highlighting (dashboard style)
      local highlights = {}
      
      -- Status character highlight
      table.insert(highlights, { 3, 3, status_highlight })
      
      -- Line count highlights
      if #line_counts_highlights > 0 then
        for _, hl in ipairs(line_counts_highlights) do
          local start_col, end_col, hl_group = hl[1], hl[2], hl[3]
          table.insert(highlights, { 3 + start_col, 3 + end_col, hl_group })
        end
      end
      
      -- File name uses Directory highlight (like dashboard)
      local file_start = 3 + #line_counts_text + 1
      table.insert(highlights, { file_start, #display_line, "Directory" })
      
      highlight_map[line_num] = highlights
    end
  else
    table.insert(lines, "Files changed:")
    table.insert(lines, "  No files changed")
    highlight_map[#lines] = "GitBranchDetailInfo"
  end

  return lines, file_map, highlight_map
end

-- Apply highlighting to buffer (same as commit detail)
local function apply_branch_highlighting(bufnr, highlight_map)
  local ns_id = vim.api.nvim_create_namespace("git_branch_detail_highlights")
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  for line_num, highlight_info in pairs(highlight_map) do
    if type(highlight_info) == "string" then
      -- Simple highlight group for entire line (headers)
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, highlight_info, line_num - 1, 0, -1)
    elseif type(highlight_info) == "table" and #highlight_info > 0 then
      -- Multiple highlight ranges (file lines)
      for _, range in ipairs(highlight_info) do
        local start_col, end_col, hl_group = range[1], range[2], range[3]
        vim.api.nvim_buf_add_highlight(bufnr, ns_id, hl_group, line_num - 1, start_col - 1, end_col)
      end
    end
  end
end

-- Set up keymaps for branch detail buffer
local function setup_branch_detail_keymaps(bufnr, file_map, current_branch, main_branch)
  vim.keymap.set('n', '<CR>', function()
    local line_num = vim.api.nvim_win_get_cursor(0)[1]
    local item = file_map[line_num]

    if item then
      if item.type == "commit" then
        -- Open commit detail view
        local git_commit_detail = require('gitcast.git-commit-detail')
        -- Need to get full commit info
        local cmd = string.format("git log -1 --format='%%H|%%h|%%an|%%ae|%%ad|%%s' --date=iso %s", 
          vim.fn.shellescape(item.hash))
        local output = sys.system(cmd):gsub("%s+$", "")
        
        if vim.v.shell_error == 0 and output ~= "" then
          local parts = vim.split(output, "|")
          if #parts >= 6 then
            local commit_info = {
              hash = parts[1],
              short_hash = parts[2],
              author = parts[3],
              email = parts[4],
              date = parts[5],
              message = parts[6]
            }
            git_commit_detail.show_commit_detail(commit_info)
          end
        end
      elseif item.path then
        -- Show file diff using delta-diff module
        local delta_diff = require('gitcast.delta-diff')
        delta_diff.show_branch_file_diff(main_branch, item.path, { 
          title = string.format("%s vs %s: %s", current_branch, main_branch, item.path) 
        })
      end
    end
  end, { buffer = bufnr, desc = "Show file diff or commit detail" })

  vim.keymap.set('n', 'gf', function()
    local line_num = vim.api.nvim_win_get_cursor(0)[1]
    local file = file_map[line_num]

    if file then
      vim.cmd('edit ' .. vim.fn.fnameescape(file.path))
    end
  end, { buffer = bufnr, desc = "Open file in editor" })


  vim.keymap.set('n', 'q', function()
    vim.cmd('bw')
  end, { buffer = bufnr, desc = "Close branch detail view" })

  vim.keymap.set('n', 'g?', function()
    M.show_branch_help()
  end, { buffer = bufnr, desc = "Show help" })
end

-- Show branch detail view with files changed compared to tracking branch
function M.show_branch_detail()
  local current_branch = get_current_branch()
  local git_tracking = require('gitcast.git-tracking')
  local tracking_branch = git_tracking.get_tracking_branch()
  
  if current_branch == tracking_branch then
    vim.notify(string.format("Already on %s branch", tracking_branch), vim.log.levels.WARN)
    return
  end
  
  setup_branch_detail_highlights()
  
  local files = get_branch_files(tracking_branch)
  local content, file_map, highlight_map = format_branch_detail_content(current_branch, tracking_branch, files)

  -- Create buffer for branch detail view
  local utils = require('gitcast.utils')
  local name = utils.create_unique_buffer_name('GitBranchDetail')
  local bufnr = utils.create_view_buffer(name, 'gitbranchdetail')
  vim.api.nvim_buf_set_option(bufnr, 'buflisted', true)
  
  -- Set content
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
  
  -- Apply highlighting
  apply_branch_highlighting(bufnr, highlight_map)
  
  -- Set up keymaps
  setup_branch_detail_keymaps(bufnr, file_map, current_branch, tracking_branch)
  
  -- Open buffer
  vim.api.nvim_set_current_buf(bufnr)
  
  -- Set cursor to first file if any
  for line_num, _ in pairs(file_map) do
    vim.api.nvim_win_set_cursor(0, { line_num, 0 })
    break
  end
end

-- Show help for branch detail
function M.show_branch_help()
  local help_lines = {
    "Git Branch Details Help",
    "",
    "Navigation:",
    "  <CR>     Show file diff against base branch",
    "  gf       Open file in editor",
    "  q        Close branch detail view",
    "  g?       Show this help"
  }

  local width = 45
  local height = #help_lines + 2
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = 'rounded'
  })

  -- Close on Esc or q
  vim.keymap.set('n', '<Esc>', function()
    vim.cmd('bw')
  end, { buffer = buf })
  
  vim.keymap.set('n', 'q', function()
    vim.cmd('bw')
  end, { buffer = buf })
end

-- Set refresh callback from dashboard
function M.set_refresh_callback(callback)
  M._refresh_callback = callback
end

-- Setup function
function M.setup()
  -- No user commands, functionality accessed through dashboard
end

return M