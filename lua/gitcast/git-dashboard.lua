-- git-dashboard.lua
local M = {}
local utils = require('gitcast.utils')
local sys = require('gitcast.system-utils')
local async_sys = require('gitcast.async-system')

-- Configuration
local config = {
  performance_tracking = false -- Enable/disable performance timing logs
}


-- Current state
M._current_buffer = nil
M._sections = {}

-- Helper function for conditional performance logging
local function log_performance(data)
  if config.performance_tracking then
    if type(data) == "string" then
      -- Legacy string format - convert to object for better display
      local caller, cmd, time_ms = data:match("%[([^%]]+)%] (.+): ([%d%.]+)ms")
      if caller and cmd and time_ms then
        dd({
          time = tonumber(time_ms) .. "ms",
          file = caller,
          cmd = cmd
        })
      else
        vim.notify(data, vim.log.levels.DEBUG)
      end
    else
      -- New object format
      dd(data)
    end
  end
end

-- Expose for other modules
M._log_performance = log_performance

-- Section definitions with their plugins and headers
local SECTIONS = {
  { key = "branch",    plugin = "gitcast.git-branch",   header = nil,                 get_module = "get_branch_module" },
  { key = "tracking",  plugin = "gitcast.git-tracking", header = nil,                 get_module = "get_tracking_module" },
  { key = "commits",   plugin = "gitcast.git-commits",  header = nil,                 get_module = "get_commits_module" }, -- Header will be dynamic
  { key = "staged",    plugin = "gitcast.git-staging",  header = "Staged changes:",   get_module = "get_staged_module" },
  { key = "modified",  plugin = "gitcast.git-staging",  header = "Unstaged changes:", get_module = "get_modified_module" },
  { key = "untracked", plugin = "gitcast.git-staging",  header = "Untracked files:",  get_module = "get_untracked_module" },
}

-- Cache module requires
local cached_modules = {}
local function get_module(plugin_path)
  if not cached_modules[plugin_path] then
    cached_modules[plugin_path] = require(plugin_path)
  end
  return cached_modules[plugin_path]
end

-- Setup highlights from all modules
local function setup_highlights()
  -- Call each module's highlight setup
  for _, section_def in ipairs(SECTIONS) do
    local plugin = get_module(section_def.plugin)
    if plugin.setup_highlights then
      plugin.setup_highlights()
    end
  end
end

-- Compose dashboard content from all modules
local function compose_dashboard_content()
  local all_lines = {}
  local line_to_section = {} -- Maps line number to section info
  local section_data = {}    -- Stores module data for each section
  local current_line = 1

  -- Check if we have any staging modules and fetch git data once
  local has_staging_modules = false
  for _, section_def in ipairs(SECTIONS) do
    if section_def.plugin == "gitcast.git-staging" then
      has_staging_modules = true
      break
    end
  end

  local git_data = nil

  if has_staging_modules then
    local git_staging_module = get_module("gitcast.git-staging")
    git_data = git_staging_module.fetch_git_status()
  end

  for _, section_def in ipairs(SECTIONS) do
    local plugin = get_module(section_def.plugin)

    -- Pass git_data to staging modules, normal call for others
    local module_data

    if section_def.plugin == "gitcast.git-staging" and git_data then
      module_data = plugin[section_def.get_module](git_data)
    elseif section_def.plugin == "gitcast.git-commits" then
      module_data = plugin[section_def.get_module]()
    elseif section_def.plugin == "gitcast.git-branch" then
      module_data = plugin[section_def.get_module]()
    else
      module_data = plugin[section_def.get_module]()
    end


    section_data[section_def.key] = {
      module_data = module_data,
      start_line = current_line,
      section_def = section_def
    }

    -- Add header if specified (prefer module header over section header)
    local header_text = module_data.header or section_def.header
    if header_text then
      table.insert(all_lines, header_text)
      line_to_section[current_line] = {
        section_key = section_def.key,
        is_header = true
      }
      current_line = current_line + 1
    end

    -- Add module lines
    for i, line in ipairs(module_data.lines) do
      table.insert(all_lines, line)
      line_to_section[current_line] = {
        section_key = section_def.key,
        module_line = i,
        is_header = false
      }
      current_line = current_line + 1
    end

    -- Add spacing after section (except between branch and tracking)
    local skip_spacing = (section_def.key == "branch") -- Don't add spacing after branch section
    if not skip_spacing then
      table.insert(all_lines, "")
      line_to_section[current_line] = { section_key = section_def.key, is_spacing = true }
      current_line = current_line + 1
    end

    section_data[section_def.key].end_line = current_line - 1
  end



  return all_lines, line_to_section, section_data
end

-- Apply highlighting to dashboard buffer
local function apply_dashboard_highlighting(bufnr, line_to_section, section_data)
  local ns_id = vim.api.nvim_create_namespace("git_dashboard_highlights")
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  for line_num, section_info in pairs(line_to_section) do
    if section_info.is_header then
      -- Highlight section headers
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, "GitStatusHeader", line_num - 1, 0, -1)
    elseif section_info.module_line and not section_info.is_spacing then
      -- Apply module-specific highlighting
      local section_key = section_info.section_key
      local module_line = section_info.module_line
      local module_data = section_data[section_key].module_data
      local highlight_map = module_data.highlight_map

      if highlight_map and highlight_map[module_line] then
        local hl_info = highlight_map[module_line]

        if type(hl_info) == "string" then
          -- Simple highlight group for entire line
          vim.api.nvim_buf_add_highlight(bufnr, ns_id, hl_info, line_num - 1, 0, -1)
        elseif type(hl_info) == "table" then
          -- Multiple highlight ranges
          for _, range in ipairs(hl_info) do
            local start_col, end_col, hl_group = range[1], range[2], range[3]
            vim.api.nvim_buf_add_highlight(bufnr, ns_id, hl_group, line_num - 1, start_col - 1, end_col)
          end
        end
      end
    end
  end
end

-- Add virtual text from modules using their own configuration
local function add_dashboard_virtual_text(bufnr, line_to_section, section_data)
  -- Create a namespace per module to allow different configurations
  local module_namespaces = {}

  for line_num, section_info in pairs(line_to_section) do
    if section_info.module_line and not section_info.is_spacing and not section_info.is_header then
      local section_key = section_info.section_key
      local module_line = section_info.module_line
      local module_data = section_data[section_key].module_data
      local section_def = section_data[section_key].section_def

      if module_data.virtual_text and module_data.virtual_text[module_line] then
        -- Get module's virtual text configuration
        local plugin = get_module(section_def.plugin)
        local virt_config = plugin.get_virtual_text_config and plugin.get_virtual_text_config() or {
          default_hl_group = "Comment",
          namespace = "git_dashboard_virtual_text"
        }

        -- Create or reuse namespace for this module
        if not module_namespaces[virt_config.namespace] then
          module_namespaces[virt_config.namespace] = vim.api.nvim_create_namespace(virt_config.namespace)
          vim.api.nvim_buf_clear_namespace(bufnr, module_namespaces[virt_config.namespace], 0, -1)
        end

        local virtual_text_content = module_data.virtual_text[module_line]
        local ns_id = module_namespaces[virt_config.namespace]

        vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_num - 1, 0, {
          virt_text = { { virtual_text_content, virt_config.default_hl_group } },
          virt_text_pos = "eol"
        })
      end
    end
  end
end

-- Setup dashboard keymaps that delegate to modules
local function setup_dashboard_keymaps(bufnr, line_to_section, section_data)
  -- <CR> - delegate to module action or open section in full screen
  vim.keymap.set('n', '<CR>', function()
    local line_num = vim.api.nvim_win_get_cursor(0)[1]
    local section_info = line_to_section[line_num]

    if section_info then
      if section_info.is_header then
        -- Only branch picker available for headers now
        local section_key = section_info.section_key
        local section_def = section_data[section_key].section_def
        local plugin = get_module(section_def.plugin)

        if section_key == "branch" and plugin.show_branch_picker then
          plugin.show_branch_picker()
        end
      elseif section_info.module_line and not section_info.is_header then
        -- Execute regular module action
        local section_key = section_info.section_key
        local module_line = section_info.module_line
        local module_data = section_data[section_key].module_data

        if module_data.actions and module_data.actions[module_line] then
          module_data.actions[module_line]()
        end
      end
    end
  end, { buffer = bufnr, desc = "Execute action for item under cursor or open section in full screen" })

  -- gf - delegate to module gf_action if available, otherwise show file diff (only for staging sections)
  vim.keymap.set('n', 'gf', function()
    local line_num = vim.api.nvim_win_get_cursor(0)[1]
    local section_info = line_to_section[line_num]

    if section_info and section_info.module_line and not section_info.is_header then
      local section_key = section_info.section_key
      local module_line = section_info.module_line
      local module_data = section_data[section_key].module_data

      -- Only for staging sections, not commits
      if section_key == "staged" or section_key == "modified" or section_key == "untracked" then
        -- Try module-specific gf_action first
        if module_data.gf_action then
          module_data.gf_action(module_line)
        elseif module_data.file_map and module_data.file_map[module_line] then
          -- For file sections, open file
          local file = module_data.file_map[module_line]
          if type(file) == "string" then
            vim.cmd('edit ' .. vim.fn.fnameescape(utils.to_abs_path(file)))
          elseif type(file) == "table" and file.file then
            vim.cmd('edit ' .. vim.fn.fnameescape(utils.to_abs_path(file.file)))
          end
        end
      end
    end
  end, { buffer = bufnr, desc = "Open file in editor (staging sections only)" })

  -- <Tab> - delegate to tab actions (branch switching, staging operations)
  vim.keymap.set('n', '<Tab>', function()
    local line_num = vim.api.nvim_win_get_cursor(0)[1]
    local section_info = line_to_section[line_num]

    if section_info and section_info.module_line and not section_info.is_header then
      local section_key = section_info.section_key
      local module_line = section_info.module_line
      local module_data = section_data[section_key].module_data

      -- For branch section or staging sections
      if section_key == "branch" or section_key == "staged" or section_key == "modified" or section_key == "untracked" then
        if module_data.tab_action then
          module_data.tab_action(module_line)
        end
      end
    end
  end, { buffer = bufnr, desc = "Switch branch or stage/unstage file" })

  -- <S-Tab> - stage/unstage all files in current section
  vim.keymap.set('n', '<S-Tab>', function()
    local line_num = vim.api.nvim_win_get_cursor(0)[1]
    local section_info = line_to_section[line_num]
    local git_staging = require('gitcast.git-staging')

    if section_info then
      local section_key = section_info.section_key

      -- Only handle staging sections
      if section_key == "staged" or section_key == "modified" or section_key == "untracked" then
        git_staging.stage_all_in_section(section_key)
      else
        -- Fallback to stage all for other sections
        git_staging.stage_all()
      end
    else
      -- Fallback to stage all if no section detected
      git_staging.stage_all()
    end
  end, { buffer = bufnr, desc = "Stage/unstage all files in current section" })

  -- <BS> - delegate to backspace actions (checkout, unstage, delete)
  vim.keymap.set('n', '<BS>', function()
    local line_num = vim.api.nvim_win_get_cursor(0)[1]
    local section_info = line_to_section[line_num]

    if section_info and section_info.module_line and not section_info.is_header then
      local section_key = section_info.section_key
      local module_line = section_info.module_line
      local module_data = section_data[section_key].module_data

      -- For staging sections and commits
      if section_key == "staged" or section_key == "modified" or section_key == "untracked" or section_key == "commits" then
        if module_data.bs_action then
          module_data.bs_action(module_line)
        end
      end
    end
  end, { buffer = bufnr, desc = "Checkout/unstage/delete file or reset to commit" })

  -- Other useful commands
  vim.keymap.set('n', 'gcm', function()
    local git_staging = require('gitcast.git-staging')
    git_staging.commit_staged_changes()
  end, { buffer = bufnr, desc = "Commit staged changes" })

  vim.keymap.set('n', 'gca', function()
    local git_staging = require('gitcast.git-staging')
    git_staging.commit_amend()
  end, { buffer = bufnr, desc = "Commit amend (edit last commit)" })

  vim.keymap.set('n', 'gcf', function()
    local git_staging = require('gitcast.git-staging')
    git_staging.commit_fixup()
  end, { buffer = bufnr, desc = "Commit fixup (fixup to selected commit)" })

  vim.keymap.set('n', 'gsb', function()
    local git_branch = require('gitcast.git-branch')
    git_branch.show_branch_picker()
  end, { buffer = bufnr, desc = "Switch to existing branch" })

  vim.keymap.set('n', 'gcb', function()
    local git_branch = require('gitcast.git-branch')
    git_branch.show_create_branch_prompt()
  end, { buffer = bufnr, desc = "Checkout new branch" })

  vim.keymap.set('n', 'gpr', function()
    async_sys.git_pull_async({
      on_complete = function(success)
        if success then
          M.refresh_dashboard()
        end
      end
    })
  end, { buffer = bufnr, desc = "Git pull rebase" })

  vim.keymap.set('n', 'grm', function()
    local git_branch = require('gitcast.git-branch')
    git_branch.rebase_onto_main()
  end, { buffer = bufnr, desc = "Rebase current branch onto main/master" })

  vim.keymap.set('n', 'gsm', function()
    local git_branch = require('gitcast.git-branch')
    git_branch.squash_merge_into_tracking()
  end, { buffer = bufnr, desc = "Squash merge current branch into tracking branch" })

  vim.keymap.set('n', 'gp', function()
    async_sys.git_push_async()
  end, { buffer = bufnr, desc = "Git push" })

  vim.keymap.set('n', 'gP', function()
    async_sys.execute_async("git rev-parse --abbrev-ref HEAD", {
      show_progress = false,
      on_exit = function(result)
        if result.exit_code == 0 then
          local branch = result.stdout:gsub("%s+", "")
          vim.ui.confirm({
            msg = "Force push to " .. branch .. "?",
            default = false
          }, function(confirmed)
            if confirmed then
              async_sys.git_push_async({ force = true })
            end
          end)
        else
          vim.notify("Failed to get current branch", vim.log.levels.ERROR)
        end
      end
    })
  end, { buffer = bufnr, desc = "Git push force (with confirmation)" })

  vim.keymap.set('n', 'g?', function()
    M.show_help()
  end, { buffer = bufnr, desc = "Show help" })
end

-- Create dashboard buffer
local function create_dashboard_buffer()
  local name = utils.create_unique_buffer_name('GitCast')
  local bufnr = utils.create_view_buffer(name, 'gitcastdashboard')
  vim.bo[bufnr].buflisted = true
  return bufnr
end

-- Refresh dashboard content
function M.refresh_dashboard()
  if not M._current_buffer or not vim.api.nvim_buf_is_valid(M._current_buffer) then
    return
  end

  local content, line_to_section, section_data = compose_dashboard_content()

  -- Update buffer content
  vim.bo[M._current_buffer].modifiable = true
  vim.api.nvim_buf_set_lines(M._current_buffer, 0, -1, false, content)
  vim.bo[M._current_buffer].modifiable = false

  -- Apply highlighting and virtual text
  apply_dashboard_highlighting(M._current_buffer, line_to_section, section_data)
  add_dashboard_virtual_text(M._current_buffer, line_to_section, section_data)

  -- Update keymaps
  setup_dashboard_keymaps(M._current_buffer, line_to_section, section_data)

  -- Store section data for actions
  M._sections = { line_to_section = line_to_section, section_data = section_data }
end

-- Open dashboard
function M.open_dashboard()
  -- Check if current buffer is already valid and reuse it
  if M._current_buffer and vim.api.nvim_buf_is_valid(M._current_buffer) then
    vim.api.nvim_set_current_buf(M._current_buffer)
    M.refresh_dashboard()
    return
  else
    M._current_buffer = nil
  end

  -- Check if we're in a git repository
  if not utils.get_git_root() then
    vim.notify("Not in a git repository", vim.log.levels.ERROR)
    return
  end

  setup_highlights()

  -- Set refresh callback for staging operations
  local git_staging = require('gitcast.git-staging')
  git_staging.set_refresh_callback(M.refresh_dashboard)

  -- Set refresh callback for commit operations
  local git_commits = require('gitcast.git-commits')
  git_commits.set_refresh_callback(M.refresh_dashboard)

  -- Set refresh callback for branch operations
  local git_branch = require('gitcast.git-branch')
  git_branch.set_refresh_callback(M.refresh_dashboard)

  -- Set refresh callback for tracking operations
  local git_tracking = require('gitcast.git-tracking')
  git_tracking.set_refresh_callback(M.refresh_dashboard)

  local content, line_to_section, section_data = compose_dashboard_content()

  -- Create buffer
  local bufnr = create_dashboard_buffer()
  M._current_buffer = bufnr

  -- Set content
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
  vim.bo[bufnr].modifiable = false

  -- Apply highlighting and virtual text
  apply_dashboard_highlighting(bufnr, line_to_section, section_data)
  add_dashboard_virtual_text(bufnr, line_to_section, section_data)

  -- Set up keymaps
  setup_dashboard_keymaps(bufnr, line_to_section, section_data)

  -- Store section data
  M._sections = { line_to_section = line_to_section, section_data = section_data }

  -- Set up auto-refresh on buffer enter
  local enter_count = 0
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = bufnr,
    callback = function()
      enter_count = enter_count + 1
      if enter_count > 1 and M._current_buffer == bufnr then
        M.refresh_dashboard()
      end
    end,
  })

  -- Open buffer
  vim.api.nvim_set_current_buf(bufnr)

  -- Set cursor to first actionable line
  for line_num, section_info in pairs(line_to_section) do
    if section_info.module_line and not section_info.is_header then
      vim.api.nvim_win_set_cursor(0, { line_num, 0 })
      break
    end
  end
end

-- Show help
function M.show_help()
  local help_lines = {
    "GitCast Dashboard Help",
    "",
    "GLOBAL KEYMAPS & COMMANDS:",
    "  g?       Show this help",
    "  gcm      Commit staged changes",
    "  gca      Commit amend (edit last commit)",
    "  gcf      Commit fixup (fixup to selected commit)",
    "  gsb      Switch to existing branch",
    "  gcb      Checkout new branch",
    "  gpr      Git pull rebase",
    "  grm      Rebase current branch onto main/master",
    "  gsm      Squash merge current branch into tracking branch",
    "  gp       Git push",
    "  gP       Git push force (with confirmation)",
    "",
    "SECTION-SPECIFIC KEYMAPS:",
    "",
    "Branch Section (Head:):",
    "  <CR>     Show branch details (files changed vs main/master)",
    "  <Tab>    Switch to existing branch",
    "",
    "Commits Section:",
    "  <CR>     Show commit detail",
    "  <BS>     Mixed reset to parent of commit",
    "",
    "Staging Sections (staged/modified/untracked):",
    "  <CR>     Show file diff",
    "  gf       Open file in editor",
    "  <Tab>    Stage/unstage file",
    "  <S-Tab>  Stage/unstage all files in current section",
    "  <BS>     Checkout/unstage/delete file"
  }

  local width = 60
  local height = #help_lines + 2
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)
  vim.bo[buf].modifiable = false

  -- Add highlighting for sections
  local ns_id = vim.api.nvim_create_namespace("git_dashboard_help")
  vim.api.nvim_buf_add_highlight(buf, ns_id, "Title", 0, 0, -1)     -- Title
  vim.api.nvim_buf_add_highlight(buf, ns_id, "Special", 2, 0, -1)   -- GLOBAL KEYMAPS & COMMANDS
  vim.api.nvim_buf_add_highlight(buf, ns_id, "Special", 10, 0, -1)  -- SECTION-SPECIFIC KEYMAPS
  vim.api.nvim_buf_add_highlight(buf, ns_id, "Function", 12, 0, -1) -- Branch Section
  vim.api.nvim_buf_add_highlight(buf, ns_id, "Function", 15, 0, -1) -- Commits Section
  vim.api.nvim_buf_add_highlight(buf, ns_id, "Function", 20, 0, -1) -- Staging Sections

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

-- Setup function
function M.setup(opts)
  opts = opts or {}

  -- Update configuration
  if opts.performance_tracking ~= nil then
    config.performance_tracking = opts.performance_tracking
  end

  -- No user commands, GitCast command is created in gitcast/init.lua
end

return M

