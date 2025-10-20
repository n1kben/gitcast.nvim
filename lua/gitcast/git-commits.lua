-- git-commits.lua - Simplified for dashboard use only
local M = {}
local sys = require('gitcast.system-utils')

-- Setup highlight groups for commits module
function M.setup_highlights()
  vim.api.nvim_set_hl(0, "GitStatusHeader", { link = "Normal" })
  vim.api.nvim_set_hl(0, "GitStatusEmpty", { link = "Comment" })
  vim.api.nvim_set_hl(0, "GitFileAdded", { link = "DiffAdd" })
  vim.api.nvim_set_hl(0, "GitFileDeleted", { link = "DiffDelete" })
end

-- Get virtual text configuration for commits module
function M.get_virtual_text_config()
  return {
    default_hl_group = "Comment",
    namespace = "git_commits_virtual_text"
  }
end

-- Parse git log output into structured data
local function parse_git_log(git_output)
  if not git_output or git_output == "" then
    return {}
  end
  
  local commits = {}
  local current_commit = nil
  local added_total = 0
  local deleted_total = 0
  
  for line in git_output:gmatch("[^\r\n]+") do
    if line:match("^COMMIT:") then
      -- Save previous commit if exists
      if current_commit then
        current_commit.added = added_total
        current_commit.deleted = deleted_total
        table.insert(commits, current_commit)
      end
      
      -- Start new commit
      local commit_data = line:sub(8) -- Remove "COMMIT:" prefix
      local parts = vim.split(commit_data, "|", { plain = true })
      if #parts >= 6 then
        current_commit = {
          hash = parts[1],
          short_hash = parts[2],
          author = parts[3],
          email = parts[4],
          date = parts[5],
          message = parts[6]
        }
        added_total = 0
        deleted_total = 0
      end
    elseif line ~= "" and current_commit then
      -- Parse numstat line: "added\tdeleted\tfilename"
      local added, deleted = line:match("^(%d+)\t(%d+)\t")
      if added and deleted then
        added_total = added_total + tonumber(added)
        deleted_total = deleted_total + tonumber(deleted)
      end
    end
  end
  
  -- Don't forget the last commit
  if current_commit then
    current_commit.added = added_total
    current_commit.deleted = deleted_total
    table.insert(commits, current_commit)
  end
  
  return commits
end

-- Set refresh callback from dashboard
function M.set_refresh_callback(callback)
  M._refresh_callback = callback
end


-- Setup
function M.setup()
  -- No user commands needed - only used through dashboard
end

-- Get commits module for dashboard
function M.get_commits_module(git_output)
  -- If no git_output provided, fetch it ourselves
  if not git_output or git_output == "" then
    local cmd = "git log --oneline --numstat --format='COMMIT:%H|%h|%an|%ae|%ar|%s' -n 5 2>/dev/null"
    local handle = sys.popen(cmd)
    if handle then
      git_output = handle:read("*a")
      handle:close()
    else
      git_output = ""
    end
  end
  
  local commits = parse_git_log(git_output)
  local lines = {}
  local commit_map = {}
  local highlight_map = {}
  local actions = {}
  local header = "Commits:"

  for i, commit in ipairs(commits) do
    local line_num = #lines + 1
    
    -- Simple format: hash message +X -Y (author) time
    local stats_text = string.format("+%d -%d", commit.added, commit.deleted)
    local author_date_text = string.format("(%s) %s", commit.author, commit.date)
    local display_line = string.format("  %s %s %s %s", commit.short_hash, commit.message, stats_text, author_date_text)
    table.insert(lines, display_line)
    commit_map[line_num] = commit
    
    -- Create highlighting for different parts
    local ranges = {}
    
    -- Hash highlight (position 3 to end of hash)
    table.insert(ranges, { 3, 2 + #commit.short_hash, "Identifier" })
    
    -- Line change highlights
    local added_text = string.format("+%d", commit.added)
    local deleted_text = string.format("-%d", commit.deleted)
    
    local added_start, added_end = string.find(display_line, added_text, 1, true)
    local deleted_start, deleted_end = string.find(display_line, deleted_text, 1, true)
    
    if added_start and added_end then
      table.insert(ranges, { added_start, added_end, "GitFileAdded" })
    end
    if deleted_start and deleted_end then
      table.insert(ranges, { deleted_start, deleted_end, "GitFileDeleted" })
    end
    
    -- Author/date highlight  
    local author_date_start, author_date_end = string.find(display_line, author_date_text, 1, true)
    if author_date_start and author_date_end then
      table.insert(ranges, { author_date_start, author_date_end, "Comment" })
    end
    
    highlight_map[line_num] = ranges
    
    -- Action: show commit detail view
    actions[line_num] = function()
      local git_commit_detail = require('gitcast.git-commit-detail')
      git_commit_detail.show_commit_detail(commit)
    end
  end

  if #commits == 0 then
    table.insert(lines, "  (no commits)")
    highlight_map[#lines] = "GitStatusEmpty"
  end

  return {
    lines = lines,
    file_map = commit_map,
    highlight_map = highlight_map,
    actions = actions,
    header = header, -- Dynamic header with count
    -- Reset action for <BS>
    bs_action = function(line_num)
      local commit = commit_map[line_num]
      if not commit then
        return
      end
      
      local commit_hash = commit.hash or commit.short_hash
      if not commit_hash then
        vim.notify("Invalid commit data", vim.log.levels.ERROR)
        return
      end
      
      -- Check if this is the initial commit by trying to get parent
      local parent_cmd = string.format("git rev-parse %s^ 2>/dev/null", commit_hash)
      local parent_hash = sys.system(parent_cmd):gsub("%s+", "")
      
      if vim.v.shell_error ~= 0 or parent_hash == "" then
        -- This is the initial commit
        local reset_msg = string.format("Reset past initial commit %s (%s)?", commit_hash:sub(1, 8), commit.message)
        local warning_msg = "This will remove ALL commits from this branch, creating an empty repository."
        
        vim.ui.confirm({
          msg = reset_msg .. "\n\n" .. warning_msg .. "\n\nThis action is destructive - are you sure?",
          default = false
        }, function(confirmed)
          if not confirmed then
            return
          end
          
          local cmd = "git update-ref -d HEAD"
          local result = sys.system(cmd)
          
          if vim.v.shell_error ~= 0 then
            vim.notify("Failed to reset past initial commit: " .. result, vim.log.levels.ERROR)
            return
          end
          
          vim.notify("Reset past initial commit - repository is now empty", vim.log.levels.INFO)
          
          if M._refresh_callback then
            M._refresh_callback()
          end
        end)
        return
      end
      
      -- Get parent commit message for display
      local parent_msg_cmd = string.format("git log --format=%%s -n 1 %s", parent_hash)
      local parent_message = sys.system(parent_msg_cmd):gsub("%s+", "")
      
      local reset_msg = string.format("Reset to parent of %s (%s)?", commit_hash:sub(1, 8), commit.message)
      local target_msg = string.format("Target: %s (%s)", parent_hash:sub(1, 8), parent_message)
      local warning_msg = "This will undo this commit and all commits after it."
      
      vim.ui.confirm({
        msg = reset_msg .. "\n" .. target_msg .. "\n\n" .. warning_msg,
        default = false
      }, function(confirmed)
        if not confirmed then
          return
        end
        
        local cmd = string.format("git reset --mixed %s", parent_hash)
        local result = sys.system(cmd)
        
        if vim.v.shell_error ~= 0 then
          vim.notify("Mixed reset failed: " .. result, vim.log.levels.ERROR)
          return
        end
        
        vim.notify(string.format("Reset to %s", parent_hash:sub(1, 8)), vim.log.levels.INFO)
        
        if M._refresh_callback then
          M._refresh_callback()
        end
      end)
    end
  }
end

return M