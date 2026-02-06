-- gitcast/utils.lua - Utility functions for GitCast
local M = {}

-- Create a read-only display buffer (for status displays, diffs, etc.)
function M.create_view_buffer(name, filetype)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false

  if filetype then
    vim.bo[bufnr].filetype = filetype
  end

  if name then
    vim.api.nvim_buf_set_name(bufnr, name)
  end

  return bufnr
end

-- Create a unique buffer name with counter if needed
function M.create_unique_buffer_name(base_name)
  local name = base_name
  local counter = 1
  while vim.fn.bufexists(name) == 1 do
    name = base_name .. '-' .. counter
    counter = counter + 1
  end
  return name
end

-- Cached git root
local _git_root_cache = nil

-- Get git repository root (cached)
function M.get_git_root()
  if _git_root_cache then
    return _git_root_cache
  end
  local root_output = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null")
  if vim.v.shell_error == 0 then
    _git_root_cache = root_output:gsub("%s+$", "") -- trim trailing whitespace
    return _git_root_cache
  end
  return nil
end

-- Convert a git-root-relative path to an absolute path.
-- Git commands return paths relative to the repo root, but filesystem
-- operations (filereadable, edit, delete) resolve relative to Neovim's CWD.
-- In monorepo subfolders, CWD != git root, so we must use absolute paths.
function M.to_abs_path(file)
  if not file then return file end
  -- Already absolute
  if file:sub(1, 1) == "/" then return file end
  local root = M.get_git_root()
  if root then
    return root .. "/" .. file
  end
  return file
end

-- Clear cached git root (e.g. when switching repositories)
function M.clear_git_root_cache()
  _git_root_cache = nil
end

return M