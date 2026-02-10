local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local io = _tl_compat and _tl_compat.io or io; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local os = _tl_compat and _tl_compat.os or os; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local argparse = require("argparse")
local cjson = require("cjson")
local terminal = require("terminal")
local sys = require("system")


local parser = argparse("multimodal", "Watch Modal app logs")
parser:option("-e --env", "Modal environment")
parser:option("-m --modal-command", "Modal command"):default("modal")
parser:option("-n --num-lines", "Number of log lines to keep per app"):default("1"):convert(tonumber)
local args = parser:parse()
local num_lines = args["num_lines"]
local env = args["env"]
if not env then
   parser:error("--env is required")
end
env = env
local modal_cmd = args["modal_command"]


if (env):match("[^%w%-_]") then
   io.stderr:write("Invalid environment name\n")
   os.exit(1)
end


local list_cmd = modal_cmd .. " app list --env '" .. (env) .. "' --json"
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
   os.exit(code or 1)
end

if not json_str or json_str == "" then
   io.stderr:write("No output from: " .. list_cmd .. "\n")
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




local lua_interp
do
   local i = -1
   while arg[i] do i = i - 1 end
   lua_interp = arg[i + 1]
end

local filter_script = [[
   local fn = arg[1]
   local nrows = tonumber(arg[2])
   local row, rows = {}, {}
   while true do
      local c = io.read(1)
      if not c then break end
      if c == "\r" or c == "\n" then
         local line = table.concat(row)
         if line ~= "" then
            rows[#rows + 1] = line
            if #rows > nrows then
               table.remove(rows, 1)
            end
            local f = io.open(fn, "w")
            if f then
               f:write(table.concat(rows, "\n"))
               f:close()
            end
         end
         row = {}
      else
         row[#row + 1] = c
      end
   end
]]

local function write_filter_script(script_path)
   local f = io.open(script_path, "w")
   if not f then
      io.stderr:write("Failed to write filter script: " .. script_path .. "\n")
      os.exit(1)
   end
   f:write(filter_script)
   f:close()
end










local streams = {}
for i, app in ipairs(apps) do

   if not app.id:match("^ap%-[%w]+$") then
      io.stderr:write("Invalid app ID: " .. app.id .. "\n")
      os.exit(1)
   end

   local log_file = tmp_dir .. "/" .. app.id
   local script_file = tmp_dir .. "/" .. app.id .. ".lua"
   write_filter_script(script_file)
   local cmd = "PYTHONUNBUFFERED=1 " .. modal_cmd .. " app logs '" .. app.id ..
   "' 2>&1 | " .. lua_interp .. " '" .. script_file ..
   "' '" .. log_file .. "' " .. num_lines .. " & echo $!"
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
      row = (i - 1) * (num_lines + 2) + 1,
   })
end


local function strip_ansi(s)

   s = s:gsub("\027%[[\048-\063]*[\032-\047]*[\064-\126]", "")

   s = s:gsub("\027%][^\027]*\027\\", "")

   s = s:gsub("\027[^\027%[]", "")
   return s
end

local key_map = terminal.input.keymap.default_key_map
local keys = terminal.input.keymap.default_keys

local selected = 1

local function update_rows()
   for i, stream in ipairs(streams) do
      stream.row = (i - 1) * (num_lines + 2) + 1
   end
end


local function draw_headers()
   for i, stream in ipairs(streams) do
      terminal.cursor.position.set(stream.row, 1)
      terminal.clear.line()
      if i == selected then
         terminal.text.stack.push({ fg = "yellow", brightness = "bold" })
         terminal.output.write("> ")
      else
         terminal.output.write("  ")
      end
      terminal.text.stack.push({ fg = "cyan", brightness = "bold" })
      terminal.output.write(
      stream.app.description .. " (" .. stream.app.id .. ")")

      terminal.text.stack.pop(i == selected and 2 or 1)
   end
end


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
   terminal.text.stack.push({ fg = "yellow" })
   terminal.output.write(
   "Stop " .. stream.app.description ..
   " (" .. stream.app.id .. ")? (y/N) ")

   terminal.text.stack.pop(1)
   terminal.cursor.visible.set(true)

   while true do
      local rawkey = terminal.input.readansi(0.1)
      if rawkey then
         terminal.cursor.visible.set(false)
         terminal.cursor.position.set(rows, 1)
         terminal.clear.line()
         if rawkey == "y" or rawkey == "Y" then
            os.execute(
            modal_cmd .. " app stop '" .. stream.app.id .. "' 2>/dev/null")

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


local function main()
   terminal.cursor.visible.set(false)
   terminal.clear.screen()
   draw_headers()


   while #streams > 0 do
      local rawkey = terminal.input.readansi(0)
      local keyname = rawkey and key_map[rawkey]
      if keyname == keys.ctrl_c then
         break
      elseif keyname == keys.up then
         if selected > 1 then
            selected = selected - 1
            draw_headers()
         end
      elseif keyname == keys.down then
         if selected < #streams then
            selected = selected + 1
            draw_headers()
         end
      elseif keyname == keys.enter then
         stop_selected()
      end


      local _, cols = terminal.size()
      local needs_header_redraw = false
      for _, stream in ipairs(streams) do
         local f = io.open(stream.log_file, "r")
         if f then
            local data = f:read("*a")
            f:close()

            if data and #data > 0 then

               local current_data = strip_ansi(data)
               current_data = current_data:gsub("[%s]+$", "")

               if current_data ~= stream.last_line then
                  stream.last_line = current_data
                  needs_header_redraw = true


                  local lines = {}
                  for line in current_data:gmatch("[^\n]+") do
                     table.insert(lines, line)
                  end
                  for j = 1, num_lines do
                     terminal.cursor.position.set(stream.row + j, 1)
                     terminal.clear.line()
                     terminal.text.stack.apply()
                     local line = lines[j]
                     if line then
                        if #line > cols then
                           line = line:sub(1, cols)
                        end
                        terminal.output.write(line)
                     end
                  end
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
