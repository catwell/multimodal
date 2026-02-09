local argparse = require "argparse"
local cjson = require "cjson"
local terminal = require "terminal"
local sys = require("system")

-- Parse arguments
local parser = argparse("multimodal", "Watch Modal app logs")
parser:option("-e --env", "Modal environment")
parser:option("-m --modal-command", "Modal command"):default("modal")
local args = parser:parse()
local env = args["env"]
if not env then
   parser:error("--env is required")
end
env = env as string
local modal_cmd = args["modal_command"] as string

-- Validate env name
if (env as string):match("[^%w%-_]") then
   io.stderr:write("Invalid environment name\n")
   os.exit(1)
end

-- Get app list
local list_cmd = modal_cmd .. " app list --env '" .. (env as string) .. "' --json"
local list_handle = io.popen(list_cmd .. " 2>&1")
if not list_handle then
   io.stderr:write("Failed to run: " .. list_cmd .. "\n")
   os.exit(1)
end
local json_str = list_handle:read("*a")
local ok, _, code = list_handle:close()

if not ok then
   io.stderr:write("Command failed: " .. list_cmd .. "\n")
   if json_str and json_str ~= "" then
      io.stderr:write(json_str)
   end
   os.exit(code as integer or 1)
end

if not json_str or json_str == "" then
   io.stderr:write("No output from: " .. list_cmd .. "\n")
   os.exit(1)
end

-- Parse JSON and filter running apps
local record App
   id: string
   description: string
end

local all_apps = cjson.decode(json_str) as {any}
local apps: {App} = {}
for _, entry in ipairs(all_apps) do
   local a = entry as {string: any}
   local state = a["State"] as string
   if state ~= "stopped" then
      table.insert(apps, {
         id = a["App ID"] as string,
         description = a["Description"] as string,
      })
   end
end

if #apps == 0 then
   io.stderr:write("No running apps found\n")
   os.exit(0)
end

-- Create temp directory for log files
local tmp_dir = os.tmpname()
os.remove(tmp_dir)
os.execute("mkdir -p '" .. tmp_dir .. "'")

-- Lua filter: read stdin line by line, overwrite file with each non-empty line
local lua_interp = arg[-1] as string
local function lua_filter_prog(file: string): string
   return 'local F="' .. file .. '";local b="";'
      .. 'while true do local c=io.read(1);if not c then break end;'
      .. 'if c=="\\r" or c=="\\n" then '
      .. 'if b~="" then local f=io.open(F,"w");'
      .. 'if f then f:write(b);f:close() end end;b="" '
      .. 'else b=b..c end end'
end

-- Launch log processes piped through lua to keep only the last line
local record AppStream
   app: App
   pid: string
   log_file: string
   last_line: string
   row: integer
end

local streams: {AppStream} = {}
for i, app in ipairs(apps) do
   -- Validate app ID format
   if not app.id:match("^ap%-[%w]+$") then
      io.stderr:write("Invalid app ID: " .. app.id .. "\n")
      os.exit(1)
   end

   local log_file = tmp_dir .. "/" .. app.id
   local cmd = "PYTHONUNBUFFERED=1 " .. modal_cmd .. " app logs '" .. app.id
      .. "' 2>&1 | " .. lua_interp .. " -e '"
      .. lua_filter_prog(log_file) .. "' & echo $!"
   local handle = io.popen(cmd)
   if not handle then
      io.stderr:write("Failed to start log process for " .. app.id .. "\n")
      os.exit(1)
   end
   local pid = handle:read("*l")
   handle:close()

   if not pid or not pid:match("^%d+$") then
      io.stderr:write("Failed to read PID for " .. app.id .. "\n")
      os.exit(1)
   end

   table.insert(streams, {
      app = app,
      pid = pid,
      log_file = log_file,
      last_line = "",
      row = (i - 1) * 3 + 1,
   })
end

-- Strip ANSI escape sequences from a string
local function strip_ansi(s: string): string
   -- CSI sequences: ESC [ ... final_byte
   s = s:gsub("\027%[[\048-\063]*[\032-\047]*[\064-\126]", "")
   -- OSC sequences: ESC ] ... ST
   s = s:gsub("\027%][^\027]*\027\\", "")
   -- Two-byte escape sequences: ESC + single char
   s = s:gsub("\027[^\027%[]", "")
   return s
end

local selected = 1

local function update_rows()
   for i, stream in ipairs(streams) do
      stream.row = (i - 1) * 3 + 1
   end
end

-- Draw headers for all streams
local function draw_headers()
   for i, stream in ipairs(streams) do
      terminal.cursor.position.set(stream.row, 1)
      terminal.clear.line()
      if i == selected then
         terminal.text.stack.push({fg = "yellow", brightness = "bold"})
         terminal.output.write("> ")
      else
         terminal.output.write("  ")
      end
      terminal.text.stack.push({fg = "cyan", brightness = "bold"})
      terminal.output.write(
         stream.app.description .. " (" .. stream.app.id .. ")"
      )
      terminal.text.stack.pop(i == selected and 2 or 1)
   end
end

-- Cleanup helper
local function cleanup()
   for _, stream in ipairs(streams) do
      os.execute("kill " .. stream.pid .. " 2>/dev/null")
   end
   os.execute("rm -rf '" .. tmp_dir .. "'")
end

local function stop_selected()
   local stream = streams[selected]
   local rows = terminal.size()
   terminal.cursor.position.set(rows, 1)
   terminal.clear.line()
   terminal.text.stack.push({fg = "yellow"})
   terminal.output.write(
      "Stop " .. stream.app.description
      .. " (" .. stream.app.id .. ")? (y/N) "
   )
   terminal.text.stack.pop(1)
   terminal.cursor.visible.set(true)

   while true do
      local key = terminal.input.readansi(0.1)
      if key then
         terminal.cursor.visible.set(false)
         terminal.cursor.position.set(rows, 1)
         terminal.clear.line()
         if key == "y" or key == "Y" then
            os.execute(
               modal_cmd .. " app stop '" .. stream.app.id .. "' 2>/dev/null"
            )
            os.execute("kill " .. stream.pid .. " 2>/dev/null")
            table.remove(streams, selected)
            if selected > #streams then
               selected = #streams
            end
            update_rows()
            terminal.clear.screen()
            draw_headers()
         end
         return
      end
   end
end

-- Main display function
local function main()
   terminal.cursor.visible.set(false)
   terminal.clear.screen()
   draw_headers()

   -- Main loop
   while #streams > 0 do
      local key = terminal.input.readansi(0)
      if key == "\3" then -- Ctrl+C
         break
      elseif key == "\27[A" then -- Up arrow
         if selected > 1 then
            selected = selected - 1
            draw_headers()
         end
      elseif key == "\27[B" then -- Down arrow
         if selected < #streams then
            selected = selected + 1
            draw_headers()
         end
      elseif key == "\13" or key == "\10" then -- Enter
         stop_selected()
      end

      -- Read from each log file
      local _, cols = terminal.size()
      local needs_header_redraw = false
      for _, stream in ipairs(streams) do
         local f = io.open(stream.log_file, "r")
         if f then
            local data = f:read("*a")
            f:close()

            if data and #data > 0 then
               -- Strip ANSI escape sequences and trailing whitespace
               local current_line = strip_ansi(data)
               current_line = current_line:gsub("[%s]+$", "")

               if current_line ~= stream.last_line then
                  stream.last_line = current_line
                  needs_header_redraw = true

                  -- Truncate to terminal width
                  local display_line = current_line
                  if #display_line > cols then
                     display_line = display_line:sub(1, cols)
                  end

                  terminal.cursor.position.set(stream.row + 1, 1)
                  terminal.clear.line()
                  terminal.text.stack.apply()
                  terminal.output.write(display_line)
               end
            end
         end
      end

      -- Redraw headers after log updates in case they were corrupted
      if needs_header_redraw then
         draw_headers()
      end

      sys.sleep(0.1)
   end

   cleanup()
   terminal.cursor.visible.set(true)
end

-- Run with terminal wrapper for clean init/shutdown
local wrapped = terminal.initwrap(main, {
   displaybackup = true,
   disable_sigint = true,
   autotermrestore = true,
})
wrapped()
