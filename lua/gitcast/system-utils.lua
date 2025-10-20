-- system-utils.lua - Centralized system call wrapper with performance tracking
local M = {}

-- Get caller information using debug.getinfo
local function get_caller_info()
  local info = debug.getinfo(3, "Sl") -- 3 levels up: system_call -> vim.fn.system -> actual caller
  if info then
    local file = info.source:match("@?(.*)") or "unknown"
    local line = info.currentline or 0
    -- Shorten file path for readability
    local short_file = file:match("([^/]+)$") or file
    return string.format("%s:%d", short_file, line)
  end
  return "unknown:0"
end

-- Check if performance tracking is enabled
local function should_log()
  local git_dashboard = package.loaded['gitcast.git-dashboard']
  return git_dashboard and git_dashboard._log_performance
end

-- Wrapper for vim.fn.system with performance tracking
function M.system(cmd)
  if not should_log() then
    return vim.fn.system(cmd)
  end
  
  local caller = get_caller_info()
  local start_time = vim.loop.hrtime()
  local result = vim.fn.system(cmd)
  local duration = (vim.loop.hrtime() - start_time) / 1000000
  
  -- Truncate long commands for readability
  local short_cmd = cmd
  if #cmd > 50 then
    short_cmd = cmd:sub(1, 47) .. "..."
  end
  
  local git_dashboard = package.loaded['gitcast.git-dashboard']
  if git_dashboard and git_dashboard._log_performance then
    git_dashboard._log_performance({
      time = string.format("%.1fms", duration),
      file = caller,
      cmd = short_cmd
    })
  end
  
  return result
end

-- Wrapper for io.popen with performance tracking
function M.popen(cmd, mode)
  if not should_log() then
    return io.popen(cmd, mode)
  end
  
  local caller = get_caller_info()
  local start_time = vim.loop.hrtime()
  local handle = io.popen(cmd, mode)
  
  if handle then
    -- Create a wrapper table that tracks timing
    local wrapper = {}
    
    wrapper.read = function(self, ...)
      return handle:read(...)
    end
    
    wrapper.close = function(self)
      local total_duration = (vim.loop.hrtime() - start_time) / 1000000
      
      -- Truncate long commands for readability
      local short_cmd = cmd
      if #cmd > 50 then
        short_cmd = cmd:sub(1, 47) .. "..."
      end
      
      local git_dashboard = package.loaded['gitcast.git-dashboard']
      if git_dashboard and git_dashboard._log_performance then
        git_dashboard._log_performance({
          time = string.format("%.1fms", total_duration),
          file = caller,
          cmd = short_cmd
        })
      end
      
      return handle:close()
    end
    
    -- Forward other methods if needed
    setmetatable(wrapper, {
      __index = handle
    })
    
    return wrapper
  end
  
  return handle
end

return M