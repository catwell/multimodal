local argparse = require "argparse"
local cjson = require "cjson"
local sys = require "system"

math.randomseed(math.floor(sys.gettime() * 1000))

local parser = argparse("fakemodal", "Mock for modal CLI")
parser:require_command(true)
parser:command_target("command")

local app = parser:command("app", "App commands")
app:require_command(true)
app:command_target("subcommand")

local list = app:command("list", "List apps")
list:option("-e --env", "Modal environment")
list:flag("--json", "Output as JSON")

local logs = app:command("logs", "Stream app logs")
logs:argument("app_id", "App ID")

local args = parser:parse()

local apps = {
   {
      ["App ID"] = "ap-fake0",
      ["Description"] = "stopped app",
      ["State"] = "stopped",
   },
   {
      ["App ID"] = "ap-fake1",
      ["Description"] = "test app 1",
      ["State"] = "deployed",
   },
   {
      ["App ID"] = "ap-fake2",
      ["Description"] = "test app 2",
      ["State"] = "deployed",
   },
   {
      ["App ID"] = "ap-fake3",
      ["Description"] = "test app 3",
      ["State"] = "deployed",
   },
}

local function app_list()
   local data = args["env"] == "test" and apps or {}
   io.write(cjson.encode(data as cjson.Serializable) .. "\n")
end

local function app_logs(app_id: string)
   local found = false
   for _, a in ipairs(apps) do
      if a["App ID"] == app_id and a["State"] ~= "stopped" then
         found = true
         break
      end
   end
   if not found then
      io.stderr:write("Error: Could not find a deployed app named '" .. app_id .. "'.\n")
      os.exit(1)
   end
   local counter = 1
   while true do
      local t = os.date("*t") as {string: integer}
      local timestamp = string.format("%02d:%02d:%02d", t.hour, t.min, t.sec)
      io.write("\r" .. timestamp .. " test log from app " .. app_id .. " " .. tostring(counter))
      io.flush()
      counter = counter + 1
      local delay = 0.2 + math.random() * 1.8
      sys.sleep(delay)
   end
end

if args["subcommand"] == "list" then
   app_list()
elseif args["subcommand"] == "logs" then
   app_logs(args["app_id"] as string)
end
