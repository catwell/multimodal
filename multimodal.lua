local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local io = _tl_compat and _tl_compat.io or io; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local os = _tl_compat and _tl_compat.os or os; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local argparse = require("argparse")
local cjson = require("cjson")
local terminal = require("terminal")
local sys = require("system")


local parser = argparse("multimodal", "Watch Modal app logs")
parser:option("-e --env", "Modal environment")
local args = parser:parse()
local env = args["env"]
if not env then
   parser:error("--env is required")
end
env = env


if (env):match("[^%w%-_]") then
   io.stderr:write("Invalid environment name\n")
   os.exit(1)
end


local list_handle = io.popen(
"modal app list --env '" .. (env) .. "' --json")

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







local all_apps = cjson.decode(json_str)
local apps = {}
for _, entry in ipairs(all_apps) do
   local a = entry
   local state = a["State"]
   if state ~= "stopped" then
      table.insert(apps, {
         id = a["App ID"],
         description = a["Description"],
      })
   end
end

if #apps == 0 then
   io.stderr:write("No running apps found\n")
   os.exit(0)
end


local tmp_dir = os.tmpname()
os.remove(tmp_dir)
os.execute("mkdir -p '" .. tmp_dir .. "'")


local awk_prog = [[BEGIN{RS="[\r\n]+"} /./{print > F; close(F)}]]










local streams = {}
for i, app in ipairs(apps) do

   if not app.id:match("^ap%-[%w]+$") then
      io.stderr:write("Invalid app ID: " .. app.id .. "\n")
      os.exit(1)
   end

   local log_file = tmp_dir .. "/" .. app.id
   local cmd = "PYTHONUNBUFFERED=1 modal app logs '" .. app.id ..
   "' 2>&1 | awk -v F='" .. log_file ..
   "' '" .. awk_prog .. "' & echo $!"
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


local function strip_ansi(s)

   s = s:gsub("\027%[[\048-\063]*[\032-\047]*[\064-\126]", "")

   s = s:gsub("\027%][^\027]*\027\\", "")

   s = s:gsub("\027[^\027%[]", "")
   return s
end


local function draw_headers()
   for _, stream in ipairs(streams) do
      terminal.cursor.position.set(stream.row, 1)
      terminal.clear.line()
      terminal.text.stack.push({ fg = "cyan", brightness = "bold" })
      terminal.output.write(
      stream.app.description .. " (" .. stream.app.id .. ")")

      terminal.text.stack.pop(1)
   end
end


local function cleanup()
   for _, stream in ipairs(streams) do
      os.execute("kill " .. stream.pid .. " 2>/dev/null")
   end
   os.execute("rm -rf '" .. tmp_dir .. "'")
end


local function main()
   terminal.cursor.visible.set(false)
   terminal.clear.screen()
   draw_headers()


   while true do

      local key = terminal.input.readansi(0)
      if key == "\3" then
         break
      end


      local _, cols = terminal.size()
      local needs_header_redraw = false
      for _, stream in ipairs(streams) do
         local f = io.open(stream.log_file, "r")
         if f then
            local data = f:read("*a")
            f:close()

            if data and #data > 0 then

               local current_line = strip_ansi(data)
               current_line = current_line:gsub("[%s]+$", "")

               if current_line ~= stream.last_line then
                  stream.last_line = current_line
                  needs_header_redraw = true


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


      if needs_header_redraw then
         draw_headers()
      end

      sys.sleep(0.1)
   end

   cleanup()
   terminal.cursor.visible.set(true)
end


local wrapped = terminal.initwrap(main, {
   displaybackup = true,
   disable_sigint = true,
   autotermrestore = true,
})
wrapped()
