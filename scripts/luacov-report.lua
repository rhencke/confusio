-- Run luacov reporter on .init.lua and check coverage against threshold.
-- Usage: ./redbean.com -i scripts/luacov-report.lua
-- Requires luacov/ to exist (make luacov) and luacov.stats.out to exist (COVERAGE=1 run).

local THRESHOLD = 97 -- percent

package.path = "luacov/?.lua;" .. package.path
local runner = require("luacov.runner")
local configuration = runner.load_config()
configuration.include = { "^%.init$" }
runner.run_report(configuration)

-- Parse coverage percentage from summary line in luacov.report.out.
local f = io.open("luacov.report.out", "r")
if not f then
  io.stderr:write("luacov.report.out not found\n")
  os.exit(1)
end
local pct
for line in f:lines() do
  local hit, missed = line:match("^%.init%.lua%s+(%d+)%s+(%d+)")
  if hit then
    hit, missed = tonumber(hit), tonumber(missed)
    pct = hit / (hit + missed) * 100
    break
  end
end
f:close()

if not pct then
  io.stderr:write("could not find .init.lua coverage line in report\n")
  os.exit(1)
end

io.write(string.format(".init.lua coverage: %.2f%% (threshold: %d%%)\n", pct, THRESHOLD))
if pct < THRESHOLD then
  io.stderr:write(string.format("FAIL: coverage %.2f%% is below threshold %d%%\n", pct, THRESHOLD))
  os.exit(1)
end
io.write("PASS\n")
