local M = {}

local function get_caller_info()
  local info = debug.getinfo(3, "Sl")
  if info then
    local file = info.source:match("@?(.*)") or "unknown"
    local line = info.currentline or 0
    local short_file = file:match("([^/]+)$") or file
    return string.format("%s:%d", short_file, line)
  end
  return "unknown:0"
end

local function should_log()
  local git_dashboard = package.loaded['gitcast.git-dashboard']
  return git_dashboard and git_dashboard._log_performance
end

local active_jobs = {}

local function create_progress_indicator(cmd)
  local short_cmd = cmd:sub(1, 30)
  if #cmd > 30 then
    short_cmd = short_cmd .. "..."
  end
  
  local frames = {"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
  local current_frame = 1
  local timer = vim.loop.new_timer()
  
  local function update_progress()
    vim.schedule(function()
      vim.notify(frames[current_frame] .. " " .. short_cmd, vim.log.levels.INFO, {
        replace = "gitcast_progress_" .. short_cmd,
        timeout = 100
      })
      current_frame = (current_frame % #frames) + 1
    end)
  end
  
  timer:start(0, 100, update_progress)
  
  return {
    stop = function()
      timer:stop()
      timer:close()
      vim.schedule(function()
        vim.notify("", vim.log.levels.INFO, {
          replace = "gitcast_progress_" .. short_cmd,
          timeout = 1
        })
      end)
    end
  }
end

function M.execute_async(cmd, opts)
  opts = opts or {}
  local on_exit = opts.on_exit
  local on_stdout = opts.on_stdout
  local on_stderr = opts.on_stderr
  local show_progress = opts.show_progress ~= false
  
  local stdout_data = {}
  local stderr_data = {}
  local start_time = vim.loop.hrtime()
  local caller = get_caller_info()
  local progress_indicator = nil
  
  if show_progress then
    progress_indicator = create_progress_indicator(cmd)
  end
  
  local job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data, _)
      if data and #data > 0 then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stdout_data, line)
            if on_stdout then
              on_stdout(line)
            end
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data and #data > 0 then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stderr_data, line)
            if on_stderr then
              on_stderr(line)
            end
          end
        end
      end
    end,
    on_exit = function(job_id, exit_code, _)
      if progress_indicator then
        progress_indicator.stop()
      end
      
      active_jobs[job_id] = nil
      
      local duration = (vim.loop.hrtime() - start_time) / 1000000
      
      if should_log() then
        local short_cmd = cmd
        if #cmd > 50 then
          short_cmd = cmd:sub(1, 47) .. "..."
        end
        
        local git_dashboard = package.loaded['gitcast.git-dashboard']
        if git_dashboard and git_dashboard._log_performance then
          git_dashboard._log_performance({
            time = string.format("%.1fms", duration),
            file = caller,
            cmd = short_cmd,
            async = true
          })
        end
      end
      
      if on_exit then
        vim.schedule(function()
          on_exit({
            exit_code = exit_code,
            stdout = table.concat(stdout_data, "\n"),
            stderr = table.concat(stderr_data, "\n"),
            duration = duration
          })
        end)
      end
    end
  })
  
  if job_id <= 0 then
    if progress_indicator then
      progress_indicator.stop()
    end
    if on_exit then
      on_exit({
        exit_code = -1,
        stdout = "",
        stderr = "Failed to start job",
        duration = 0
      })
    end
  else
    active_jobs[job_id] = cmd
  end
  
  return job_id
end

function M.cancel_all_jobs()
  for job_id, _ in pairs(active_jobs) do
    vim.fn.jobstop(job_id)
  end
  active_jobs = {}
end

function M.git_pull_async(opts)
  opts = opts or {}
  local branch = opts.branch
  
  if not branch then
    M.execute_async("git rev-parse --abbrev-ref HEAD", {
      show_progress = false,
      on_exit = function(result)
        if result.exit_code == 0 then
          branch = result.stdout:gsub("%s+", "")
          local cmd = "git pull --rebase origin " .. vim.fn.shellescape(branch)
          
          M.execute_async(cmd, {
            show_progress = true,
            on_exit = function(pull_result)
              if pull_result.exit_code == 0 then
                vim.notify("Pull rebase completed", vim.log.levels.INFO)
                if opts.on_complete then
                  opts.on_complete(true)
                end
              else
                vim.notify("Pull rebase failed: " .. pull_result.stderr, vim.log.levels.ERROR)
                if opts.on_complete then
                  opts.on_complete(false, pull_result.stderr)
                end
              end
            end
          })
        else
          vim.notify("Failed to get current branch", vim.log.levels.ERROR)
          if opts.on_complete then
            opts.on_complete(false, "Failed to get current branch")
          end
        end
      end
    })
  else
    local cmd = "git pull --rebase origin " .. vim.fn.shellescape(branch)
    M.execute_async(cmd, {
      show_progress = true,
      on_exit = function(result)
        if result.exit_code == 0 then
          vim.notify("Pull rebase completed", vim.log.levels.INFO)
          if opts.on_complete then
            opts.on_complete(true)
          end
        else
          vim.notify("Pull rebase failed: " .. result.stderr, vim.log.levels.ERROR)
          if opts.on_complete then
            opts.on_complete(false, result.stderr)
          end
        end
      end
    })
  end
end

function M.git_push_async(opts)
  opts = opts or {}
  local branch = opts.branch
  local force = opts.force
  
  if not branch then
    M.execute_async("git rev-parse --abbrev-ref HEAD", {
      show_progress = false,
      on_exit = function(result)
        if result.exit_code == 0 then
          branch = result.stdout:gsub("%s+", "")
          local cmd = "git push origin " .. vim.fn.shellescape(branch)
          if force then
            cmd = cmd .. " --force-with-lease"
          end
          
          M.execute_async(cmd, {
            show_progress = true,
            on_exit = function(push_result)
              if push_result.exit_code == 0 then
                vim.notify(force and "Force push completed" or "Push completed", vim.log.levels.INFO)
                if opts.on_complete then
                  opts.on_complete(true)
                end
              else
                vim.notify((force and "Force push" or "Push") .. " failed: " .. push_result.stderr, vim.log.levels.ERROR)
                if opts.on_complete then
                  opts.on_complete(false, push_result.stderr)
                end
              end
            end
          })
        else
          vim.notify("Failed to get current branch", vim.log.levels.ERROR)
          if opts.on_complete then
            opts.on_complete(false, "Failed to get current branch")
          end
        end
      end
    })
  else
    local cmd = "git push origin " .. vim.fn.shellescape(branch)
    if force then
      cmd = cmd .. " --force-with-lease"
    end
    
    M.execute_async(cmd, {
      show_progress = true,
      on_exit = function(result)
        if result.exit_code == 0 then
          vim.notify(force and "Force push completed" or "Push completed", vim.log.levels.INFO)
          if opts.on_complete then
            opts.on_complete(true)
          end
        else
          vim.notify((force and "Force push" or "Push") .. " failed: " .. result.stderr, vim.log.levels.ERROR)
          if opts.on_complete then
            opts.on_complete(false, result.stderr)
          end
        end
      end
    })
  end
end

function M.git_rebase_async(target_branch, opts)
  opts = opts or {}
  local cmd = string.format("git rebase %s", vim.fn.shellescape(target_branch))
  
  M.execute_async(cmd, {
    show_progress = true,
    on_exit = function(result)
      if result.exit_code == 0 then
        vim.notify("Rebase completed successfully", vim.log.levels.INFO)
        if opts.on_complete then
          opts.on_complete(true)
        end
      else
        vim.notify("Rebase failed: " .. result.stderr, vim.log.levels.ERROR)
        vim.notify("You may need to resolve conflicts and run 'git rebase --continue' or 'git rebase --abort'", vim.log.levels.INFO)
        if opts.on_complete then
          opts.on_complete(false, result.stderr)
        end
      end
    end
  })
end

return M