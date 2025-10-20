-- gitcast/utils.lua - Utility functions for GitCast
local M = {}

-- Create a read-only display buffer (for status displays, diffs, etc.)
function M.create_view_buffer(name, filetype)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(bufnr, 'swapfile', false)
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)

  if filetype then
    vim.api.nvim_buf_set_option(bufnr, 'filetype', filetype)
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

-- Get git repository root
function M.get_git_root()
  local root_output = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null")
  if vim.v.shell_error == 0 then
    return root_output:gsub("%s+$", "") -- trim trailing whitespace
  end
  return nil
end

return M