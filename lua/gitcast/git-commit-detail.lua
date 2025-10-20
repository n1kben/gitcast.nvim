-- git-commit-detail.lua
local M = {}
local utils = require('gitcast.utils')
local sys = require('gitcast.system-utils')

-- Current state
M._current_commit = nil
M._current_files = {}
M._detail_buffer = nil

-- Setup highlight groups (commit detail specific)
local function setup_highlights()
  vim.api.nvim_set_hl(0, "GitCommitDetailHeader", { link = "Title" })
  vim.api.nvim_set_hl(0, "GitCommitDetailInfo", { link = "Comment" })
  -- Reuse existing highlight groups for file status
  vim.api.nvim_set_hl(0, "GitFileAdded", { link = "DiffAdd" })
  vim.api.nvim_set_hl(0, "GitFileDeleted", { link = "DiffDelete" })
  vim.api.nvim_set_hl(0, "GitFileModified", { link = "DiagnosticWarn" })
end

-- Get file changes for a specific commit
local function get_commit_files(commit_hash)
  -- Get file status (A/M/D) and line counts separately
  local status_cmd = string.format("git show --name-status --format='' %s", commit_hash)
  local numstat_cmd = string.format("git show --numstat --format='' %s", commit_hash)
  
  -- Get file statuses
  local status_handle = sys.popen(status_cmd)
  if not status_handle then
    return {}
  end
  local status_output = status_handle:read("*a")
  status_handle:close()
  
  -- Get line counts
  local numstat_handle = sys.popen(numstat_cmd)
  if not numstat_handle then
    return {}
  end
  local numstat_output = numstat_handle:read("*a")
  numstat_handle:close()

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

-- Format line counts inline (similar to dashboard style)
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

-- Format commit detail content (dashboard style)
local function format_commit_detail_content(commit, files)
  local lines = {}
  local file_map = {}
  local highlight_map = {}

  -- Full hash on its own line
  table.insert(lines, commit.hash)
  highlight_map[#lines] = "Identifier"
  
  table.insert(lines, commit.message)
  
  table.insert(lines, string.format("%s <%s>", commit.author, commit.email))
  highlight_map[#lines] = "GitCommitDetailInfo"
  table.insert(lines, string.format("%s", commit.date))
  highlight_map[#lines] = "GitCommitDetailInfo"
  
  table.insert(lines, "")
  
  -- Files changed section
  if #files > 0 then
    local total_added = 0
    local total_deleted = 0
    for _, file in ipairs(files) do
      total_added = total_added + file.added
      total_deleted = total_deleted + file.deleted
    end
    
    table.insert(lines, string.format("Files changed (%d files, +%d -%d):", #files, total_added, total_deleted))
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
      file_map[line_num] = file

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
      
      -- File name uses normal color (like dashboard)
      local file_start = 3 + #line_counts_text + 1
      table.insert(highlights, { file_start, #display_line, "Directory" })
      
      highlight_map[line_num] = highlights
    end
  else
    table.insert(lines, "Files changed:")
    table.insert(lines, "  No files changed")
    highlight_map[#lines] = "GitCommitDetailInfo"
  end

  return lines, file_map, highlight_map
end

-- Show file content at specific commit point
local function show_file_at_commit(commit_hash, filepath)
  local cmd = string.format("git show %s:%s", commit_hash, filepath)
  local handle = sys.popen(cmd)
  if not handle then
    vim.notify("Failed to get file content", vim.log.levels.ERROR)
    return
  end

  local output = handle:read("*a")
  handle:close()

  if vim.v.shell_error ~= 0 then
    vim.notify("File not found at this commit", vim.log.levels.WARN)
    return
  end

  -- Create file buffer
  local bufnr = vim.api.nvim_create_buf(false, false)
  local name = string.format("%s@%s", filepath, commit_hash:sub(1, 7))
  vim.api.nvim_buf_set_name(bufnr, name)

  -- Set buffer content
  local lines = vim.split(output, '\n')
  if #lines > 0 and lines[#lines] == "" then
    table.remove(lines)
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Set buffer options
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
  vim.api.nvim_buf_set_option(bufnr, "modified", false)
  vim.api.nvim_buf_set_option(bufnr, 'buflisted', true)

  -- Set filetype for syntax highlighting
  local filetype = vim.fn.fnamemodify(filepath, ":e")
  if filetype ~= "" then
    vim.api.nvim_buf_set_option(bufnr, "filetype", filetype)
  end

  vim.api.nvim_set_current_buf(bufnr)
end

-- Set up keymaps for commit detail buffer
local function setup_commit_detail_keymaps(bufnr, file_map, commit)
  vim.keymap.set('n', '<CR>', function()
    local line_num = vim.api.nvim_win_get_cursor(0)[1]
    local file = file_map[line_num]

    if file then
      -- Show file diff using delta-diff module
      local delta_diff = require('gitcast.delta-diff')
      delta_diff.show_git_diff(file.path, { 
        commit = commit.hash,
        title = string.format("%s: %s", commit.short_hash, file.path)
      })
    end
  end, { buffer = bufnr, desc = "Show file diff" })

  vim.keymap.set('n', 'gf', function()
    local line_num = vim.api.nvim_win_get_cursor(0)[1]
    local file = file_map[line_num]

    if file then
      show_file_at_commit(commit.hash, file.path)
    end
  end, { buffer = bufnr, desc = "Open file at commit" })


  vim.keymap.set('n', 'g?', function()
    M.show_help()
  end, { buffer = bufnr, desc = "Show help" })
end

-- Apply highlighting to buffer (dashboard style)
local function apply_highlighting(bufnr, highlight_map)
  local ns_id = vim.api.nvim_create_namespace("git_commit_detail_highlights")
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

-- Create commit detail buffer
local function create_commit_detail_buffer()
  local name = utils.create_unique_buffer_name('GitCommitDetail')
  local bufnr = utils.create_view_buffer(name, 'gitcommitdetail')
  vim.api.nvim_buf_set_option(bufnr, 'buflisted', true)
  return bufnr
end

-- Show commit detail
function M.show_commit_detail(commit)
  setup_highlights()
  
  local files = get_commit_files(commit.hash)
  M._current_commit = commit
  M._current_files = files

  local content, file_map, highlight_map = format_commit_detail_content(commit, files)

  -- Create buffer
  local bufnr = create_commit_detail_buffer()
  M._detail_buffer = bufnr

  -- Set content
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)

  -- Apply highlighting
  apply_highlighting(bufnr, highlight_map)

  -- Set up keymaps
  setup_commit_detail_keymaps(bufnr, file_map, commit)

  -- Open buffer
  vim.api.nvim_set_current_buf(bufnr)

  -- Set cursor to first file if any
  for line_num, _ in pairs(file_map) do
    vim.api.nvim_win_set_cursor(0, { line_num, 0 })
    break
  end
end

-- Show help
function M.show_help()
  local help_lines = {
    "Git Commit Details Help",
    "",
    "Navigation:",
    "  <CR>     Show file diff",
    "  gf       Open file at commit point",
    "  g?       Show this help"
  }

  local width = 40
  local height = #help_lines
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

  -- Close on Esc
  vim.keymap.set('n', '<Esc>', function()
    vim.cmd('bw')
  end, { buffer = buf })
end

-- Setup function
function M.setup()
  -- No user commands, functionality accessed through dashboard
end

return M