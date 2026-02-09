local argparse = require "argparse"
local cjson = require "cjson"
local terminal = require "terminal"
local sys = require("system")

-- Parse arguments
local parser = argparse("multimodal", "Watch Modal app logs")
parser:option("-e --env", "Modal environment")
local args = parser:parse()
local env = args["env"]
if not env then
   parser:error("--env is required")
end
env = env as string

-- Validate env name
if (env as string):match("[^%w%-_]") then
   io.stderr:write("Invalid environment name\n")
   os.exit(1)
end

-- Get app list
local list_handle = io.popen(
   "modal app list --env '" .. (env as string) .. "' --json"
)
if not list_handle then
   io.stderr:write("Failed to run modal app list\n")
   os.exit(1)
end
local json_str = list_handle:read("*a")
list_handle:close()

if not json_str or json_str == "" then
   io.stderr:write("No output from modal app list\n")
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

-- awk program: split on \r or \n, overwrite file with each non-empty record
local awk_prog = [[BEGIN{RS="[\r\n]+"} /./{print > F; close(F)}]]

-- Launch log processes piped through awk to keep only the last line
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
   local cmd = "PYTHONUNBUFFERED=1 modal app logs '" .. app.id
      .. "' 2>&1 | awk -v F='" .. log_file
      .. "' '" .. awk_prog .. "' & echo $!"
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

-- Draw headers for all streams
local function draw_headers()
   for _, stream in ipairs(streams) do
      terminal.cursor.position.set(stream.row, 1)
      terminal.clear.line()
      terminal.text.stack.push({fg = "cyan", brightness = "bold"})
      terminal.output.write(
         stream.app.description .. " (" .. stream.app.id .. ")"
      )
      terminal.text.stack.pop(1)
   end
end

-- Cleanup helper
local function cleanup()
   for _, stream in ipairs(streams) do
      os.execute("kill " .. stream.pid .. " 2>/dev/null")
   end
   os.execute("rm -rf '" .. tmp_dir .. "'")
end

-- Main display function
local function main()
   terminal.cursor.visible.set(false)
   terminal.clear.screen()
   draw_headers()

   -- Main loop
   while true do
      -- Check for ctrl+c
      local key = terminal.input.readansi(0)
      if key == "\3" then
         break
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
