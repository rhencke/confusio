-- Unit tests for all global functions in .init.lua.
-- Run from project root: sh redbean.com -i test/unit-init.lua
-- ============================================================

-- Enable luacov coverage tracing when COVERAGE=1.
-- Requires: make luacov (downloads luacov source to ./luacov/).
if os.getenv("COVERAGE") then
  package.path = "luacov/?.lua;" .. package.path
  require("luacov")
end

-- Stub state for the Redbean HTTP context APIs.
local _last_status, _last_headers, _last_body
local _req_headers, _req_path, _req_params, _req_method, _req_body

local function reset_response()
  _last_status = nil
  _last_headers = {}
  _last_body = ""
end

local function reset_request(opts)
  opts = opts or {}
  _req_headers = opts.headers or {}
  _req_path = opts.path or "/"
  _req_params = opts.params or {}
  _req_method = opts.method or "GET"
  _req_body = opts.body or nil
end

reset_response()
reset_request()

-- Override Redbean HTTP context built-ins before loading .init.lua.
-- luacheck: push
-- luacheck: globals SetStatus SetHeader Write GetHeader GetPath GetParam GetMethod GetBody Route
-- luacheck: globals GetCryptoHash DecodeBase64 SourcehutVerifyEd25519 CodeCommitVerifySnsSignature
SetStatus = function(code, _reason)
  _last_status = code
end
SetHeader = function(k, v)
  _last_headers[k] = v
end
Write = function(s)
  _last_body = _last_body .. tostring(s)
end
GetHeader = function(k)
  return _req_headers[k]
end
GetPath = function()
  return _req_path
end
GetParam = function(k)
  return _req_params[k]
end
GetMethod = function()
  return _req_method
end
Route = function() end
GetBody = function()
  return _req_body
end
-- Stub GetCryptoHash: returns a fixed 32-byte string so unit tests can exercise
-- the signature verification logic without requiring real crypto.  Integration
-- tests that need real HMAC run against the live binary where GetCryptoHash is
-- implemented by Redbean's C layer.
GetCryptoHash = function(_alg, _msg, _key)
  return string.rep("\xaa", 32)
end
-- Stub GetRandomBytes: returns a deterministic byte sequence so make_uuid produces a
-- predictable value in tests.  Byte i = (i * 17) % 256, giving 16 distinct bytes.
GetRandomBytes = function(n) -- luacheck: globals GetRandomBytes
  local t = {}
  for i = 1, n do
    t[i] = string.char((i * 17) % 256)
  end
  return table.concat(t)
end
-- Stub DecodeBase64: identity decode for Basic auth verification tests.
DecodeBase64 = function(s)
  return s
end
SourcehutVerifyEd25519 = function(public_key, body, signature)
  return public_key == string.rep("k", 32) and body == "{}" and signature == string.rep("s", 64)
end
CodeCommitVerifySnsSignature = nil
-- Stub Fetch: records outbound calls so startup synthesis (synthesize_startup_events)
-- and deliver_fire tests do not make real network requests.  Returns a 200 response.
-- Individual tests that need more control save/restore Fetch locally.
local _fetch_calls = {}
Fetch = function(url, opts) -- luacheck: globals Fetch _fetch_calls
  _fetch_calls[#_fetch_calls + 1] = { url = url, opts = opts }
  return 200, {}, "{}"
end
-- luacheck: pop

-- Prevent backend file loading (config.backend will be "" anyway, but be safe).
-- Redirect /zip/internal/ to the internal/ directory on the filesystem so unit
-- tests can load internal modules without a Redbean zip.
local _real_dofile = dofile
function dofile(path) -- luacheck: globals dofile
  if path and path:match("^/zip/backends/") then
    return
  end
  if path and path:match("^/zip/internal/") then
    return _real_dofile(path:sub(6))
  end
  return _real_dofile(path)
end

-- Exercise the read_secret_file error branches in .init.lua before the main
-- init call.  Each case loads .init.lua in a pcall with a bad arg; the early
-- error exits before any module loading, so the main test environment is
-- unaffected by the repeated calls.  Uses bare assert() — ok/eq not yet loaded.

-- Case 1: file not found → startup error.
do
  local saved_arg = arg -- luacheck: globals arg
  arg = { "gitea", "webhook_secret_file_gitea=/tmp/no-such-file-fido-test-9x7z.txt" } -- luacheck: globals arg
  local ok1, err1 = pcall(_real_dofile, ".init.lua")
  arg = saved_arg -- luacheck: globals arg
  assert(not ok1, "read_secret_file: missing file should cause startup error")
  assert(
    type(err1) == "string" and err1:find("not found"),
    "read_secret_file: missing file error should mention 'not found' (got: "
      .. tostring(err1)
      .. ")"
  )
end

-- Provider/upstream flag validation happens before module loading, so these
-- pcall checks can exercise startup failures without affecting the main load.
do
  local saved_arg = arg

  arg = { "--provider=notarealprovider", "--upstream=https://git.example.com" } -- luacheck: globals arg
  local ok_provider, err_provider = pcall(_real_dofile, ".init.lua")
  assert(not ok_provider, "--provider: unsupported provider should cause startup error")
  assert(
    type(err_provider) == "string" and err_provider:find("unsupported provider"),
    "--provider: unsupported provider error should mention unsupported provider (got: "
      .. tostring(err_provider)
      .. ")"
  )

  arg = { "--provider=", "--upstream=https://git.example.com" } -- luacheck: globals arg
  local ok_empty_provider, err_empty_provider = pcall(_real_dofile, ".init.lua")
  assert(not ok_empty_provider, "--provider: empty value should cause startup error")
  assert(
    type(err_empty_provider) == "string" and err_empty_provider:find("missing value"),
    "--provider: empty value error should mention missing value (got: "
      .. tostring(err_empty_provider)
      .. ")"
  )

  arg = { "--provider", "--upstream=https://git.example.com" } -- luacheck: globals arg
  local ok_missing_provider_value, err_missing_provider_value = pcall(_real_dofile, ".init.lua")
  assert(
    not ok_missing_provider_value,
    "--provider: missing split value should cause startup error"
  )
  assert(
    type(err_missing_provider_value) == "string"
      and err_missing_provider_value:find("missing value"),
    "--provider: missing split value error should mention missing value (got: "
      .. tostring(err_missing_provider_value)
      .. ")"
  )

  arg = { "--provider=gitea" } -- luacheck: globals arg
  local ok_missing_upstream, err_missing_upstream = pcall(_real_dofile, ".init.lua")
  assert(not ok_missing_upstream, "--provider without --upstream should cause startup error")
  assert(
    type(err_missing_upstream) == "string" and err_missing_upstream:find("%-%-upstream"),
    "--provider without --upstream error should mention --upstream (got: "
      .. tostring(err_missing_upstream)
      .. ")"
  )

  arg = { "--provider=gitea", "--upstream=" } -- luacheck: globals arg
  local ok_empty_upstream, err_empty_upstream = pcall(_real_dofile, ".init.lua")
  assert(not ok_empty_upstream, "--upstream: empty value should cause startup error")
  assert(
    type(err_empty_upstream) == "string" and err_empty_upstream:find("missing value"),
    "--upstream: empty value error should mention missing value (got: "
      .. tostring(err_empty_upstream)
      .. ")"
  )

  arg = { "--webhook-admin=runtime", "--provider=gitea", "--upstream=https://git.example.com" } -- luacheck: globals arg
  local ok_unknown_flag, err_unknown_flag = pcall(_real_dofile, ".init.lua")
  assert(not ok_unknown_flag, "unknown startup flag should cause startup error")
  assert(
    type(err_unknown_flag) == "string" and err_unknown_flag:find("unknown startup flag"),
    "unknown startup flag error should mention unknown startup flag (got: "
      .. tostring(err_unknown_flag)
      .. ")"
  )

  arg = { "--config=/tmp/confusio.toml", "--provider=gitea", "--upstream=https://git.example.com" } -- luacheck: globals arg
  local ok_config_file_flag, err_config_file_flag = pcall(_real_dofile, ".init.lua")
  assert(not ok_config_file_flag, "config file startup flag should cause startup error")
  assert(
    type(err_config_file_flag) == "string" and err_config_file_flag:find("unknown startup flag"),
    "config file startup flag error should mention unknown startup flag (got: "
      .. tostring(err_config_file_flag)
      .. ")"
  )

  arg = { -- luacheck: globals arg
    "--webhook-target-env=CONFUSIO_WEBHOOK_TARGETS",
    "--provider=gitea",
    "--upstream=https://git.example.com",
  }
  local ok_target_env_flag, err_target_env_flag = pcall(_real_dofile, ".init.lua")
  assert(not ok_target_env_flag, "webhook target env startup flag should cause startup error")
  assert(
    type(err_target_env_flag) == "string" and err_target_env_flag:find("unknown startup flag"),
    "webhook target env startup flag error should mention unknown startup flag (got: "
      .. tostring(err_target_env_flag)
      .. ")"
  )

  arg = { -- luacheck: globals arg
    "--webhook-secret-env=CONFUSIO_WEBHOOK_SECRET",
    "--provider=gitea",
    "--upstream=https://git.example.com",
  }
  local ok_secret_env_flag, err_secret_env_flag = pcall(_real_dofile, ".init.lua")
  assert(not ok_secret_env_flag, "webhook secret env startup flag should cause startup error")
  assert(
    type(err_secret_env_flag) == "string" and err_secret_env_flag:find("unknown startup flag"),
    "webhook secret env startup flag error should mention unknown startup flag (got: "
      .. tostring(err_secret_env_flag)
      .. ")"
  )

  arg = { "--provider=gitea", "--upstream=not-a-url" } -- luacheck: globals arg
  local ok_bad_url, err_bad_url = pcall(_real_dofile, ".init.lua")
  assert(not ok_bad_url, "--upstream: invalid URL should cause startup error")
  assert(
    type(err_bad_url) == "string" and err_bad_url:find("invalid upstream URL"),
    "--upstream: invalid URL error should mention invalid upstream URL (got: "
      .. tostring(err_bad_url)
      .. ")"
  )

  arg = { "gitea", "--provider=gitlab", "--upstream=https://git.example.com" } -- luacheck: globals arg
  local ok_conflict, err_conflict = pcall(_real_dofile, ".init.lua")
  assert(not ok_conflict, "--provider: conflicting positional provider should cause startup error")
  assert(
    type(err_conflict) == "string" and err_conflict:find("conflicting"),
    "--provider: conflict error should mention conflicting configuration (got: "
      .. tostring(err_conflict)
      .. ")"
  )

  arg = { "--provider=gitea", "--provider=gitea", "--upstream=https://git.example.com" } -- luacheck: globals arg
  local ok_duplicate, err_duplicate = pcall(_real_dofile, ".init.lua")
  assert(not ok_duplicate, "--provider: duplicate provider flag should cause startup error")
  assert(
    type(err_duplicate) == "string" and err_duplicate:find("conflicting"),
    "--provider: duplicate provider error should mention conflicting configuration (got: "
      .. tostring(err_duplicate)
      .. ")"
  )

  arg = { "--webhook-target=name=only-name" } -- luacheck: globals arg
  local ok_missing_target_url, err_missing_target_url = pcall(_real_dofile, ".init.lua")
  assert(not ok_missing_target_url, "--webhook-target: missing url should cause startup error")
  assert(
    type(err_missing_target_url) == "string" and err_missing_target_url:find("requires url"),
    "--webhook-target: missing url error should mention required url (got: "
      .. tostring(err_missing_target_url)
      .. ")"
  )

  arg = { "--webhook-target=" } -- luacheck: globals arg
  local ok_empty_target_spec, err_empty_target_spec = pcall(_real_dofile, ".init.lua")
  assert(not ok_empty_target_spec, "--webhook-target: empty spec should cause startup error")
  assert(
    type(err_empty_target_spec) == "string" and err_empty_target_spec:find("missing value"),
    "--webhook-target: empty spec error should mention missing value (got: "
      .. tostring(err_empty_target_spec)
      .. ")"
  )

  arg = { "--webhook-target=url=https://hook.example.com/no-name" } -- luacheck: globals arg
  local ok_missing_target_name, err_missing_target_name = pcall(_real_dofile, ".init.lua")
  assert(not ok_missing_target_name, "--webhook-target: missing name should cause startup error")
  assert(
    type(err_missing_target_name) == "string" and err_missing_target_name:find("requires name"),
    "--webhook-target: missing name error should mention required name (got: "
      .. tostring(err_missing_target_name)
      .. ")"
  )

  arg = { "--webhook-target=name=bad,url=not-a-url" } -- luacheck: globals arg
  local ok_bad_target_url, err_bad_target_url = pcall(_real_dofile, ".init.lua")
  assert(not ok_bad_target_url, "--webhook-target: invalid url should cause startup error")
  assert(
    type(err_bad_target_url) == "string" and err_bad_target_url:find("invalid webhook target URL"),
    "--webhook-target: invalid url error should mention invalid target URL (got: "
      .. tostring(err_bad_target_url)
      .. ")"
  )

  arg = { "--webhook-target=name=bad,url=https://hook.example.com,shape=xml" } -- luacheck: globals arg
  local ok_bad_target_shape, err_bad_target_shape = pcall(_real_dofile, ".init.lua")
  assert(not ok_bad_target_shape, "--webhook-target: invalid shape should cause startup error")
  assert(
    type(err_bad_target_shape) == "string"
      and err_bad_target_shape:find("unsupported webhook target shape"),
    "--webhook-target: invalid shape error should mention unsupported shape (got: "
      .. tostring(err_bad_target_shape)
      .. ")"
  )

  arg = { "--webhook-target=name=bad,url=https://hook.example.com,color=blue" } -- luacheck: globals arg
  local ok_unsupported_target_field, err_unsupported_target_field = pcall(_real_dofile, ".init.lua")
  assert(
    not ok_unsupported_target_field,
    "--webhook-target: unsupported field should cause startup error"
  )
  assert(
    type(err_unsupported_target_field) == "string"
      and err_unsupported_target_field:find("unsupported --webhook-target field", 1, true),
    "--webhook-target: unsupported field error should mention unsupported field (got: "
      .. tostring(err_unsupported_target_field)
      .. ")"
  )

  arg = { "--webhook-target=name=bad,url=https://hook.example.com,events=" } -- luacheck: globals arg
  local ok_empty_target_events, err_empty_target_events = pcall(_real_dofile, ".init.lua")
  assert(not ok_empty_target_events, "--webhook-target: empty events should cause startup error")
  assert(
    type(err_empty_target_events) == "string" and err_empty_target_events:find("missing"),
    "--webhook-target: empty events error should mention missing value (got: "
      .. tostring(err_empty_target_events)
      .. ")"
  )

  arg = { "--webhook-target=name=bad,url=https://hook.example.com,events=++" } -- luacheck: globals arg
  local ok_delimiter_only_events, err_delimiter_only_events = pcall(_real_dofile, ".init.lua")
  assert(
    not ok_delimiter_only_events,
    "--webhook-target: delimiter-only events should cause startup error"
  )
  assert(
    type(err_delimiter_only_events) == "string"
      and err_delimiter_only_events:find("events must not be empty"),
    "--webhook-target: delimiter-only events error should mention empty events (got: "
      .. tostring(err_delimiter_only_events)
      .. ")"
  )

  arg = { "--webhook-target=name=bad,url=https://hook.example.com,events=push+not_a_github_event" } -- luacheck: globals arg
  local ok_bad_target_event, err_bad_target_event = pcall(_real_dofile, ".init.lua")
  assert(not ok_bad_target_event, "--webhook-target: invalid event should cause startup error")
  assert(
    type(err_bad_target_event) == "string"
      and err_bad_target_event:find("unsupported webhook target event"),
    "--webhook-target: invalid event error should mention unsupported event (got: "
      .. tostring(err_bad_target_event)
      .. ")"
  )

  arg = { "--webhook-target=name=bad,url" } -- luacheck: globals arg
  local ok_malformed_target, err_malformed_target = pcall(_real_dofile, ".init.lua")
  assert(not ok_malformed_target, "--webhook-target: malformed field should cause startup error")
  assert(
    type(err_malformed_target) == "string" and err_malformed_target:find("malformed"),
    "--webhook-target: malformed field error should mention malformed field (got: "
      .. tostring(err_malformed_target)
      .. ")"
  )

  arg = { "--webhook-target=name=bad,name=bad2,url=https://hook.example.com" } -- luacheck: globals arg
  local ok_duplicate_target_field, err_duplicate_target_field = pcall(_real_dofile, ".init.lua")
  assert(
    not ok_duplicate_target_field,
    "--webhook-target: duplicate field should cause startup error"
  )
  assert(
    type(err_duplicate_target_field) == "string" and err_duplicate_target_field:find("duplicate"),
    "--webhook-target: duplicate field error should mention duplicate field (got: "
      .. tostring(err_duplicate_target_field)
      .. ")"
  )

  arg = { -- luacheck: globals arg
    "--webhook-target=name=one,url=https://hook.example.com/one",
    "--webhook-target=name=one,url=https://hook.example.com/two",
  }
  local ok_duplicate_target_name, err_duplicate_target_name = pcall(_real_dofile, ".init.lua")
  assert(
    not ok_duplicate_target_name,
    "--webhook-target: duplicate names should cause startup error"
  )
  assert(
    type(err_duplicate_target_name) == "string"
      and err_duplicate_target_name:find("duplicate webhook target name"),
    "--webhook-target: duplicate name error should mention duplicate target name (got: "
      .. tostring(err_duplicate_target_name)
      .. ")"
  )

  arg = { -- luacheck: globals arg
    "--webhook-target=name=bad,url=https://hook.example.com,secret_file=/tmp/no-such-target-secret",
  }
  local ok_bad_target_secret, err_bad_target_secret = pcall(_real_dofile, ".init.lua")
  assert(
    not ok_bad_target_secret,
    "--webhook-target: missing secret file should cause startup error"
  )
  assert(
    type(err_bad_target_secret) == "string" and err_bad_target_secret:find("not found"),
    "--webhook-target: missing secret file error should mention not found (got: "
      .. tostring(err_bad_target_secret)
      .. ")"
  )

  arg = { "webhook_target=not-a-url" } -- luacheck: globals arg
  local ok_bad_legacy_target_url, err_bad_legacy_target_url = pcall(_real_dofile, ".init.lua")
  assert(
    not ok_bad_legacy_target_url,
    "legacy webhook_target: invalid url should cause startup error"
  )
  assert(
    type(err_bad_legacy_target_url) == "string"
      and err_bad_legacy_target_url:find("invalid webhook target URL"),
    "legacy webhook_target: invalid url error should mention invalid target URL (got: "
      .. tostring(err_bad_legacy_target_url)
      .. ")"
  )

  arg = { "webhook_target=https://hook.example.com", "webhook_target_shape=xml" } -- luacheck: globals arg
  local ok_bad_legacy_target_shape, err_bad_legacy_target_shape = pcall(_real_dofile, ".init.lua")
  assert(
    not ok_bad_legacy_target_shape,
    "legacy webhook_target_shape: invalid shape should cause startup error"
  )
  assert(
    type(err_bad_legacy_target_shape) == "string"
      and err_bad_legacy_target_shape:find("unsupported webhook target shape"),
    "legacy webhook_target_shape: invalid shape error should mention unsupported shape (got: "
      .. tostring(err_bad_legacy_target_shape)
      .. ")"
  )

  arg = { "webhook_target=https://hook.example.com", "webhook_target_events=" } -- luacheck: globals arg
  local ok_empty_legacy_target_events, err_empty_legacy_target_events =
    pcall(_real_dofile, ".init.lua")
  assert(
    not ok_empty_legacy_target_events,
    "legacy webhook_target_events: empty events should cause startup error"
  )
  assert(
    type(err_empty_legacy_target_events) == "string"
      and err_empty_legacy_target_events:find("events must not be empty"),
    "legacy webhook_target_events: empty events error should mention empty events (got: "
      .. tostring(err_empty_legacy_target_events)
      .. ")"
  )

  arg = { -- luacheck: globals arg
    "--webhook-target=name=legacy,url=https://hook.example.com/new",
    "webhook_target=https://hook.example.com/legacy",
    "webhook_target_name=legacy",
  }
  local ok_legacy_duplicate, err_legacy_duplicate = pcall(_real_dofile, ".init.lua")
  assert(
    not ok_legacy_duplicate,
    "--webhook-target: legacy duplicate name should cause startup error"
  )
  assert(
    type(err_legacy_duplicate) == "string"
      and err_legacy_duplicate:find("duplicate webhook target name"),
    "--webhook-target: legacy duplicate name error should mention duplicate target name (got: "
      .. tostring(err_legacy_duplicate)
      .. ")"
  )

  arg = saved_arg -- luacheck: globals arg
end

-- Case 2: file owned by wrong uid → startup error.  Mock unix.stat to return
-- uid=0 (root) while unix.geteuid() returns 1000, then load with a real 0600 file.
do
  local saved_arg = arg
  local saved_stat = unix.stat -- luacheck: globals unix
  local saved_geteuid = unix.geteuid
  unix.stat = function(_path)
    return {
      uid = function()
        return 0
      end,
      mode = function()
        return 0x8180
      end,
    },
      nil
  end
  unix.geteuid = function()
    return 1000
  end
  local tmpf2 = os.tmpname()
  local fh2 = io.open(tmpf2, "w")
  fh2:write("secret")
  fh2:close()
  os.execute("chmod 600 " .. tmpf2)
  arg = { "gitea", "webhook_secret_file_gitea=" .. tmpf2 } -- luacheck: globals arg
  local ok2, err2 = pcall(_real_dofile, ".init.lua")
  arg = saved_arg -- luacheck: globals arg
  unix.stat = saved_stat
  unix.geteuid = saved_geteuid
  os.remove(tmpf2)
  assert(not ok2, "read_secret_file: uid mismatch should cause startup error")
  assert(
    type(err2) == "string" and err2:find("uid"),
    "read_secret_file: uid mismatch error should mention 'uid' (got: " .. tostring(err2) .. ")"
  )
end

-- Case 3: file has wrong permissions (0644) → startup error.
do
  local saved_arg = arg
  local tmpf3 = os.tmpname()
  local fh3 = io.open(tmpf3, "w")
  fh3:write("secret")
  fh3:close()
  os.execute("chmod 644 " .. tmpf3)
  arg = { "gitea", "webhook_secret_file_gitea=" .. tmpf3 } -- luacheck: globals arg
  local ok3, err3 = pcall(_real_dofile, ".init.lua")
  arg = saved_arg -- luacheck: globals arg
  os.remove(tmpf3)
  assert(not ok3, "read_secret_file: wrong permissions should cause startup error")
  assert(
    type(err3) == "string" and err3:find("0600"),
    "read_secret_file: perm error should mention '0600' (got: " .. tostring(err3) .. ")"
  )
end

-- Create temp secret files (0600) for the main init call.
-- These exercise the success path of read_secret_file.
local _ws_secret_file = os.tmpname()
local _wt_secret_file = os.tmpname()
do
  local f_ws = io.open(_ws_secret_file, "w")
  f_ws:write("ws_coverage_test")
  f_ws:close()
  os.execute("chmod 600 " .. _ws_secret_file)
  local f_wt = io.open(_wt_secret_file, "w")
  f_wt:write("wt-hmac-secret")
  f_wt:close()
  os.execute("chmod 600 " .. _wt_secret_file)
end

-- Provide SCRIPTARGS entries to exercise all CLI parsing paths in .init.lua:
--   --provider / --upstream: provider name and upstream URL
--   webhook_secret_file_BACKEND: path to 0600 file with inbound signing secret
--   webhook_target=URL: outbound delivery target
--   webhook_target_name=wt-coverage: logical outbound target name
--   webhook_target_events=push,pull_request: event filter
--   webhook_target_shape=github: delivery shape
--   webhook_target_secret_file: path to 0600 file with outbound HMAC signing secret
--   repeated --webhook-target: startup-only target specs
arg = { -- luacheck: globals arg
  "--provider",
  "gitea",
  "--upstream=https://git.example.com/api/",
  "webhook_secret_file_gitea=" .. _ws_secret_file,
  "--webhook-target=name=fido,url=https://hook.example.com/fido,shape=github,events=release+workflow_run,secret_file="
    .. _wt_secret_file,
  "--webhook-target",
  "name=auditor,url=https://hook.example.com/audit,shape=confusio,events=workflow_run,secret=inline-audit-secret",
  "webhook_target=https://hook.example.com/wt-coverage",
  "webhook_target_name=wt-coverage",
  "webhook_target_events=push,pull_request",
  "webhook_target_shape=github",
  "webhook_target_secret_file=" .. _wt_secret_file,
}

-- Load the module under test.
_real_dofile(".init.lua")

-- Clean up temp secret files (secrets are now in config, files no longer needed).
os.remove(_ws_secret_file)
os.remove(_wt_secret_file)

assert(config.backend == "gitea", "--provider CLI arg: config.backend should be gitea")
assert(
  config.base_url == "https://git.example.com/api",
  "--upstream CLI arg: trailing slash should be stripped from config.base_url (got: "
    .. tostring(config.base_url)
    .. ")"
)

-- Verify the SCRIPTARGS webhook_secret_file_* arg populated config.webhook_secrets.
assert(
  type(config.webhook_secrets) == "table", -- luacheck: globals config
  "webhook_secret_file_gitea CLI arg: config.webhook_secrets should be a table after load"
)
assert(
  config.webhook_secrets.gitea == "ws_coverage_test",
  "webhook_secret_file_gitea CLI arg: gitea secret mismatch: "
    .. tostring(config.webhook_secrets.gitea)
)

-- Verify the webhook_target CLI arg populated config.webhook_target.
assert(
  type(config.webhook_target) == "table",
  "webhook_target CLI arg: config.webhook_target should be a table after load"
)
assert(
  config.webhook_target.url == "https://hook.example.com/wt-coverage",
  "webhook_target CLI arg: url mismatch: " .. tostring((config.webhook_target or {}).url)
)
assert(
  config.webhook_target.name == "wt-coverage",
  "webhook_target_name CLI arg: name mismatch: " .. tostring((config.webhook_target or {}).name)
)
assert(
  type(config.webhook_target.events) == "table",
  "webhook_target_events CLI arg: events should be a table after load"
)
assert(
  config.webhook_target.events[1] == "push",
  "webhook_target_events CLI arg: events[1] should be push"
)
assert(
  config.webhook_target.events[2] == "pull_request",
  "webhook_target_events CLI arg: events[2] should be pull_request"
)
assert(
  config.webhook_target.secret == "wt-hmac-secret",
  "webhook_target_secret_file CLI arg: secret mismatch: "
    .. tostring((config.webhook_target or {}).secret)
)
assert(
  type(config.webhook_targets) == "table",
  "--webhook-target CLI arg: config.webhook_targets should be a table after load"
)
assert(#config.webhook_targets == 2, "--webhook-target CLI arg: expected two repeated targets")
assert(
  config.webhook_targets[1].name == "fido",
  "--webhook-target CLI arg: first target name mismatch: "
    .. tostring((config.webhook_targets[1] or {}).name)
)
assert(
  config.webhook_targets[1].url == "https://hook.example.com/fido",
  "--webhook-target CLI arg: first target url mismatch: "
    .. tostring((config.webhook_targets[1] or {}).url)
)
assert(
  config.webhook_targets[1].shape == "github",
  "--webhook-target CLI arg: first target shape mismatch: "
    .. tostring((config.webhook_targets[1] or {}).shape)
)
assert(
  config.webhook_targets[1].events[1] == "release"
    and config.webhook_targets[1].events[2] == "workflow_run",
  "--webhook-target CLI arg: first target event filter mismatch"
)
assert(
  config.webhook_targets[1].secret == "wt-hmac-secret",
  "--webhook-target CLI arg: first target secret_file mismatch: "
    .. tostring((config.webhook_targets[1] or {}).secret)
)
assert(
  config.webhook_targets[2].name == "auditor",
  "--webhook-target CLI arg: second target name mismatch: "
    .. tostring((config.webhook_targets[2] or {}).name)
)
assert(
  config.webhook_targets[2].shape == "confusio",
  "--webhook-target CLI arg: second target shape mismatch: "
    .. tostring((config.webhook_targets[2] or {}).shape)
)
assert(
  config.webhook_targets[2].events[1] == "workflow_run",
  "--webhook-target CLI arg: second target event filter mismatch"
)
assert(
  config.webhook_targets[2].secret == "inline-audit-secret",
  "--webhook-target CLI arg: second target inline secret mismatch: "
    .. tostring((config.webhook_targets[2] or {}).secret)
)

-- Clear coverage-only state so later tests see a clean config.
-- (config and app.config reference the same table.)
config.webhook_secrets = {}
config.webhook_target = nil
config.webhook_targets = nil

-- Restore dofile so later tests that call it work normally.
dofile = _real_dofile -- luacheck: globals dofile

-- ============================================================
-- Minimal assertion helpers
-- ============================================================

local PASS, FAIL = 0, 0

local function ok(cond, msg)
  if cond then
    PASS = PASS + 1
    io.write("PASS  " .. msg .. "\n")
  else
    FAIL = FAIL + 1
    io.write("FAIL  " .. msg .. "\n")
  end
end

local function eq(a, b, msg)
  ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

local function read_file(path)
  local f = assert(io.open(path, "r"))
  local body = f:read("*a")
  f:close()
  return body
end

do
  local init_source = read_file(".init.lua")
  ok(
    init_source:find("os.getenv", 1, true) == nil,
    ".init.lua: startup webhook config does not read environment variables"
  )
  ok(
    init_source:find("--config", 1, true) == nil,
    ".init.lua: startup webhook config has no config-file flag"
  )
  local catalog_source = read_file("internal/catalog.lua")
  ok(
    catalog_source:find('"/admin', 1, true) == nil,
    "route catalog: no /admin routes are registered"
  )
end

-- ============================================================
-- set_preamble
-- ============================================================

reset_response()
set_preamble(200)
eq(_last_status, 200, "set_preamble(200): status 200")
eq(
  _last_headers["Content-Type"],
  "application/json; charset=utf-8",
  "set_preamble(200): default content-type"
)

reset_response()
set_preamble(404)
eq(_last_status, 404, "set_preamble(404): status 404")

reset_response()
set_preamble(503)
eq(_last_status, 503, "set_preamble(503): status 503")

reset_response()
set_preamble("text/plain")
eq(_last_status, 200, "set_preamble(str): string arg → status 200")
eq(
  _last_headers["Content-Type"],
  "text/plain",
  "set_preamble(str): string arg → custom content-type"
)

reset_response()
set_preamble(201, "text/html")
eq(_last_status, 201, "set_preamble(201, str): status 201")
eq(_last_headers["Content-Type"], "text/html", "set_preamble(201, str): custom content-type")

-- ============================================================
-- respond_json
-- ============================================================

reset_response()
respond_json(200, { foo = "bar" })
eq(_last_status, 200, "respond_json(200, obj): status 200")
ok(_last_body ~= "", "respond_json(200, obj): non-empty body")
ok(
  _last_body:find('"foo"') ~= nil or _last_body:find("foo") ~= nil,
  "respond_json(200, obj): body contains key"
)

reset_response()
respond_json(404, {})
eq(_last_status, 404, "respond_json(404, {}): status 404")

-- ============================================================
-- rewrite_link_header
-- ============================================================

reset_request({
  headers = { Host = "proxy.example.com", ["X-Forwarded-Proto"] = "https" },
  path = "/repos/owner/repo/issues",
})

local mapping = { per_page = "limit", page = "page" }
local up_link = '<https://gitea.example.com/api/v1/repos/owner/repo/issues?limit=30&page=2>; rel="next"'
  .. ', <https://gitea.example.com/api/v1/repos/owner/repo/issues?limit=30&page=5>; rel="last"'
local result = rewrite_link_header(up_link, mapping)
ok(result ~= nil, "rewrite_link_header: non-nil for valid input")
ok(result:find("proxy.example.com") ~= nil, "rewrite_link_header: rewrites host to confusio host")
ok(result:find("https://") ~= nil, "rewrite_link_header: uses X-Forwarded-Proto scheme")
ok(result:find("per_page=30") ~= nil, "rewrite_link_header: translates limit → per_page")
ok(result:find('rel="next"') ~= nil, "rewrite_link_header: preserves rel=next")
ok(result:find('rel="last"') ~= nil, "rewrite_link_header: preserves rel=last")
ok(result:find("gitea.example.com") == nil, "rewrite_link_header: removes upstream host")

-- nil / empty input
ok(rewrite_link_header(nil, mapping) == nil, "rewrite_link_header(nil): returns nil")
ok(rewrite_link_header("", mapping) == nil, "rewrite_link_header(''): returns nil")

-- Unknown params are dropped
local link_unknown =
  '<https://gitea.example.com/api/v1/repos/owner/repo?limit=10&unknown=foo>; rel="next"'
local result_unknown = rewrite_link_header(link_unknown, mapping)
ok(
  result_unknown == nil or result_unknown:find("unknown") == nil,
  "rewrite_link_header: drops unrecognised params"
)

-- Only-unknown params → entry kept but query string stripped
local link_only_unknown = '<https://gitea.example.com/api/v1/repos?unknown=foo>; rel="next"'
local result_only_unknown = rewrite_link_header(link_only_unknown, mapping)
ok(
  result_only_unknown ~= nil,
  "rewrite_link_header: entry kept even when all params are unrecognised"
)
ok(
  result_only_unknown ~= nil and result_only_unknown:find("unknown") == nil,
  "rewrite_link_header: unrecognised param stripped from kept entry"
)

-- Default proto when X-Forwarded-Proto absent
reset_request({ headers = { Host = "localhost:8080" }, path = "/users" })
local result_http = rewrite_link_header(
  '<https://gitea.example.com/api/v1/users?limit=20&page=1>; rel="next"',
  mapping
)
ok(
  result_http ~= nil and result_http:find("http://localhost:8080") ~= nil,
  "rewrite_link_header: defaults to http when no X-Forwarded-Proto"
)

-- ============================================================
-- append_page_params
-- ============================================================

reset_request({ params = {} })
eq(
  append_page_params("https://example.com/api", mapping),
  "https://example.com/api",
  "append_page_params: no params → unchanged"
)

reset_request({ params = { per_page = "50", page = "3" } })
local url_both = append_page_params("https://example.com/api", mapping)
ok(url_both:find("limit=50") ~= nil, "append_page_params: per_page → limit")
ok(url_both:find("page=3") ~= nil, "append_page_params: page passes through")
ok(url_both:find("^https://example.com/api%?") ~= nil, "append_page_params: appends with ?")

reset_request({ params = { per_page = "25" } })
local url_existing = append_page_params("https://example.com/api?existing=1", mapping)
ok(url_existing:find("&limit=25") ~= nil, "append_page_params: uses & when ? already present")
ok(url_existing:find("existing=1") ~= nil, "append_page_params: preserves existing param")

-- page-only mapping (like Sourcehut)
reset_request({ params = { per_page = "10" } })
local url_limit_only = append_page_params("https://example.com/api", { per_page = "limit" })
ok(url_limit_only:find("limit=10") ~= nil, "append_page_params: limit-only mapping works")
ok(url_limit_only:find("page") == nil, "append_page_params: no page key in limit-only mapping")

-- ============================================================
-- make_fetch_opts
-- ============================================================

reset_request({ headers = {} })
ok(make_fetch_opts("token") == nil, "make_fetch_opts: nil when no Authorization header")

reset_request({ headers = { Authorization = "token mytoken123" } })
local opts_tok = make_fetch_opts("token")
ok(opts_tok ~= nil, "make_fetch_opts(token): non-nil when Authorization present")
eq(
  opts_tok.headers["Authorization"],
  "token mytoken123",
  "make_fetch_opts(token): token scheme passthrough"
)

reset_request({ headers = { Authorization = "Bearer mybearer" } })
local opts_bea = make_fetch_opts("bearer")
eq(opts_bea.headers["Authorization"], "Bearer mybearer", "make_fetch_opts(bearer): bearer scheme")

-- basic-colon: empty username prefix
reset_request({ headers = { Authorization = "token mysecret" } })
local opts_bc = make_fetch_opts("basic-colon")
ok(opts_bc ~= nil, "make_fetch_opts(basic-colon): non-nil")
ok(
  opts_bc.headers["Authorization"]:find("^Basic ") ~= nil,
  "make_fetch_opts(basic-colon): Basic prefix"
)

-- basic: raw base64 of the token
reset_request({ headers = { Authorization = "token user:pass" } })
local opts_basic = make_fetch_opts("basic")
ok(opts_basic ~= nil, "make_fetch_opts(basic): non-nil")
ok(
  opts_basic.headers["Authorization"]:find("^Basic ") ~= nil,
  "make_fetch_opts(basic): Basic prefix"
)

-- ============================================================
-- owner_repo_id
-- ============================================================

eq(owner_repo_id("alice", "myrepo"), "alice%2Fmyrepo", "owner_repo_id: basic case")
eq(owner_repo_id("org", "my-repo"), "org%2Fmy-repo", "owner_repo_id: hyphen in repo name")
eq(owner_repo_id("a", "b"), "a%2Fb", "owner_repo_id: single-char segments")

-- ============================================================
-- translate_repo
-- ============================================================

local fake_repo = {
  id = 42,
  name = "myrepo",
  full_name = "alice/myrepo",
  private = false,
  owner = {
    login = "alice",
    id = 1,
    avatar_url = "https://example.com/alice.png",
    url = "https://example.com/alice",
    html_url = "https://example.com/alice",
    type = "User",
  },
  html_url = "https://example.com/alice/myrepo",
  description = "A repo",
  fork = false,
  url = "https://example.com/alice/myrepo",
  ssh_url = "git@example.com:alice/myrepo.git",
  clone_url = "https://example.com/alice/myrepo.git",
  website = "https://alice.example.com",
  size = 100,
  stars_count = 5,
  watchers_count = 3,
  language = "Lua",
  has_issues = true,
  has_wiki = false,
  forks_count = 2,
  archived = false,
  open_issues_count = 1,
  default_branch = "main",
  visibility = "public",
  created = "2024-01-01T00:00:00Z",
  updated = "2024-06-01T00:00:00Z",
  permissions = { admin = true, push = true, pull = true },
}

local tr = translate_repo(fake_repo)
eq(tr.id, 42, "translate_repo: id")
eq(tr.name, "myrepo", "translate_repo: name")
eq(tr.full_name, "alice/myrepo", "translate_repo: full_name")
eq(tr.node_id, "", "translate_repo: node_id is empty string")
eq(tr.owner.login, "alice", "translate_repo: owner.login")
eq(tr.stargazers_count, 5, "translate_repo: stargazers_count from stars_count")
eq(tr.watchers_count, 3, "translate_repo: watchers_count")
eq(tr.forks_count, 2, "translate_repo: forks_count")
eq(tr.homepage, "https://alice.example.com", "translate_repo: homepage from website")
eq(tr.clone_url, "https://example.com/alice/myrepo.git", "translate_repo: clone_url")
eq(tr.ssh_url, "git@example.com:alice/myrepo.git", "translate_repo: ssh_url")
eq(tr.git_url, "git@example.com:alice/myrepo.git", "translate_repo: git_url from ssh_url")
eq(tr.created_at, "2024-01-01T00:00:00Z", "translate_repo: created_at from created")
eq(tr.updated_at, "2024-06-01T00:00:00Z", "translate_repo: updated_at from updated")
eq(tr.pushed_at, "2024-06-01T00:00:00Z", "translate_repo: pushed_at from updated")
eq(tr.disabled, false, "translate_repo: disabled always false")
eq(tr.visibility, "public", "translate_repo: visibility")

-- visibility derived from private flag when not explicit
local tr_priv =
  translate_repo(setmetatable({ private = true, owner = {} }, { __index = fake_repo }))
eq(tr_priv.visibility, "public", "translate_repo: visibility from repo.visibility takes precedence")
local tr_priv2 = translate_repo({
  id = 1,
  name = "x",
  full_name = "a/x",
  private = true,
  owner = {},
  stars_count = 0,
  watchers_count = 0,
  forks_count = 0,
  open_issues_count = 0,
})
eq(tr_priv2.visibility, "private", "translate_repo: visibility derived from private=true")

ok(type(translate_repo(nil)) == "table", "translate_repo(nil): returns empty table")

-- ============================================================
-- translate_user
-- ============================================================

local fake_user = {
  login = "alice",
  id = 1,
  avatar_url = "https://example.com/alice.png",
  html_url = "https://example.com/alice",
  is_admin = false,
  full_name = "Alice Smith",
  email = "alice@example.com",
  location = "Wonderland",
  website = "https://alice.example.com",
  followers_count = 10,
  following_count = 5,
  created = "2024-01-01T00:00:00Z",
}

local tu = translate_user(fake_user)
eq(tu.login, "alice", "translate_user: login")
eq(tu.id, 1, "translate_user: id")
eq(tu.node_id, "", "translate_user: node_id is empty string")
eq(tu.name, "Alice Smith", "translate_user: name from full_name")
eq(tu.email, "alice@example.com", "translate_user: email")
eq(tu.location, "Wonderland", "translate_user: location")
eq(tu.blog, "https://alice.example.com", "translate_user: blog from website")
eq(tu.followers, 10, "translate_user: followers from followers_count")
eq(tu.following, 5, "translate_user: following from following_count")
eq(tu.type, "User", "translate_user: type always User")
eq(tu.site_admin, false, "translate_user: site_admin from is_admin")
eq(tu.created_at, "2024-01-01T00:00:00Z", "translate_user: created_at from created")

-- is_admin=true
local tu_admin = translate_user(setmetatable({ is_admin = true }, { __index = fake_user }))
eq(tu_admin.site_admin, true, "translate_user: site_admin=true when is_admin=true")

-- missing optional counts default to 0
local tu_minimal = translate_user({ login = "bob", id = 2 })
eq(tu_minimal.followers, 0, "translate_user: followers defaults to 0")
eq(tu_minimal.following, 0, "translate_user: following defaults to 0")

ok(type(translate_user(nil)) == "table", "translate_user(nil): returns empty table")

-- ============================================================
-- translate_migration
-- ============================================================

local fake_migration = {
  id = 7,
  node_id = "MDEy1234",
  owner = { login = "alice" },
  guid = "abc-123",
  state = "exported",
  lock_repositories = true,
  exclude_metadata = true,
  exclude_git_data = false,
  exclude_attachments = false,
  exclude_releases = false,
  exclude_owner_projects = false,
  org_metadata_only = false,
  repositories = { { id = 1 } },
  url = "https://example.com/migrations/7",
  created_at = "2024-01-01T00:00:00Z",
  updated_at = "2024-06-01T00:00:00Z",
  archive_url = "https://example.com/migrations/7/archive.tar.gz",
  exclude = { "repositories" },
}
local tm = translate_migration(fake_migration)
eq(tm.id, 7, "translate_migration: id")
eq(tm.node_id, "MDEy1234", "translate_migration: node_id")
eq(tm.owner.login, "alice", "translate_migration: owner")
eq(tm.guid, "abc-123", "translate_migration: guid")
eq(tm.state, "exported", "translate_migration: state")
eq(tm.lock_repositories, true, "translate_migration: lock_repositories")
eq(tm.exclude_metadata, true, "translate_migration: exclude_metadata")
eq(tm.exclude_git_data, false, "translate_migration: exclude_git_data")
eq(tm.exclude_attachments, false, "translate_migration: exclude_attachments")
eq(tm.exclude_releases, false, "translate_migration: exclude_releases")
eq(tm.exclude_owner_projects, false, "translate_migration: exclude_owner_projects")
eq(tm.org_metadata_only, false, "translate_migration: org_metadata_only")
eq(tm.repositories[1].id, 1, "translate_migration: repositories")
eq(tm.url, "https://example.com/migrations/7", "translate_migration: url")
eq(tm.created_at, "2024-01-01T00:00:00Z", "translate_migration: created_at")
eq(tm.updated_at, "2024-06-01T00:00:00Z", "translate_migration: updated_at")
eq(
  tm.archive_url,
  "https://example.com/migrations/7/archive.tar.gz",
  "translate_migration: archive_url"
)
eq(tm.exclude[1], "repositories", "translate_migration: exclude")

local tm_minimal = translate_migration({ id = 1 })
eq(tm_minimal.node_id, "", "translate_migration: node_id defaults to empty string")
eq(tm_minimal.guid, "", "translate_migration: guid defaults to empty string")
eq(tm_minimal.state, "pending", "translate_migration: state defaults to pending")
eq(tm_minimal.lock_repositories, false, "translate_migration: lock_repositories defaults to false")
eq(tm_minimal.url, "", "translate_migration: url defaults to empty string")

ok(type(translate_migration(nil)) == "table", "translate_migration(nil): returns empty table")

-- ============================================================
-- proxy_json
-- ============================================================

reset_response()
proxy_json(nil, true, 200, {}, '{"foo":"bar"}')
eq(_last_status, 200, "proxy_json: success → 200")
ok(_last_body ~= "", "proxy_json: non-empty body on success")

reset_response()
proxy_json(function(r)
  r.extra = true
  return r
end, true, 200, {}, '{"x":1}')
ok(_last_body:find("extra") ~= nil, "proxy_json: translate fn applied")

reset_response()
proxy_json(nil, true, 404, {}, "{}")
eq(_last_status, 404, "proxy_json: upstream non-200 forwarded")

reset_response()
proxy_json(nil, false, nil, nil, nil)
eq(_last_status, 503, "proxy_json: pcall failure → 503")

-- translate returning nil falls back to empty table
reset_response()
proxy_json(function(_r)
  return nil
end, true, 200, {}, '{"x":1}')
eq(_last_status, 200, "proxy_json: nil translate return → still 200")

-- ============================================================
-- proxy_json_paged
-- ============================================================

reset_request({
  headers = { Host = "proxy.example.com", ["X-Forwarded-Proto"] = "http" },
  path = "/user/repos",
})

reset_response()
local paged_link = '<https://gitea.com/api/v1/repos/search?limit=10&page=2>; rel="next"'
proxy_json_paged(
  nil,
  { per_page = "limit", page = "page" },
  true,
  200,
  { Link = paged_link },
  '[{"id":1}]'
)
eq(_last_status, 200, "proxy_json_paged: success → 200")
ok(_last_headers["Link"] ~= nil, "proxy_json_paged: Link header present")
ok(_last_headers["Link"]:find("proxy.example.com") ~= nil, "proxy_json_paged: Link rewrites host")

reset_response()
proxy_json_paged(nil, { per_page = "limit", page = "page" }, true, 200, {}, '[{"id":1}]')
ok(_last_headers["Link"] == nil, "proxy_json_paged: no Link when upstream has none")

reset_response()
proxy_json_paged(nil, { per_page = "limit", page = "page" }, true, 404, {}, "{}")
eq(_last_status, 404, "proxy_json_paged: upstream non-200 forwarded")

reset_response()
proxy_json_paged(nil, { per_page = "limit", page = "page" }, false, nil, nil, nil)
eq(_last_status, 503, "proxy_json_paged: pcall failure → 503")

reset_response()
proxy_json_paged(function(r)
  return { translated = #r }
end, { per_page = "limit", page = "page" }, true, 200, {}, '[{"id":1},{"id":2}]')
eq(_last_status, 200, "proxy_json_paged: translate fn applied")
ok(_last_body:find("translated") ~= nil, "proxy_json_paged: translated body emitted")

-- ============================================================
-- proxy_json_created
-- ============================================================

reset_response()
proxy_json_created(nil, true, 201, {}, '{"id":99}')
eq(_last_status, 201, "proxy_json_created: upstream 201 → 201")

reset_response()
proxy_json_created(nil, true, 200, {}, '{"id":99}')
eq(_last_status, 201, "proxy_json_created: upstream 200 → 201")

reset_response()
proxy_json_created(nil, true, 404, {}, "{}")
eq(_last_status, 404, "proxy_json_created: upstream 404 forwarded")

reset_response()
proxy_json_created(nil, false, nil, nil, nil)
eq(_last_status, 503, "proxy_json_created: pcall failure → 503")

reset_response()
proxy_json_created(function(r)
  r.created = true
  return r
end, true, 201, {}, '{"id":1}')
eq(_last_status, 201, "proxy_json_created: translate fn applied")
ok(_last_body:find("created") ~= nil, "proxy_json_created: translated body emitted")

-- ============================================================
-- proxy_health_check
-- ============================================================

reset_response()
proxy_health_check(true, 200)
eq(_last_status, 200, "proxy_health_check: upstream 200 → 200")
eq(_last_body, "{}", "proxy_health_check: upstream 200 → empty object body")

reset_response()
proxy_health_check(true, 404)
eq(_last_status, 503, "proxy_health_check: upstream non-200 → 503")

reset_response()
proxy_health_check(true, 503)
eq(_last_status, 503, "proxy_health_check: upstream 503 → 503")

reset_response()
proxy_health_check(false, nil)
eq(_last_status, 503, "proxy_health_check: pcall failure → 503")

-- ============================================================
-- proxy_204
-- ============================================================

-- 204-only (also_ok = nil)
reset_response()
proxy_204(nil, true, 204)
eq(_last_status, 204, "proxy_204: upstream 204 → 204")
eq(_last_body, "", "proxy_204: upstream 204 → no body")

reset_response()
proxy_204(nil, true, 404)
eq(_last_status, 404, "proxy_204: upstream 404 forwarded")

reset_response()
proxy_204(nil, false, nil)
eq(_last_status, 503, "proxy_204: pcall failure → 503")

-- also_ok = {200}
reset_response()
proxy_204({ 200 }, true, 200)
eq(_last_status, 204, "proxy_204({200}): upstream 200 → 204")

reset_response()
proxy_204({ 200 }, true, 204)
eq(_last_status, 204, "proxy_204({200}): upstream 204 → 204")

reset_response()
proxy_204({ 200 }, true, 422)
eq(_last_status, 422, "proxy_204({200}): upstream 422 forwarded")

-- also_ok = {202}
reset_response()
proxy_204({ 202 }, true, 202)
eq(_last_status, 204, "proxy_204({202}): upstream 202 → 204")

-- also_ok = {200, 201}
reset_response()
proxy_204({ 200, 201 }, true, 201)
eq(_last_status, 204, "proxy_204({200,201}): upstream 201 → 204")

reset_response()
proxy_204({ 200, 201 }, true, 204)
eq(_last_status, 204, "proxy_204({200,201}): upstream 204 → 204")

reset_response()
proxy_204({ 200, 201 }, false, nil)
eq(_last_status, 503, "proxy_204({200,201}): pcall failure → 503")

-- ============================================================
-- proxy_json_list
-- ============================================================

local function identity_list(x)
  return x
end

reset_response()
proxy_json_list(identity_list, true, 200, {}, '[{"a":1},{"b":2}]')
eq(_last_status, 200, "proxy_json_list: upstream 200 → 200")
ok(
  _last_body == '[{"a":1},{"b":2}]' or _last_body == '[{"b":2},{"a":1}]',
  "proxy_json_list: non-empty array body"
)

reset_response()
proxy_json_list(identity_list, true, 200, {}, "[]")
eq(_last_status, 200, "proxy_json_list: upstream empty array → 200")
eq(_last_body, "[]", "proxy_json_list: upstream empty array → [] body")

reset_response()
proxy_json_list(identity_list, true, 404, {}, "{}")
eq(_last_status, 404, "proxy_json_list: upstream non-200 forwarded")

reset_response()
proxy_json_list(identity_list, false, nil, nil, nil)
eq(_last_status, 503, "proxy_json_list: pcall failure → 503")

reset_response()
proxy_json_list(function(data)
  local out = {}
  for i, x in ipairs(data) do
    out[i] = { v = (x.v or 0) * 2 }
  end
  return out
end, true, 200, {}, '[{"v":3}]')
eq(_last_status, 200, "proxy_json_list: translate applied")
ok(_last_body:find('"v":6') ~= nil, "proxy_json_list: translate doubles value")

-- ============================================================
-- translate_list
-- ============================================================

local tl = translate_list(function(x)
  return x * 2
end, { 1, 2, 3 })
eq(#tl, 3, "translate_list: length preserved")
eq(tl[1], 2, "translate_list: first element doubled")
eq(tl[3], 6, "translate_list: third element doubled")

local tl_empty = translate_list(function(x)
  return x
end, {})
eq(#tl_empty, 0, "translate_list: empty input → empty output")

local tl_nil = translate_list(function(x)
  return x
end, nil)
eq(#tl_nil, 0, "translate_list: nil input → empty output")

-- ============================================================
-- proxy_search_envelope
-- ============================================================

reset_response()
proxy_search_envelope(function(x)
  return { id = x.id * 10 }
end, nil, true, 200, {}, '[{"id":1},{"id":2}]')
eq(_last_status, 200, "proxy_search_envelope(nil container): 200")
ok(_last_body:find('"total_count":2') ~= nil, "proxy_search_envelope(nil container): total_count")
ok(
  _last_body:find('"incomplete_results":false') ~= nil,
  "proxy_search_envelope: incomplete_results false"
)
ok(_last_body:find('"id":10') ~= nil, "proxy_search_envelope: translate_item applied")

reset_response()
proxy_search_envelope(function(x)
  return { v = x.v }
end, "values", true, 200, {}, '{"values":[{"v":7}],"size":1}')
eq(_last_status, 200, "proxy_search_envelope(string container): 200")
ok(
  _last_body:find('"total_count":1') ~= nil,
  "proxy_search_envelope(string container): total_count 1"
)
ok(_last_body:find('"v":7') ~= nil, "proxy_search_envelope(string container): item translated")

reset_response()
proxy_search_envelope(function(x)
  return x
end, nil, true, 200, {}, "[]")
ok(_last_body:find('"items":%[%]') ~= nil, "proxy_search_envelope: empty array → items:[]")

reset_response()
proxy_search_envelope(function(x)
  return x
end, nil, true, 404, {}, "{}")
eq(_last_status, 404, "proxy_search_envelope: upstream non-200 forwarded")

reset_response()
proxy_search_envelope(function(x)
  return x
end, nil, false, nil, nil, nil)
eq(_last_status, 503, "proxy_search_envelope: pcall failure → 503")

-- ============================================================
-- make_proxy_handler
-- ============================================================

local fetch_log = {}
local function fake_fetch(url)
  fetch_log[#fetch_log + 1] = url
  return true, 200, {}, '{"fetched":true}'
end

local ph = make_proxy_handler(fake_fetch)
reset_response()
local handler = ph(nil, function(owner, repo)
  return "https://example.com/" .. owner .. "/" .. repo
end)
handler("alice", "myrepo")
eq(
  fetch_log[#fetch_log],
  "https://example.com/alice/myrepo",
  "make_proxy_handler: url_fn called with handler args"
)
eq(_last_status, 200, "make_proxy_handler: response proxied")

-- translate fn receives handler args too
fetch_log = {}
reset_response()
local handler2 = ph(function(r, owner, repo)
  r.owner_arg = owner
  r.repo_arg = repo
  return r
end, function(owner, repo)
  return "https://example.com/" .. owner .. "/" .. repo
end)
handler2("bob", "testrepo")
eq(
  fetch_log[#fetch_log],
  "https://example.com/bob/testrepo",
  "make_proxy_handler: url_fn receives args"
)
ok(
  _last_body:find("bob") ~= nil and _last_body:find("testrepo") ~= nil,
  "make_proxy_handler: translate fn receives handler args"
)

-- custom proxy_fn (proxy_json_created)
fetch_log = {}
reset_response()
local fake_fetch_201 = function(_url)
  return true, 201, {}, '{"id":7}'
end
local ph_created = make_proxy_handler(fake_fetch_201, proxy_json_created)
local handler3 = ph_created(nil, function()
  return "https://example.com/repos"
end)
handler3()
eq(_last_status, 201, "make_proxy_handler: custom proxy_fn (proxy_json_created) used")

-- ============================================================
-- make_backend_transport
-- ============================================================

do
  -- Stub Fetch for this section so fetch_json doesn't hit the network.
  -- luacheck: push
  -- luacheck: globals Fetch
  local captured_url, captured_opts, stub_ok, stub_status, stub_headers, stub_body

  local function set_fetch_stub(stub_ok_arg, status, headers, body)
    stub_ok = stub_ok_arg
    stub_status = status
    stub_headers = headers
    stub_body = body
    Fetch = function(url, opts)
      captured_url = url
      captured_opts = opts
      if stub_ok then
        return stub_status, stub_headers, stub_body
      else
        error("network error")
      end
    end
  end
  -- luacheck: pop

  -- Returns the four sub-fields.
  local t_tok = make_backend_transport("token", { per_page = "limit", page = "page" })
  ok(type(t_tok.fetch_json) == "function", "make_backend_transport: fetch_json is a function")
  ok(type(t_tok.proxy_handler) == "function", "make_backend_transport: proxy_handler is a function")
  ok(
    type(t_tok.proxy_handler_created) == "function",
    "make_backend_transport: proxy_handler_created is a function"
  )
  ok(
    type(t_tok.proxy_handler_paged) == "function",
    "make_backend_transport: proxy_handler_paged is a function when pages supplied"
  )

  -- Without pages, proxy_handler_paged is nil.
  local t_nopages = make_backend_transport("bearer")
  ok(
    t_nopages.proxy_handler_paged == nil,
    "make_backend_transport: proxy_handler_paged is nil when pages omitted"
  )

  -- fetch_json GET: no method or body modifications.
  reset_request({ headers = { Authorization = "token mytoken" } })
  set_fetch_stub(true, 200, {}, '{"ok":true}')
  captured_url, captured_opts = nil, nil
  local ok2, status2 = t_tok.fetch_json("https://example.com/api/repos")
  ok(ok2, "make_backend_transport fetch_json GET: pcall ok")
  eq(status2, 200, "make_backend_transport fetch_json GET: status 200")
  eq(
    captured_url,
    "https://example.com/api/repos",
    "make_backend_transport fetch_json GET: url forwarded"
  )
  ok(
    captured_opts == nil or captured_opts.method == nil,
    "make_backend_transport fetch_json GET: no method override"
  )
  ok(
    captured_opts == nil
      or captured_opts.headers == nil
      or captured_opts.headers["Content-Type"] == nil,
    "make_backend_transport fetch_json GET: no Content-Type"
  )

  -- fetch_json POST with body: sets method and Content-Type.
  reset_request({ headers = { Authorization = "token mytoken" } })
  set_fetch_stub(true, 201, {}, '{"id":1}')
  captured_opts = nil
  t_tok.fetch_json("https://example.com/api/repos", "POST", '{"name":"foo"}')
  eq(
    captured_opts and captured_opts.method,
    "POST",
    "make_backend_transport fetch_json POST: method set"
  )
  eq(
    captured_opts and captured_opts.body,
    '{"name":"foo"}',
    "make_backend_transport fetch_json POST: body set"
  )
  eq(
    captured_opts and captured_opts.headers and captured_opts.headers["Content-Type"],
    "application/json",
    "make_backend_transport fetch_json POST: Content-Type set"
  )

  -- fetch_json POST without body: method set, no Content-Type.
  reset_request({ headers = { Authorization = "token mytoken" } })
  set_fetch_stub(true, 204, {}, "")
  captured_opts = nil
  t_tok.fetch_json("https://example.com/api/repos", "DELETE")
  eq(
    captured_opts and captured_opts.method,
    "DELETE",
    "make_backend_transport fetch_json DELETE: method set"
  )
  ok(
    captured_opts == nil
      or captured_opts.headers == nil
      or captured_opts.headers["Content-Type"] == nil,
    "make_backend_transport fetch_json DELETE: no Content-Type without body"
  )

  -- fetch_json: auth header forwarded under the requested scheme.
  reset_request({ headers = { Authorization = "token mytoken" } })
  set_fetch_stub(true, 200, {}, "{}")
  captured_opts = nil
  t_tok.fetch_json("https://example.com/api")
  ok(
    captured_opts ~= nil and captured_opts.headers["Authorization"] == "token mytoken",
    "make_backend_transport fetch_json: token auth scheme forwarded"
  )

  reset_request({ headers = { Authorization = "token mybearer" } })
  local t_bearer = make_backend_transport("bearer")
  set_fetch_stub(true, 200, {}, "{}")
  captured_opts = nil
  t_bearer.fetch_json("https://example.com/api")
  ok(
    captured_opts ~= nil and captured_opts.headers["Authorization"] == "Bearer mybearer",
    "make_backend_transport fetch_json: bearer auth scheme forwarded"
  )

  -- fetch_json with no Authorization: opts nil, no header sent.
  reset_request({ headers = {} })
  set_fetch_stub(true, 200, {}, "{}")
  captured_opts = "sentinel"
  t_tok.fetch_json("https://example.com/api")
  ok(captured_opts == nil, "make_backend_transport fetch_json: nil opts when no Authorization")

  -- proxy_handler_paged uses the correct pages mapping.
  reset_request({
    headers = { Host = "proxy.example.com", ["X-Forwarded-Proto"] = "http" },
    path = "/user/repos",
    params = {},
  })
  set_fetch_stub(
    true,
    200,
    { Link = '<https://upstream.example.com/api/repos?limit=10&page=2>; rel="next"' },
    '[{"id":1}]'
  )
  reset_response()
  local paged_h = t_tok.proxy_handler_paged(nil, function()
    return "https://upstream.example.com/api/repos?limit=10"
  end)
  paged_h()
  eq(_last_status, 200, "make_backend_transport proxy_handler_paged: 200 on success")
  ok(
    _last_headers["Link"] ~= nil,
    "make_backend_transport proxy_handler_paged: Link header rewritten"
  )
  ok(
    _last_headers["Link"]:find("per_page=10") ~= nil,
    "make_backend_transport proxy_handler_paged: limit translated to per_page"
  )
end

-- ============================================================
-- OnHttpRequest
-- ============================================================

-- GET / with no backend → default handler returns {}
reset_response()
reset_request({ method = "GET", path = "/" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET / → 200")

-- DELETE /rate_limit — known path, wrong method → 405
reset_response()
reset_request({ method = "DELETE", path = "/rate_limit" })
OnHttpRequest()
eq(_last_status, 405, "OnHttpRequest: wrong method on known path → 405")

-- GET /nonexistent — unknown path → 404
reset_response()
reset_request({ method = "GET", path = "/nonexistent/path/that/does/not/exist" })
OnHttpRequest()
eq(_last_status, 404, "OnHttpRequest: unknown path → 404")

-- Webhook configuration is startup-only.  There is no admin API, runtime target
-- registry, outbox, replay, or Confusio delivery inspection surface.
reset_response()
reset_request({ method = "POST", path = "/admin/webhook-targets" })
OnHttpRequest()
eq(_last_status, 404, "OnHttpRequest: POST /admin/webhook-targets → 404")

reset_response()
reset_request({ method = "GET", path = "/admin/webhook-deliveries" })
OnHttpRequest()
eq(_last_status, 404, "OnHttpRequest: GET /admin/webhook-deliveries → 404")

reset_response()
reset_request({ method = "POST", path = "/webhook-targets" })
OnHttpRequest()
eq(_last_status, 404, "OnHttpRequest: POST /webhook-targets → 404")

reset_response()
reset_request({ method = "GET", path = "/deliveries" })
OnHttpRequest()
eq(_last_status, 404, "OnHttpRequest: GET /deliveries → 404")

reset_response()
reset_request({ method = "GET", path = "/outbox" })
OnHttpRequest()
eq(_last_status, 404, "OnHttpRequest: GET /outbox → 404")

reset_response()
reset_request({ method = "POST", path = "/replay" })
OnHttpRequest()
eq(_last_status, 404, "OnHttpRequest: POST /replay → 404")

-- GitHub-compatible hook delivery endpoints expose no Confusio delivery state:
-- lists are empty, individual delivery records are absent, and redelivery is
-- deliberately not implemented.
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/hooks" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /repos/{owner}/{repo}/hooks → 200")
eq(_last_body, "[]", "OnHttpRequest: GET /repos/{owner}/{repo}/hooks → body is []")

reset_response()
reset_request({ method = "POST", path = "/repos/alice/myrepo/hooks" })
OnHttpRequest()
eq(_last_status, 501, "OnHttpRequest: POST /repos/{owner}/{repo}/hooks → 501")

reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/hooks/1/deliveries" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /repos/{owner}/{repo}/hooks/{hook_id}/deliveries → 200")
eq(
  _last_body,
  "[]",
  "OnHttpRequest: GET /repos/{owner}/{repo}/hooks/{hook_id}/deliveries → body is []"
)

reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/hooks/1/deliveries/abc" })
OnHttpRequest()
eq(
  _last_status,
  404,
  "OnHttpRequest: GET /repos/{owner}/{repo}/hooks/{hook_id}/deliveries/{delivery_id} → 404"
)

reset_response()
reset_request({
  method = "POST",
  path = "/repos/alice/myrepo/hooks/1/deliveries/abc/attempts",
})
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: POST /repos/{owner}/{repo}/hooks/{hook_id}/deliveries/{delivery_id}/attempts → 501"
)

reset_response()
reset_request({ method = "GET", path = "/app/hook/deliveries" })
OnHttpRequest()
eq(_last_status, 404, "OnHttpRequest: GET /app/hook/deliveries → 404")

reset_response()
reset_request({ method = "POST", path = "/app/hook/deliveries/abc/attempts" })
OnHttpRequest()
eq(_last_status, 404, "OnHttpRequest: POST /app/hook/deliveries/{delivery_id}/attempts → 404")

-- GET /zen — built-in, no backend needed
reset_response()
reset_request({ method = "GET", path = "/zen" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /zen → 200")

-- GET /meta — built-in
reset_response()
reset_request({ method = "GET", path = "/meta" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /meta → 200")

-- GET /teapot — 418
reset_response()
reset_request({ method = "GET", path = "/teapot" })
OnHttpRequest()
eq(_last_status, 418, "OnHttpRequest: GET /teapot → 418")

-- GET /rate_limit — default handler
reset_response()
reset_request({ method = "GET", path = "/rate_limit" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /rate_limit → 200")

-- GET /octocat — built-in, no backend needed
reset_response()
reset_request({ method = "GET", path = "/octocat" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /octocat → 200")

-- GET /versions — built-in
reset_response()
reset_request({ method = "GET", path = "/versions" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /versions → 200")

-- GET /issues — default empty_list fallback
reset_response()
reset_request({ method = "GET", path = "/issues" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /issues → 200 (empty_list default)")

-- GET /search/code — default search_empty fallback
reset_response()
reset_request({ method = "GET", path = "/search/code" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /search/code → 200 (search_empty default)")

-- GET /user/interaction-limits — default interaction_limits_empty
reset_response()
reset_request({ method = "GET", path = "/user/interaction-limits" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /user/interaction-limits → 200")
eq(_last_body, "{}", "OnHttpRequest: GET /user/interaction-limits → empty object body")

-- PUT /user/interaction-limits — default interaction_limits_put echoes body
reset_response()
reset_request({
  method = "PUT",
  path = "/user/interaction-limits",
  body = '{"limit":"collaborators_only","expiry":"one_day"}',
})
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: PUT /user/interaction-limits → 200")
ok(
  _last_body:find("collaborators_only") ~= nil,
  "OnHttpRequest: PUT /user/interaction-limits → echoes body"
)

-- DELETE /user/interaction-limits — default interaction_limits_delete returns 204
reset_response()
reset_request({ method = "DELETE", path = "/user/interaction-limits" })
OnHttpRequest()
eq(_last_status, 204, "OnHttpRequest: DELETE /user/interaction-limits → 204")

-- GET /repos/{owner}/{repo} — no backend → 404 (no default_fn)
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo" })
OnHttpRequest()
eq(_last_status, 404, "OnHttpRequest: backend endpoint without default → 404")

-- app.allow_anonymous=false, no Authorization → 401
reset_response()
reset_request({ method = "GET", path = "/" })
app.allow_anonymous = false
OnHttpRequest()
eq(_last_status, 401, "OnHttpRequest: anon forbidden when app.allow_anonymous=false → 401")
app.allow_anonymous = true

-- app.allow_anonymous=false, with Authorization → proceeds normally
reset_response()
reset_request({ method = "GET", path = "/", headers = { Authorization = "token mytoken" } })
app.allow_anonymous = false
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: authorized request allowed when app.allow_anonymous=false → 200"
)
app.allow_anonymous = true

-- GET /orgs/{org}/code-scanning/alerts — code_scanning_list_empty default → 200
reset_response()
reset_request({ method = "GET", path = "/orgs/myorg/code-scanning/alerts" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /orgs/{org}/code-scanning/alerts → 200 (empty list)")

-- GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number} — code_scanning_not_implemented default → 501
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/code-scanning/alerts/1" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number} → 501 (not implemented)"
)

-- POST /orgs/{org}/migrations — migrations_not_supported default → 501
reset_response()
reset_request({ method = "POST", path = "/orgs/myorg/migrations" })
OnHttpRequest()
eq(_last_status, 501, "OnHttpRequest: POST /orgs/{org}/migrations → 501 (not supported)")

-- POST /user/migrations — migrations_not_supported default → 501
reset_response()
reset_request({ method = "POST", path = "/user/migrations" })
OnHttpRequest()
eq(_last_status, 501, "OnHttpRequest: POST /user/migrations → 501 (not supported)")

-- GET /orgs/{org}/migrations/{migration_id} — migration_not_found default → 404
reset_response()
reset_request({ method = "GET", path = "/orgs/myorg/migrations/7" })
OnHttpRequest()
eq(
  _last_status,
  404,
  "OnHttpRequest: GET /orgs/{org}/migrations/{migration_id} → 404 (not found)"
)

-- GET /repos/{owner}/{repo}/import — source_import_gone default → 410
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/import" })
OnHttpRequest()
eq(_last_status, 410, "OnHttpRequest: GET /repos/{owner}/{repo}/import → 410 (deprecated)")

-- GET /repos/{owner}/{repo}/pages — pages_not_implemented default → 501
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/pages" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: GET /repos/{owner}/{repo}/pages → 501 (pages not implemented)"
)

-- POST /markdown — markdown_not_implemented default → 501
reset_response()
reset_request({ method = "POST", path = "/markdown" })
OnHttpRequest()
eq(_last_status, 501, "OnHttpRequest: POST /markdown → 501 (markdown not implemented)")

-- POST /markdown/raw — markdown_not_implemented default → 501
reset_response()
reset_request({ method = "POST", path = "/markdown/raw" })
OnHttpRequest()
eq(_last_status, 501, "OnHttpRequest: POST /markdown/raw → 501 (markdown not implemented)")

-- Actions default handlers — each function must be hit at least once.

-- actions_not_implemented: GET /enterprises/{enterprise}/actions/cache/retention-limit → 501
reset_response()
reset_request({ method = "GET", path = "/enterprises/myenterprise/actions/cache/retention-limit" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: GET /enterprises/{enterprise}/actions/cache/retention-limit → 501 (actions not implemented)"
)

-- actions_runs_empty: GET /repos/{owner}/{repo}/actions/runs → 200 with workflow_runs list
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/actions/runs" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /repos/{owner}/{repo}/actions/runs → 200 (runs empty)")
ok(
  _last_body:find("workflow_runs") ~= nil,
  "OnHttpRequest: GET /repos/{owner}/{repo}/actions/runs → body contains workflow_runs"
)

-- actions_artifacts_empty: GET /repos/{owner}/{repo}/actions/artifacts → 200 with artifacts list
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/actions/artifacts" })
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: GET /repos/{owner}/{repo}/actions/artifacts → 200 (artifacts empty)"
)
ok(
  _last_body:find("artifacts") ~= nil,
  "OnHttpRequest: GET /repos/{owner}/{repo}/actions/artifacts → body contains artifacts"
)

-- actions_jobs_empty: GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs → 200 with jobs list
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/actions/runs/42/jobs" })
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs → 200 (jobs empty)"
)
ok(
  _last_body:find('"jobs"') ~= nil,
  "OnHttpRequest: GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs → body contains jobs"
)

-- actions_runners_empty: GET /orgs/{org}/actions/hosted-runners → 200 with runners list
reset_response()
reset_request({ method = "GET", path = "/orgs/myorg/actions/hosted-runners" })
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: GET /orgs/{org}/actions/hosted-runners → 200 (runners empty)"
)
ok(
  _last_body:find("runners") ~= nil,
  "OnHttpRequest: GET /orgs/{org}/actions/hosted-runners → body contains runners"
)

-- actions_runner_groups_empty: GET /orgs/{org}/actions/runner-groups → 200 with runner_groups list
reset_response()
reset_request({ method = "GET", path = "/orgs/myorg/actions/runner-groups" })
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: GET /orgs/{org}/actions/runner-groups → 200 (runner groups empty)"
)
ok(
  _last_body:find("runner_groups") ~= nil,
  "OnHttpRequest: GET /orgs/{org}/actions/runner-groups → body contains runner_groups"
)

-- actions_secrets_empty: GET /orgs/{org}/actions/secrets → 200 with secrets list
reset_response()
reset_request({ method = "GET", path = "/orgs/myorg/actions/secrets" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /orgs/{org}/actions/secrets → 200 (secrets empty)")
ok(
  _last_body:find("secrets") ~= nil,
  "OnHttpRequest: GET /orgs/{org}/actions/secrets → body contains secrets"
)

-- actions_variables_empty: GET /orgs/{org}/actions/variables → 200 with variables list
reset_response()
reset_request({ method = "GET", path = "/orgs/myorg/actions/variables" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /orgs/{org}/actions/variables → 200 (variables empty)")
ok(
  _last_body:find("variables") ~= nil,
  "OnHttpRequest: GET /orgs/{org}/actions/variables → body contains variables"
)

-- actions_caches_empty: GET /repos/{owner}/{repo}/actions/caches → 200 with actions_caches list
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/actions/caches" })
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: GET /repos/{owner}/{repo}/actions/caches → 200 (caches empty)"
)
ok(
  _last_body:find("actions_caches") ~= nil,
  "OnHttpRequest: GET /repos/{owner}/{repo}/actions/caches → body contains actions_caches"
)

-- actions_workflows_empty: GET /repos/{owner}/{repo}/actions/workflows → 200 with workflows list
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/actions/workflows" })
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: GET /repos/{owner}/{repo}/actions/workflows → 200 (workflows empty)"
)
ok(
  _last_body:find("workflows") ~= nil,
  "OnHttpRequest: GET /repos/{owner}/{repo}/actions/workflows → body contains workflows"
)

-- licenses_not_implemented: GET /licenses → 501
reset_response()
reset_request({ method = "GET", path = "/licenses" })
OnHttpRequest()
eq(_last_status, 501, "OnHttpRequest: GET /licenses → 501 (licenses not implemented)")

-- licenses_not_implemented: GET /licenses/{license} → 501
reset_response()
reset_request({ method = "GET", path = "/licenses/mit" })
OnHttpRequest()
eq(_last_status, 501, "OnHttpRequest: GET /licenses/{license} → 501 (licenses not implemented)")

-- licenses_not_implemented: GET /repos/{owner}/{repo}/license → 501
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/license" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: GET /repos/{owner}/{repo}/license → 501 (licenses not implemented)"
)

-- dependency_graph_not_implemented: GET /repos/{owner}/{repo}/dependency-graph/compare/{basehead} → 501
reset_response()
reset_request({
  method = "GET",
  path = "/repos/alice/myrepo/dependency-graph/compare/main...feature",
})
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: GET /repos/{owner}/{repo}/dependency-graph/compare/{basehead} → 501 (dependency graph not implemented)"
)

-- dependency_graph_not_implemented: GET /repos/{owner}/{repo}/dependency-graph/sbom → 501
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/dependency-graph/sbom" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: GET /repos/{owner}/{repo}/dependency-graph/sbom → 501 (dependency graph not implemented)"
)

-- dependency_graph_not_implemented: POST /repos/{owner}/{repo}/dependency-graph/snapshots → 501
reset_response()
reset_request({ method = "POST", path = "/repos/alice/myrepo/dependency-graph/snapshots" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: POST /repos/{owner}/{repo}/dependency-graph/snapshots → 501 (dependency graph not implemented)"
)

-- git_not_implemented: any git database route → 501
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/git/blobs/abc123" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: GET /repos/{owner}/{repo}/git/blobs/{file_sha} → 501 (git database not implemented)"
)

-- greedy param trie walk: route with {ref+} matches multi-segment ref
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/git/ref/heads/main" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: GET /repos/{owner}/{repo}/git/ref/{ref+} with multi-segment ref → 501"
)

-- checks_post_check_runs: POST /repos/{owner}/{repo}/check-runs → 201 with id/head_sha/name/status/output
reset_response()
reset_request({
  method = "POST",
  path = "/repos/alice/myrepo/check-runs",
  body = '{"head_sha":"abc123","name":"my-check","status":"in_progress"}',
})
OnHttpRequest()
eq(_last_status, 201, "OnHttpRequest: POST /repos/{owner}/{repo}/check-runs → 201")
ok(
  _last_body:find('"head_sha"') ~= nil,
  "OnHttpRequest: POST /repos/{owner}/{repo}/check-runs → body has head_sha"
)
ok(
  _last_body:find('"output"') ~= nil,
  "OnHttpRequest: POST /repos/{owner}/{repo}/check-runs → body has output"
)

-- checks_get_check_run: GET /repos/{owner}/{repo}/check-runs/{check_run_id} → 200
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/check-runs/42" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /repos/{owner}/{repo}/check-runs/{check_run_id} → 200")
ok(
  _last_body:find('"id"') ~= nil,
  "OnHttpRequest: GET /repos/{owner}/{repo}/check-runs/{check_run_id} → body has id"
)

-- checks_patch_check_run: PATCH /repos/{owner}/{repo}/check-runs/{check_run_id} → 200
reset_response()
reset_request({ method = "PATCH", path = "/repos/alice/myrepo/check-runs/42" })
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: PATCH /repos/{owner}/{repo}/check-runs/{check_run_id} → 200"
)

-- checks_get_check_run_annotations: GET /repos/{owner}/{repo}/check-runs/{check_run_id}/annotations → 200 []
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/check-runs/42/annotations" })
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: GET /repos/{owner}/{repo}/check-runs/{check_run_id}/annotations → 200"
)
eq(
  _last_body,
  "[]",
  "OnHttpRequest: GET /repos/{owner}/{repo}/check-runs/{check_run_id}/annotations → body is []"
)

-- checks_post_check_run_rerequest: POST /repos/{owner}/{repo}/check-runs/{check_run_id}/rerequest → 201
reset_response()
reset_request({ method = "POST", path = "/repos/alice/myrepo/check-runs/42/rerequest" })
OnHttpRequest()
eq(
  _last_status,
  201,
  "OnHttpRequest: POST /repos/{owner}/{repo}/check-runs/{check_run_id}/rerequest → 201"
)

-- checks_get_commit_check_runs: GET /repos/{owner}/{repo}/commits/{ref}/check-runs → 200 empty
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/commits/abc123/check-runs" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /repos/{owner}/{repo}/commits/{ref}/check-runs → 200")
ok(
  _last_body:find('"check_runs"') ~= nil,
  "OnHttpRequest: GET /repos/{owner}/{repo}/commits/{ref}/check-runs → body has check_runs"
)

-- checks_post_check_suites: POST /repos/{owner}/{repo}/check-suites → 201
reset_response()
reset_request({
  method = "POST",
  path = "/repos/alice/myrepo/check-suites",
  body = '{"head_sha":"abc123"}',
})
OnHttpRequest()
eq(_last_status, 201, "OnHttpRequest: POST /repos/{owner}/{repo}/check-suites → 201")
ok(
  _last_body:find('"head_sha"') ~= nil,
  "OnHttpRequest: POST /repos/{owner}/{repo}/check-suites → body has head_sha"
)

-- checks_patch_check_suites_preferences: PATCH /repos/{owner}/{repo}/check-suites/preferences → 200
reset_response()
reset_request({
  method = "PATCH",
  path = "/repos/alice/myrepo/check-suites/preferences",
  body = "{}",
})
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: PATCH /repos/{owner}/{repo}/check-suites/preferences → 200")
ok(
  _last_body:find('"preferences"') ~= nil,
  "OnHttpRequest: PATCH /repos/{owner}/{repo}/check-suites/preferences → body has preferences"
)

-- checks_get_check_suite: GET /repos/{owner}/{repo}/check-suites/{check_suite_id} → 200
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/check-suites/7" })
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: GET /repos/{owner}/{repo}/check-suites/{check_suite_id} → 200"
)
ok(
  _last_body:find('"repository"') ~= nil,
  "OnHttpRequest: GET /repos/{owner}/{repo}/check-suites/{check_suite_id} → body has repository"
)

-- checks_get_check_suite_check_runs: GET /repos/{owner}/{repo}/check-suites/{check_suite_id}/check-runs → 200 empty
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/check-suites/7/check-runs" })
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: GET /repos/{owner}/{repo}/check-suites/{check_suite_id}/check-runs → 200"
)
ok(
  _last_body:find('"check_runs"') ~= nil,
  "OnHttpRequest: GET /repos/{owner}/{repo}/check-suites/{check_suite_id}/check-runs → body has check_runs"
)

-- checks_post_check_suite_rerequest: POST /repos/{owner}/{repo}/check-suites/{check_suite_id}/rerequest → 201
reset_response()
reset_request({ method = "POST", path = "/repos/alice/myrepo/check-suites/7/rerequest" })
OnHttpRequest()
eq(
  _last_status,
  201,
  "OnHttpRequest: POST /repos/{owner}/{repo}/check-suites/{check_suite_id}/rerequest → 201"
)

-- checks_get_commit_check_suites: GET /repos/{owner}/{repo}/commits/{ref}/check-suites → 200 empty
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/commits/abc123/check-suites" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /repos/{owner}/{repo}/commits/{ref}/check-suites → 200")
ok(
  _last_body:find('"check_suites"') ~= nil,
  "OnHttpRequest: GET /repos/{owner}/{repo}/commits/{ref}/check-suites → body has check_suites"
)

-- GET /orgs/{org}/dependabot/alerts — dependabot_list_empty default → 200
reset_response()
reset_request({ method = "GET", path = "/orgs/myorg/dependabot/alerts" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /orgs/{org}/dependabot/alerts → 200 (empty list)")

-- GET /repos/{owner}/{repo}/dependabot/alerts/{alert_number} — dependabot_not_implemented default → 501
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/dependabot/alerts/1" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: GET /repos/{owner}/{repo}/dependabot/alerts/{alert_number} → 501 (dependabot not implemented)"
)

-- GET /orgs/{org}/projectsV2 — projects_list_empty default → 200
reset_response()
reset_request({ method = "GET", path = "/orgs/myorg/projectsV2" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /orgs/{org}/projectsV2 → 200 (empty list)")

-- GET /orgs/{org}/projectsV2/{project_number} — projects_not_implemented default → 501
reset_response()
reset_request({ method = "GET", path = "/orgs/myorg/projectsV2/1" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: GET /orgs/{org}/projectsV2/{project_number} → 501 (projects not implemented)"
)

-- GET /orgs/{org}/secret-scanning/alerts — secret_scanning_list_empty default → 200
reset_response()
reset_request({ method = "GET", path = "/orgs/myorg/secret-scanning/alerts" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /orgs/{org}/secret-scanning/alerts → 200 (empty list)")

-- GET /repos/{owner}/{repo}/secret-scanning/alerts/{alert_number} — secret_scanning_not_implemented default → 501
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/secret-scanning/alerts/1" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: GET /repos/{owner}/{repo}/secret-scanning/alerts/{alert_number} → 501 (not implemented)"
)

-- POST /gists — gists_not_implemented default → 501
reset_response()
reset_request({ method = "POST", path = "/gists" })
OnHttpRequest()
eq(_last_status, 501, "OnHttpRequest: POST /gists → 501 (gists not supported)")

-- POST /repos/{owner}/{repo}/issues/{issue_number}/reactions — reactions_not_implemented default → 501
reset_response()
reset_request({ method = "POST", path = "/repos/alice/myrepo/issues/1/reactions" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: POST /repos/{owner}/{repo}/issues/{issue_number}/reactions → 501 (reactions not supported)"
)

-- GET /events — activity_list_empty default → 200 []
reset_response()
reset_request({ method = "GET", path = "/events" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /events → 200 (activity list empty)")
eq(_last_body, "[]", "OnHttpRequest: GET /events → body is []")

-- GET /feeds — activity_not_implemented default → 501
reset_response()
reset_request({ method = "GET", path = "/feeds" })
OnHttpRequest()
eq(_last_status, 501, "OnHttpRequest: GET /feeds → 501 (activity not implemented)")

-- ============================================================
-- b:build() strip patterns (alias feature gaps)
-- ============================================================

do
  local _saved_rest = app.backend.rest

  -- b:build(strip) with explicit strip patterns excludes matching REST keys.
  app.backend.rest = {}
  local bt = make_backend_builder()
  bt:rest("get_package_info", function() end)
  bt:rest("list_actions_runs", function() end)
  bt:rest("get_repo", function() end)
  bt:build({ "_package", "_actions_" })
  ok(app.backend.rest["get_package_info"] == nil, "b:build(strip): strips _package keys")
  ok(app.backend.rest["list_actions_runs"] == nil, "b:build(strip): strips _actions_ keys")
  ok(app.backend.rest["get_repo"] ~= nil, "b:build(strip): preserves non-matching keys")

  -- b:build() without strip registers all REST keys.
  app.backend.rest = {}
  local bt2 = make_backend_builder()
  bt2:rest("get_package_info", function() end)
  bt2:rest("get_repo", function() end)
  bt2:build()
  ok(
    app.backend.rest["get_package_info"] ~= nil,
    "b:build(): without strip, all keys are registered"
  )

  app.backend.rest = _saved_rest
end

-- ============================================================
-- app context
-- ============================================================

ok(type(app) == "table", "app: is a table")
ok(app.config == config, "app.config: same object as global config")
ok(type(app.backend) == "table", "app.backend: is a table")
ok(type(app.backend.rest) == "table", "app.backend.rest: is a table")
ok(type(app.backend.graphql) == "table", "app.backend.graphql: is a table")
ok(type(app.backend.capabilities) == "table", "app.backend.capabilities: is a table")
ok(type(app.backend.webhooks) == "table", "app.backend.webhooks: is a table")
ok(type(app.backend.webhook_translators) == "table", "app.backend.webhook_translators: is a table")
ok(
  type(app.backend.webhook_github_translators) == "table",
  "app.backend.webhook_github_translators: is a table"
)
ok(type(app.allow_anonymous) == "boolean", "app.allow_anonymous: is a boolean")
ok(app.allow_anonymous == true, "app.allow_anonymous: default true (no backend loaded)")
ok(type(app.route_match) == "function", "app.route_match: bound router lookup installed on app")
ok(
  type(app.path_known) == "function",
  "app.path_known: bound path-existence check installed on app"
)

-- make_app: constructs independent context from a given config table.
do
  local test_cfg = { backend = "test", base_url = "https://test.example.com" }
  local test_app = make_app(test_cfg)
  ok(test_app.config == test_cfg, "make_app: config is the supplied table")
  ok(type(test_app.backend) == "table", "make_app: backend is a table")
  ok(type(test_app.backend.rest) == "table", "make_app: backend.rest is a table")
  ok(type(test_app.backend.graphql) == "table", "make_app: backend.graphql is a table")
  ok(type(test_app.backend.capabilities) == "table", "make_app: backend.capabilities is a table")
  ok(type(test_app.backend.webhooks) == "table", "make_app: backend.webhooks is a table")
  ok(
    type(test_app.backend.webhook_translators) == "table",
    "make_app: backend.webhook_translators is a table"
  )
  ok(
    type(test_app.backend.webhook_github_translators) == "table",
    "make_app: backend.webhook_github_translators is a table"
  )
  ok(test_app.allow_anonymous == true, "make_app: allow_anonymous defaults to true")
  ok(test_app ~= app, "make_app: returns a new independent table each call")
end

-- ============================================================
-- make_backend_builder
-- ============================================================

do
  local saved_rest = app.backend.rest
  local saved_capabilities = app.backend.capabilities
  local saved_webhooks = app.backend.webhooks
  local saved_webhook_translators = app.backend.webhook_translators
  local saved_webhook_github_translators = app.backend.webhook_github_translators
  local saved_resolvers = graphql_resolvers -- luacheck: globals graphql_resolvers
  local saved_anon = app.allow_anonymous

  local function restore()
    app.backend.rest = saved_rest
    app.backend.capabilities = saved_capabilities
    app.backend.webhooks = saved_webhooks
    app.backend.webhook_translators = saved_webhook_translators
    app.backend.webhook_github_translators = saved_webhook_github_translators
    graphql_resolvers = saved_resolvers -- luacheck: globals graphql_resolvers
    app.allow_anonymous = saved_anon
  end

  -- factory returns a builder table with the expected methods
  local b = make_backend_builder()
  ok(type(b) == "table", "make_backend_builder: returns a table")
  ok(type(b.rest) == "function", "make_backend_builder: has rest method")
  ok(type(b.graphql) == "function", "make_backend_builder: has graphql method")
  ok(type(b.capability) == "function", "make_backend_builder: has capability method")
  ok(type(b.webhook) == "function", "make_backend_builder: has webhook method")
  ok(
    type(b.webhook_translator) == "function",
    "make_backend_builder: has webhook_translator method"
  )
  ok(
    type(b.webhook_github_translator) == "function",
    "make_backend_builder: has webhook_github_translator method"
  )
  ok(
    type(b.set_allow_anonymous) == "function",
    "make_backend_builder: has set_allow_anonymous method"
  )
  ok(type(b.build) == "function", "make_backend_builder: has build method")

  -- registration methods return self for chaining
  local b2 = make_backend_builder()
  ok(b2:rest("get_foo", function() end) == b2, "builder:rest: returns self")
  ok(b2:graphql("Query.foo", function() end) == b2, "builder:graphql: returns self")
  ok(b2:capability("repos", {}) == b2, "builder:capability: returns self")
  ok(b2:webhook("push", function() end) == b2, "builder:webhook: returns self")
  ok(
    b2:webhook_translator("push", function() end) == b2,
    "builder:webhook_translator: returns self"
  )
  ok(
    b2:webhook_github_translator("push", function() end) == b2,
    "builder:webhook_github_translator: returns self"
  )
  ok(b2:set_allow_anonymous(true) == b2, "builder:set_allow_anonymous: returns self")

  -- build() populates app.backend.rest, graphql_resolvers, app.backend.capabilities,
  -- app.backend.webhooks, app.backend.webhook_translators, and
  -- app.backend.webhook_github_translators
  app.backend.rest = {}
  app.backend.capabilities = {}
  app.backend.webhooks = {}
  app.backend.webhook_translators = {}
  app.backend.webhook_github_translators = {}
  graphql_resolvers = {} -- luacheck: globals graphql_resolvers
  app.allow_anonymous = true

  local get_fn = function() end
  local gql_fn = function() end
  local cap_repos = { get = function() end, list = function() end }
  local push_fn = function() end
  local push_translator_fn = function() end
  local push_github_translator_fn = function() end
  local b3 = make_backend_builder()
  b3:rest("get_repo", get_fn)
  b3:graphql("Query.viewer", gql_fn)
  b3:capability("repos", cap_repos)
  b3:webhook("push", push_fn)
  b3:webhook_translator("push", push_translator_fn)
  b3:webhook_github_translator("push", push_github_translator_fn)
  b3:set_allow_anonymous(false)
  b3:build()

  eq(app.backend.rest["get_repo"], get_fn, "builder:build: registers REST handler")
  eq(graphql_resolvers["Query.viewer"], gql_fn, "builder:build: registers GraphQL resolver") -- luacheck: globals graphql_resolvers
  eq(app.backend.capabilities["repos"], cap_repos, "builder:build: registers capability module")
  eq(app.backend.webhooks["push"], push_fn, "builder:build: registers webhook event handler")
  eq(
    app.backend.webhook_translators["push"],
    push_translator_fn,
    "builder:build: registers normalized webhook translator"
  )
  eq(
    app.backend.webhook_github_translators["push"],
    push_github_translator_fn,
    "builder:build: registers GitHub-shape webhook translator"
  )
  eq(app.allow_anonymous, false, "builder:build: sets allow_anonymous")

  -- build() without set_allow_anonymous leaves allow_anonymous unchanged
  app.backend.rest = {}
  app.backend.capabilities = {}
  app.allow_anonymous = true
  local b4 = make_backend_builder()
  b4:rest("get_root", function() end)
  b4:build()
  ok(
    app.allow_anonymous == true,
    "builder:build: does not change allow_anonymous when not declared"
  )

  -- build(strip) excludes REST keys matching any pattern but NOT capabilities or webhooks
  app.backend.rest = {}
  app.backend.capabilities = {}
  app.backend.webhooks = {}
  local cap_issues = { get = function() end }
  local push_fn2 = function() end
  local b5 = make_backend_builder()
  b5:rest("get_repo", function() end)
  b5:rest("get_package_info", function() end)
  b5:rest("list_actions_runs", function() end)
  b5:capability("issues", cap_issues)
  b5:webhook("push", push_fn2)
  b5:build({ "_package", "_actions_" })
  ok(app.backend.rest["get_repo"] ~= nil, "builder:build(strip): keeps non-matching key")
  ok(app.backend.rest["get_package_info"] == nil, "builder:build(strip): strips _package key")
  ok(app.backend.rest["list_actions_runs"] == nil, "builder:build(strip): strips _actions_ key")
  eq(
    app.backend.capabilities["issues"],
    cap_issues,
    "builder:build(strip): capabilities are not stripped"
  )
  eq(
    app.backend.webhooks["push"],
    push_fn2,
    "builder:build(strip): webhook handlers are not stripped"
  )

  -- two builders are independent and do not share state
  app.backend.rest = {}
  app.backend.capabilities = {}
  local ba = make_backend_builder()
  ba:rest("get_foo", function() end)
  ba:capability("repos", { get = function() end })
  local bb = make_backend_builder()
  bb:rest("get_bar", function() end)
  bb:capability("users", { get = function() end })
  ba:build()
  ok(app.backend.rest["get_foo"] ~= nil, "make_backend_builder: builders are independent (a built)")
  ok(
    app.backend.rest["get_bar"] == nil,
    "make_backend_builder: builders are independent (b not yet built)"
  )
  ok(
    app.backend.capabilities["repos"] ~= nil,
    "make_backend_builder: capability builders independent (a built)"
  )
  ok(
    app.backend.capabilities["users"] == nil,
    "make_backend_builder: capability builders independent (b not yet built)"
  )
  bb:build()
  ok(app.backend.rest["get_bar"] ~= nil, "make_backend_builder: builders are independent (b built)")
  ok(
    app.backend.capabilities["users"] ~= nil,
    "make_backend_builder: capability builders independent (b built)"
  )

  restore()
end

-- ============================================================
-- cap_err
-- ============================================================

do
  local e = cap_err(404, "not found")
  ok(type(e) == "table", "cap_err: returns a table")
  eq(e.status, 404, "cap_err: status field set")
  eq(e.message, "not found", "cap_err: message field set")

  local e0 = cap_err(0, "network error")
  eq(e0.status, 0, "cap_err: status 0 for network errors")
end

-- ============================================================
-- cap_fetch
-- ============================================================

do
  local function make_mock_fetch(ok_val, status_val, headers_val, body_val)
    return function(_url, _method, _body)
      return ok_val, status_val, headers_val, body_val
    end
  end

  -- success: 200 with valid JSON
  local fetch_ok = make_mock_fetch(true, 200, {}, '{"name":"hello"}')
  local data, err = cap_fetch(fetch_ok, "https://example.com/api/repo")
  ok(data ~= nil, "cap_fetch: success returns non-nil data")
  ok(err == nil, "cap_fetch: success returns nil err")
  eq(data.name, "hello", "cap_fetch: decoded JSON field")

  -- network error (ok=false)
  local fetch_net_err = make_mock_fetch(false, 0, nil, nil)
  local d2, e2 = cap_fetch(fetch_net_err, "https://example.com/api/repo")
  ok(d2 == nil, "cap_fetch: network error returns nil data")
  ok(e2 ~= nil, "cap_fetch: network error returns non-nil err")
  eq(e2.status, 0, "cap_fetch: network error status is 0")

  -- non-2xx status
  local fetch_404 = make_mock_fetch(true, 404, {}, '{"message":"Not Found"}')
  local d3, e3 = cap_fetch(fetch_404, "https://example.com/api/repo")
  ok(d3 == nil, "cap_fetch: 404 returns nil data")
  ok(e3 ~= nil, "cap_fetch: 404 returns non-nil err")
  eq(e3.status, 404, "cap_fetch: 404 err status is 404")

  -- invalid JSON body
  local fetch_bad_json = make_mock_fetch(true, 200, {}, "not json {{{")
  local d4, e4 = cap_fetch(fetch_bad_json, "https://example.com/api/repo")
  ok(d4 == nil, "cap_fetch: bad JSON returns nil data")
  ok(e4 ~= nil, "cap_fetch: bad JSON returns non-nil err")
  eq(e4.status, 200, "cap_fetch: bad JSON err status is the HTTP status")
end

-- ============================================================
-- cap_fetch_paged
-- ============================================================

do
  local function make_mock_fetch(ok_val, status_val, headers_val, body_val)
    return function(_url, _method, _body)
      return ok_val, status_val, headers_val, body_val
    end
  end

  -- success: returns (data, headers, nil)
  local fetch_ok =
    make_mock_fetch(true, 200, { Link = '<https://x.com?page=2>; rel="next"' }, "[1,2,3]")
  local data, hdrs, err = cap_fetch_paged(fetch_ok, "https://example.com/api/list")
  ok(data ~= nil, "cap_fetch_paged: success returns non-nil data")
  ok(hdrs ~= nil, "cap_fetch_paged: success returns non-nil headers")
  ok(err == nil, "cap_fetch_paged: success returns nil err")
  ok(hdrs["Link"] ~= nil, "cap_fetch_paged: Link header present")

  -- missing headers → empty table
  local fetch_no_hdrs = make_mock_fetch(true, 200, nil, "[]")
  local d2, h2, e2 = cap_fetch_paged(fetch_no_hdrs, "https://example.com/api/list")
  ok(d2 ~= nil, "cap_fetch_paged: no headers → data still returned")
  ok(type(h2) == "table", "cap_fetch_paged: no headers → empty table")
  ok(e2 == nil, "cap_fetch_paged: no headers → nil err")

  -- network error: returns (nil, nil, err)
  local fetch_net_err = make_mock_fetch(false, 0, nil, nil)
  local d3, h3, e3 = cap_fetch_paged(fetch_net_err, "https://example.com/api/list")
  ok(d3 == nil, "cap_fetch_paged: network error returns nil data")
  ok(h3 == nil, "cap_fetch_paged: network error returns nil headers")
  ok(e3 ~= nil, "cap_fetch_paged: network error returns non-nil err")
  eq(e3.status, 0, "cap_fetch_paged: network error err.status is 0")

  -- non-2xx: returns (nil, nil, err)
  local fetch_403 = make_mock_fetch(true, 403, {}, '{"message":"Forbidden"}')
  local d4, h4, e4 = cap_fetch_paged(fetch_403, "https://example.com/api/list")
  ok(d4 == nil, "cap_fetch_paged: 403 returns nil data")
  ok(h4 == nil, "cap_fetch_paged: 403 returns nil headers")
  eq(e4.status, 403, "cap_fetch_paged: 403 err.status is 403")
end

-- ============================================================
-- cap_rest_respond
-- ============================================================

do
  -- success with translate
  reset_response()
  cap_rest_respond({ id = 1, x = "a" }, nil, function(d)
    return { id = d.id }
  end)
  eq(_last_status, 200, "cap_rest_respond: success → 200")
  ok(_last_body:find('"id"') ~= nil, "cap_rest_respond: body contains translated field")
  ok(_last_body:find('"x"') == nil, "cap_rest_respond: translate removes unwanted field")

  -- success without translate
  reset_response()
  cap_rest_respond({ v = 42 }, nil, nil)
  eq(_last_status, 200, "cap_rest_respond: no translate → 200")

  -- network error → 503
  reset_response()
  cap_rest_respond(nil, cap_err(0, "connection refused"), nil)
  eq(_last_status, 503, "cap_rest_respond: network error → 503")

  -- upstream 404 → 404
  reset_response()
  cap_rest_respond(nil, cap_err(404, "not found"), nil)
  eq(_last_status, 404, "cap_rest_respond: upstream 404 → 404")

  -- upstream 403 → 403
  reset_response()
  cap_rest_respond(nil, cap_err(403, "forbidden"), nil)
  eq(_last_status, 403, "cap_rest_respond: upstream 403 → 403")
end

-- ============================================================
-- cap_rest_created
-- ============================================================

do
  -- success → 201
  reset_response()
  cap_rest_created({ id = 99 }, nil, nil)
  eq(_last_status, 201, "cap_rest_created: success → 201")

  -- network error → 503
  reset_response()
  cap_rest_created(nil, cap_err(0, "timeout"), nil)
  eq(_last_status, 503, "cap_rest_created: network error → 503")

  -- upstream 422 → 422
  reset_response()
  cap_rest_created(nil, cap_err(422, "unprocessable"), nil)
  eq(_last_status, 422, "cap_rest_created: upstream 422 → 422")
end

-- ============================================================
-- cap_rest_204
-- ============================================================

do
  -- ok → 204
  reset_response()
  cap_rest_204(true, nil)
  eq(_last_status, 204, "cap_rest_204: ok → 204")

  -- network error → 503
  reset_response()
  cap_rest_204(nil, cap_err(0, "connection reset"))
  eq(_last_status, 503, "cap_rest_204: network error → 503")

  -- upstream 404 → 404
  reset_response()
  cap_rest_204(nil, cap_err(404, "repo not found"))
  eq(_last_status, 404, "cap_rest_204: upstream 404 → 404")
end

-- ============================================================
-- cap_rest_paged
-- ============================================================

do
  local PAGES = { per_page = "limit", page = "page" }

  -- need a Host header for rewrite_link_header
  reset_request({ headers = { Host = "proxy.example.com" }, path = "/repos" })

  -- success with Link header → 200 + rewritten Link
  reset_response()
  local hdrs_with_link = { Link = '<https://gitea.com/api/v1/repos?limit=30&page=2>; rel="next"' }
  cap_rest_paged({ { id = 1 } }, hdrs_with_link, nil, PAGES, nil)
  eq(_last_status, 200, "cap_rest_paged: success → 200")
  ok(_last_headers["Link"] ~= nil, "cap_rest_paged: Link header rewritten")
  ok(
    _last_headers["Link"]:find("proxy.example.com") ~= nil,
    "cap_rest_paged: Link rewritten to proxy host"
  )

  -- success without Link header → 200, no Link
  reset_response()
  cap_rest_paged({ { id = 1 } }, {}, nil, PAGES, nil)
  eq(_last_status, 200, "cap_rest_paged: no upstream Link → 200")
  ok(_last_headers["Link"] == nil, "cap_rest_paged: no Link header when none upstream")

  -- success with translate
  reset_response()
  cap_rest_paged({ { raw = true } }, {}, nil, PAGES, function(items)
    return translate_list(function(i)
      return { translated = i.raw }
    end, items)
  end)
  eq(_last_status, 200, "cap_rest_paged: translate applied")

  -- network error → 503
  reset_response()
  cap_rest_paged(nil, nil, cap_err(0, "network down"), PAGES, nil)
  eq(_last_status, 503, "cap_rest_paged: network error → 503")

  -- upstream 401 → 401
  reset_response()
  cap_rest_paged(nil, nil, cap_err(401, "unauthorized"), PAGES, nil)
  eq(_last_status, 401, "cap_rest_paged: upstream 401 → 401")
end

-- ============================================================
-- Launchpad webhook handlers
-- ============================================================

do
  local saved_rest = app.backend.rest
  local saved_capabilities = app.backend.capabilities
  local saved_webhooks = app.backend.webhooks
  local saved_webhook_translators = app.backend.webhook_translators
  local saved_base_url = config.base_url
  local saved_backend = config.backend

  app.backend.rest = {}
  app.backend.capabilities = {}
  app.backend.webhooks = {}
  app.backend.webhook_translators = {}
  config.base_url = ""
  config.backend = "launchpad"
  _real_dofile("backends/launchpad.lua")

  local push_payload = {
    git_repository = "/devel/~fido/confusio/+git/confusio",
    git_repository_path = "~fido/confusio/+git/confusio",
    ref_changes = {
      ["refs/heads/main"] = {
        old = { commit_sha1 = "1111111111111111111111111111111111111111" },
        new = { commit_sha1 = "2222222222222222222222222222222222222222" },
      },
    },
  }
  local push_event = app.backend.webhooks["git:push:0.1"](push_payload)
  eq(push_event.event, "push", "launchpad webhook: git push maps to push")
  eq(push_event.provider, "launchpad", "launchpad webhook: git push sets provider")
  eq(push_event.data.ref, "refs/heads/main", "launchpad webhook: git push sets ref")
  eq(
    push_event.data.before,
    "1111111111111111111111111111111111111111",
    "launchpad webhook: git push sets before SHA"
  )
  eq(
    push_event.data.after,
    "2222222222222222222222222222222222222222",
    "launchpad webhook: git push sets after SHA"
  )
  eq(
    push_event.data.repository.full_name,
    "fido/confusio",
    "launchpad webhook: git push sets repository"
  )
  local push_envelope = app.backend.webhook_translators.push(push_event)
  eq(push_envelope.type, "push", "launchpad webhook: normalized push is actionless")
  eq(push_envelope.repository.full_name, "fido/confusio", "launchpad webhook: push envelope repo")

  local ping_event = app.backend.webhooks.ping({ ping = true })
  eq(ping_event.event, "ping", "launchpad webhook: ping maps to ping")
  eq(ping_event.data.zen, "Launchpad", "launchpad webhook: ping sets zen")
  local ping_envelope = app.backend.webhook_translators.ping(ping_event)
  eq(ping_envelope.type, "ping", "launchpad webhook: normalized ping is actionless")

  local bug_payload = {
    action = "created",
    target = "/confusio",
    bug = "/bugs/1234",
    owner = "/~fido",
  }
  local bug_event = app.backend.webhooks["bug:0.1"](bug_payload)
  eq(bug_event.event, "issues", "launchpad webhook: bug maps to issues")
  eq(bug_event.action, "opened", "launchpad webhook: bug created maps to opened")
  eq(bug_event.data.issue.number, 1234, "launchpad webhook: bug sets issue number")
  eq(
    bug_event.data.repository.full_name,
    "launchpad/confusio",
    "launchpad webhook: bug sets target repository"
  )
  local bug_envelope = app.backend.webhook_translators.issues(bug_event)
  eq(bug_envelope.type, "issue.opened", "launchpad webhook: normalized bug includes action")

  local bug_edit_event = app.backend.webhooks["bug:0.1"]({
    action = "status-changed",
    target = "/ubuntu/+source/confusio",
    bug = "/bugs/1234",
  })
  eq(bug_edit_event.action, "edited", "launchpad webhook: bug field change maps to edited")

  local comment_payload = {
    action = "created",
    target = "/confusio",
    bug = "/bugs/1234",
    bug_comment = "/bugs/1234/comments/5",
    new = {
      commenter = "/~fido",
      content = "Woof, found the bug.",
    },
  }
  local comment_event = app.backend.webhooks["bug:comment:0.1"](comment_payload)
  eq(comment_event.event, "issue_comment", "launchpad webhook: comment maps to issue_comment")
  eq(comment_event.action, "created", "launchpad webhook: comment created maps to created")
  eq(comment_event.data.issue.number, 1234, "launchpad webhook: comment sets issue number")
  eq(comment_event.data.comment.id, 5, "launchpad webhook: comment sets comment id")
  eq(
    comment_event.data.comment.body,
    "Woof, found the bug.",
    "launchpad webhook: comment sets body"
  )
  local comment_envelope = app.backend.webhook_translators.issue_comment(comment_event)
  eq(
    comment_envelope.type,
    "issue.comment.created",
    "launchpad webhook: normalized comment includes action"
  )

  local mp_payload = {
    action = "created",
    merge_proposal = "/~fido/confusio/+git/feature/+merge/42",
    new = {
      registrant = "/~fido",
      commit_message = "Add the good feature",
      description = "Please merge this branch.",
      source_git_repository = "/~fido/confusio/+git/feature",
      source_git_path = "~fido/confusio/+git/feature",
      target_git_repository = "/~fido/confusio/+git/main",
      target_git_path = "~fido/confusio/+git/main",
      queue_status = "Needs review",
    },
  }
  local mp_event = app.backend.webhooks["merge-proposal:0.1"](mp_payload)
  eq(mp_event.event, "pull_request", "launchpad webhook: merge proposal maps to pull_request")
  eq(mp_event.action, "opened", "launchpad webhook: merge proposal created maps to opened")
  eq(mp_event.data.number, 42, "launchpad webhook: merge proposal sets number")
  eq(
    mp_event.data.pull_request.title,
    "Add the good feature",
    "launchpad webhook: merge proposal sets title"
  )
  eq(
    mp_event.data.repository.full_name,
    "fido/main",
    "launchpad webhook: merge proposal sets base repository"
  )
  local mp_envelope = app.backend.webhook_translators.pull_request(mp_event)
  eq(
    mp_envelope.type,
    "pull_request.opened",
    "launchpad webhook: normalized merge proposal includes action"
  )

  local mp_sync_event = app.backend.webhooks["merge-proposal:0.1"]({
    action = "modified",
    merge_proposal = "/~fido/confusio/+git/feature/+merge/42",
    old = { source_git_commit_sha = "1111111111111111111111111111111111111111" },
    new = { source_git_commit_sha = "2222222222222222222222222222222222222222" },
  })
  eq(
    mp_sync_event.action,
    "synchronize",
    "launchpad webhook: merge proposal push maps to synchronize"
  )

  local mp_closed_event = app.backend.webhooks["merge-proposal:0.1"]({
    action = "modified",
    merge_proposal = "/~fido/confusio/+git/feature/+merge/42",
    old = { queue_status = "Needs review" },
    new = { queue_status = "Merged" },
  })
  eq(mp_closed_event.action, "closed", "launchpad webhook: merge proposal merged maps to closed")

  local ci_event = app.backend.webhooks["ci:build:0.1"]({
    action = "created",
    build = "/~fido/confusio/+git/main/+build/77",
    git_repository = "/~fido/confusio/+git/main",
    commit_sha1 = "3333333333333333333333333333333333333333",
    status = "Needs building",
  })
  eq(ci_event.event, "workflow_run", "launchpad webhook: CI build maps to workflow_run")
  eq(ci_event.action, "requested", "launchpad webhook: CI build created maps to requested")
  eq(ci_event.data.workflow_run.id, 77, "launchpad webhook: CI build sets run id")
  eq(
    ci_event.data.workflow_run.head_sha,
    "3333333333333333333333333333333333333333",
    "launchpad webhook: CI build sets head SHA"
  )
  local ci_envelope = app.backend.webhook_translators.workflow_run(ci_event)
  eq(
    ci_envelope.type,
    "workflow.run.requested",
    "launchpad webhook: normalized CI build includes action"
  )

  local snap_event = app.backend.webhooks["snap:build:0.1"]({
    action = "status-changed",
    snap_build = "/~fido/+snap/confusio/+build/88",
    snap = "/~fido/+snap/confusio",
    status = "Successfully built",
    store_upload_status = "Uploaded",
  })
  eq(snap_event.action, "completed", "launchpad webhook: successful snap build maps to completed")
  eq(
    snap_event.data.workflow_run.conclusion,
    "success",
    "launchpad webhook: successful snap build sets success conclusion"
  )

  local binary_build_event = app.backend.webhooks["archive:binary-build:0.1"]({
    action = "status-changed",
    build = "/~fido/+archive/ubuntu/ppa/+build/99",
    archive = "/~fido/+archive/ubuntu/ppa",
    source_package_name = "confusio",
    status = "Failed to build",
    buildlog = "https://launchpad.net/buildlog.txt",
  })
  eq(
    binary_build_event.action,
    "completed",
    "launchpad webhook: failed binary build maps to completed"
  )
  eq(
    binary_build_event.data.workflow_run.conclusion,
    "failure",
    "launchpad webhook: failed binary build sets failure conclusion"
  )

  local source_package_event = app.backend.webhooks["archive:source-package-upload:0.1"]({
    action = "status-changed",
    package_upload = "/~fido/+archive/ubuntu/ppa/+upload/12",
    status = "Accepted",
    archive = "/~fido/+archive/ubuntu/ppa",
    package_name = "confusio",
    package_version = "1.2.3",
  })
  eq(source_package_event.event, "package", "launchpad webhook: source upload maps to package")
  eq(
    source_package_event.action,
    "published",
    "launchpad webhook: accepted upload maps to published"
  )
  eq(
    source_package_event.data.package.package_type,
    "deb-source",
    "launchpad webhook: source upload sets package type"
  )
  local package_envelope = app.backend.webhook_translators.package(source_package_event)
  eq(
    package_envelope.type,
    "package.published",
    "launchpad webhook: normalized package includes action"
  )

  local binary_package_event = app.backend.webhooks["archive:binary-package-upload:0.1"]({
    action = "status-changed",
    package_upload = "/~fido/+archive/ubuntu/ppa/+upload/13",
    status = "Rejected",
    archive = "/~fido/+archive/ubuntu/ppa",
    source_package_name = "confusio",
  })
  eq(binary_package_event.action, "updated", "launchpad webhook: rejected upload maps to updated")
  eq(
    binary_package_event.data.package.package_type,
    "deb-binary",
    "launchpad webhook: binary upload sets package type"
  )

  app.backend.rest = saved_rest
  app.backend.capabilities = saved_capabilities
  app.backend.webhooks = saved_webhooks
  app.backend.webhook_translators = saved_webhook_translators
  config.base_url = saved_base_url
  config.backend = saved_backend
end

-- ============================================================
-- Phabricator webhook handlers
-- ============================================================

do
  local saved_rest = app.backend.rest
  local saved_capabilities = app.backend.capabilities
  local saved_webhooks = app.backend.webhooks
  local saved_webhook_translators = app.backend.webhook_translators
  local saved_webhook_github_translators = app.backend.webhook_github_translators
  local saved_resolvers = graphql_resolvers -- luacheck: globals graphql_resolvers
  local saved_base_url = config.base_url
  local saved_backend = config.backend

  app.backend.rest = {}
  app.backend.capabilities = {}
  app.backend.webhooks = {}
  app.backend.webhook_translators = {}
  app.backend.webhook_github_translators = {}
  graphql_resolvers = {} -- luacheck: globals graphql_resolvers
  config.base_url = ""
  config.backend = "phabricator"
  _real_dofile("backends/phabricator.lua")

  ok(app.backend.webhooks.TASK ~= nil, "phabricator webhook: TASK handler registered")
  ok(
    app.backend.webhook_translators.issues ~= nil,
    "phabricator webhook: issues translator registered"
  )
  ok(
    app.backend.webhook_github_translators.issues ~= nil,
    "phabricator webhook: issues GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_translators.pull_request ~= nil,
    "phabricator webhook: pull_request translator registered"
  )
  ok(app.backend.webhook_translators.push ~= nil, "phabricator webhook: push translator registered")
  ok(
    app.backend.webhook_github_translators.push ~= nil,
    "phabricator webhook: push GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_translators.repository ~= nil,
    "phabricator webhook: repository translator registered"
  )

  local task_payload = {
    object = {
      type = "TASK",
      id = 123,
      phid = "PHID-TASK-123",
      fields = {
        name = "Fix the kennel door",
        status = { value = "open" },
        authorPHID = "PHID-USER-fido",
        description = { raw = "The latch sticks." },
        dateCreated = 1715767200,
        dateModified = 1715770800,
      },
    },
    repository = { full_name = "phabricator/maniphest" },
    action = { actorPHID = "PHID-USER-rob", epoch = 1715770800 },
    transactions = {
      { type = "title", oldValue = "Fix door", newValue = "Fix the kennel door" },
    },
  }
  local task_event = app.backend.webhooks.TASK(task_payload)
  eq(task_event.event, "issues", "phabricator webhook: TASK maps to issues")
  eq(task_event.action, "edited", "phabricator webhook: task title change maps to edited")
  eq(task_event.provider, "phabricator", "phabricator webhook: TASK sets provider")
  eq(task_event.data.issue.number, 123, "phabricator webhook: task sets issue number")
  eq(
    task_event.data.issue.title,
    "Fix the kennel door",
    "phabricator webhook: task sets issue title"
  )
  eq(
    task_event.data.repository.full_name,
    "phabricator/maniphest",
    "phabricator webhook: task keeps repository"
  )
  eq(task_event.data.sender.login, "PHID-USER-rob", "phabricator webhook: task sets sender")
  local task_envelope = app.backend.webhook_translators.issues(task_event)
  eq(task_envelope.type, "issue.edited", "phabricator webhook: normalized task includes action")
  local task_github_payload = app.backend.webhook_github_translators.issues(task_event)
  eq(task_github_payload.issue.number, 123, "phabricator webhook: GitHub-shape task includes issue")

  local closed_event = app.backend.webhooks.TASK({
    object = {
      type = "TASK",
      id = 124,
      phid = "PHID-TASK-124",
      fields = {
        name = "Close this",
        status = { value = "resolved", closed = true },
      },
    },
    transactions = {
      { type = "status", oldValue = "open", newValue = "resolved" },
    },
  })
  eq(closed_event.action, "closed", "phabricator webhook: status change maps to closed")
  eq(closed_event.data.issue.state, "closed", "phabricator webhook: closed task state")

  local comment_event = app.backend.webhooks.TASK({
    object = {
      type = "TASK",
      id = 125,
      phid = "PHID-TASK-125",
      fields = {
        name = "Comment here",
        status = { value = "open" },
      },
    },
    transactions = {
      {
        type = "comment",
        id = 77,
        phid = "PHID-XACT-TASK-comment",
        authorPHID = "PHID-USER-commenter",
        dateCreated = 1715774400,
        comments = {
          { content = { raw = "I found a clue." } },
        },
      },
    },
  })
  eq(
    comment_event.event,
    "issue_comment",
    "phabricator webhook: comment transaction maps to issue_comment"
  )
  eq(comment_event.action, "created", "phabricator webhook: comment maps to created")
  eq(comment_event.data.comment.body, "I found a clue.", "phabricator webhook: comment body")
  local comment_envelope = app.backend.webhook_translators.issue_comment(comment_event)
  eq(
    comment_envelope.type,
    "issue.comment.created",
    "phabricator webhook: normalized comment includes action"
  )
  local comment_github_payload = app.backend.webhook_github_translators.issue_comment(comment_event)
  eq(
    comment_github_payload.comment.body,
    "I found a clue.",
    "phabricator webhook: GitHub-shape comment includes body"
  )

  local revision_payload = {
    object = {
      type = "DREV",
      id = 45,
      phid = "PHID-DREV-45",
      fields = {
        title = "Teach the code review path",
        summary = { raw = "Differential review body." },
        status = { value = "needs-review" },
        authorPHID = "PHID-USER-reviewer",
        sourceBranch = "feature/differential",
        targetBranch = "main",
        sourceCommit = "abc123",
        dateCreated = 1715778000,
        dateModified = 1715781600,
      },
    },
    repository = { full_name = "phabricator/differential" },
    action = { actorPHID = "PHID-USER-rob", epoch = 1715781600 },
    transactions = {
      { type = "core:create" },
    },
  }
  local revision_event = app.backend.webhooks.DREV(revision_payload)
  eq(revision_event.event, "pull_request", "phabricator webhook: DREV maps to pull_request")
  eq(revision_event.action, "opened", "phabricator webhook: DREV create maps to opened")
  eq(revision_event.data.number, 45, "phabricator webhook: DREV sets number")
  eq(
    revision_event.data.pull_request.title,
    "Teach the code review path",
    "phabricator webhook: DREV sets title"
  )
  eq(
    revision_event.data.pull_request.head.ref,
    "feature/differential",
    "phabricator webhook: DREV sets head ref"
  )
  eq(revision_event.data.pull_request.base.ref, "main", "phabricator webhook: DREV sets base ref")
  local revision_envelope = app.backend.webhook_translators.pull_request(revision_event)
  eq(
    revision_envelope.type,
    "pull_request.opened",
    "phabricator webhook: normalized DREV includes action"
  )
  local revision_github_payload =
    app.backend.webhook_github_translators.pull_request(revision_event)
  eq(
    revision_github_payload.pull_request.number,
    45,
    "phabricator webhook: GitHub-shape DREV includes pull_request"
  )

  local accepted_event = app.backend.webhooks.DREV({
    object = {
      type = "DREV",
      id = 46,
      phid = "PHID-DREV-46",
      fields = {
        title = "Accepted review",
        status = { value = "accepted", closed = true },
        dateModified = 1715785200,
      },
    },
    transactions = {
      { type = "status", oldValue = "needs-review", newValue = "accepted" },
    },
  })
  eq(accepted_event.action, "closed", "phabricator webhook: DREV accepted maps to closed")
  eq(accepted_event.data.pull_request.state, "closed", "phabricator webhook: accepted DREV state")
  ok(
    accepted_event.data.pull_request.merged == true,
    "phabricator webhook: accepted DREV marks merged"
  )

  local diff_event = app.backend.webhooks.DIFF({
    object = {
      type = "DIFF",
      id = 9001,
      phid = "PHID-DIFF-9001",
    },
    revision = {
      id = 47,
      phid = "PHID-DREV-47",
      fields = {
        title = "Updated diff",
        status = { value = "needs-review" },
        sourceBranch = "feature/updated",
        targetBranch = "main",
      },
    },
    repository = { full_name = "phabricator/differential" },
    action = { actorPHID = "PHID-USER-diff" },
  })
  eq(diff_event.event, "pull_request", "phabricator webhook: DIFF maps to pull_request")
  eq(diff_event.action, "synchronize", "phabricator webhook: DIFF maps to synchronize")
  eq(diff_event.data.number, 47, "phabricator webhook: DIFF uses revision number")

  local commit_event = app.backend.webhooks.CMIT({
    object = {
      type = "CMIT",
      id = 9002,
      phid = "PHID-CMIT-9002",
      fields = {
        identifier = "abcdef123456",
        message = "Teach Diffusion push webhooks",
        branch = "main",
        authorName = "Fido",
        authorPHID = "PHID-USER-fido",
        committerName = "Rob",
        committerPHID = "PHID-USER-rob",
        epoch = 1715788800,
      },
    },
    repository = {
      id = 12,
      phid = "PHID-REPO-confusio",
      fields = {
        name = "confusio",
        shortName = "confusio",
        defaultBranch = "main",
      },
    },
    action = { actorPHID = "PHID-USER-rob", epoch = 1715788800 },
  })
  eq(commit_event.event, "push", "phabricator webhook: CMIT maps to push")
  eq(commit_event.action, "", "phabricator webhook: CMIT is action-less push")
  eq(commit_event.data.ref, "refs/heads/main", "phabricator webhook: CMIT sets ref")
  eq(commit_event.data.after, "abcdef123456", "phabricator webhook: CMIT sets after SHA")
  eq(
    commit_event.data.head_commit.message,
    "Teach Diffusion push webhooks",
    "phabricator webhook: CMIT sets head commit"
  )
  eq(
    commit_event.data.repository.full_name,
    "confusio",
    "phabricator webhook: CMIT translates repository"
  )
  local commit_envelope = app.backend.webhook_translators.push(commit_event)
  eq(commit_envelope.type, "push", "phabricator webhook: normalized CMIT uses push type")
  local commit_github_payload = app.backend.webhook_github_translators.push(commit_event)
  eq(
    commit_github_payload.head_commit.id,
    "abcdef123456",
    "phabricator webhook: GitHub-shape CMIT includes head commit"
  )

  local repo_event = app.backend.webhooks.REPO({
    object = {
      type = "REPO",
      id = 12,
      phid = "PHID-REPO-confusio",
      fields = {
        name = "confusio-renamed",
        shortName = "confusio-renamed",
        defaultBranch = "main",
        dateModified = 1715792400,
      },
    },
    action = { actorPHID = "PHID-USER-rob", epoch = 1715792400 },
    transactions = {
      { type = "name", oldValue = "confusio" },
    },
  })
  eq(repo_event.event, "repository", "phabricator webhook: REPO maps to repository")
  eq(repo_event.action, "renamed", "phabricator webhook: REPO name change maps to renamed")
  eq(
    repo_event.data.repository.full_name,
    "confusio-renamed",
    "phabricator webhook: REPO translates repository"
  )
  eq(
    repo_event.data.changes.repository.name.from,
    "confusio",
    "phabricator webhook: REPO records previous name"
  )
  local repo_envelope = app.backend.webhook_translators.repository(repo_event)
  eq(
    repo_envelope.type,
    "repository.renamed",
    "phabricator webhook: normalized REPO includes action"
  )
  local repo_github_payload = app.backend.webhook_github_translators.repository(repo_event)
  eq(
    repo_github_payload.repository.name,
    "confusio-renamed",
    "phabricator webhook: GitHub-shape REPO includes repository"
  )

  app.backend.rest = saved_rest
  app.backend.capabilities = saved_capabilities
  app.backend.webhooks = saved_webhooks
  app.backend.webhook_translators = saved_webhook_translators
  app.backend.webhook_github_translators = saved_webhook_github_translators
  graphql_resolvers = saved_resolvers -- luacheck: globals graphql_resolvers
  config.base_url = saved_base_url
  config.backend = saved_backend
end

-- ============================================================
-- Sourcehut webhook handlers
-- ============================================================

do
  local saved_rest = app.backend.rest
  local saved_capabilities = app.backend.capabilities
  local saved_webhooks = app.backend.webhooks
  local saved_webhook_translators = app.backend.webhook_translators
  local saved_webhook_github_translators = app.backend.webhook_github_translators
  local saved_resolvers = graphql_resolvers -- luacheck: globals graphql_resolvers
  local saved_base_url = config.base_url
  local saved_backend = config.backend

  app.backend.rest = {}
  app.backend.capabilities = {}
  app.backend.webhooks = {}
  app.backend.webhook_translators = {}
  app.backend.webhook_github_translators = {}
  graphql_resolvers = {} -- luacheck: globals graphql_resolvers
  config.base_url = ""
  config.backend = "sourcehut"
  _real_dofile("backends/sourcehut.lua")

  ok(app.backend.webhooks.REPO_CREATED ~= nil, "sourcehut webhook: REPO_CREATED registered")
  ok(app.backend.webhooks.REPO_UPDATE ~= nil, "sourcehut webhook: REPO_UPDATE registered")
  ok(app.backend.webhooks.REPO_DELETED ~= nil, "sourcehut webhook: REPO_DELETED registered")
  ok(app.backend.webhooks.GIT_PRE_RECEIVE ~= nil, "sourcehut webhook: GIT_PRE_RECEIVE registered")
  ok(app.backend.webhooks.GIT_POST_RECEIVE ~= nil, "sourcehut webhook: GIT_POST_RECEIVE registered")
  ok(app.backend.webhook_translators.push ~= nil, "sourcehut webhook: push translator registered")
  ok(
    app.backend.webhook_github_translators.push ~= nil,
    "sourcehut webhook: push GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_translators.repository ~= nil,
    "sourcehut webhook: repository translator registered"
  )
  ok(
    app.backend.webhook_github_translators.repository ~= nil,
    "sourcehut webhook: repository GitHub-shape translator registered"
  )
  ok(app.backend.webhooks.TICKET_CREATED ~= nil, "sourcehut webhook: TICKET_CREATED registered")
  ok(app.backend.webhooks.TICKET_UPDATE ~= nil, "sourcehut webhook: TICKET_UPDATE registered")
  ok(app.backend.webhooks.TICKET_DELETED ~= nil, "sourcehut webhook: TICKET_DELETED registered")
  ok(app.backend.webhooks.LABEL_CREATED ~= nil, "sourcehut webhook: LABEL_CREATED registered")
  ok(app.backend.webhooks.LABEL_UPDATE ~= nil, "sourcehut webhook: LABEL_UPDATE registered")
  ok(app.backend.webhooks.LABEL_DELETED ~= nil, "sourcehut webhook: LABEL_DELETED registered")
  ok(app.backend.webhooks.EVENT_CREATED ~= nil, "sourcehut webhook: EVENT_CREATED registered")
  ok(app.backend.webhooks.JOB_CREATED ~= nil, "sourcehut webhook: JOB_CREATED registered")
  ok(app.backend.webhooks.JOB_UPDATED ~= nil, "sourcehut webhook: JOB_UPDATED registered")
  ok(
    app.backend.webhooks.PATCHSET_RECEIVED ~= nil,
    "sourcehut webhook: PATCHSET_RECEIVED registered"
  )
  ok(
    app.backend.webhook_translators.issues ~= nil,
    "sourcehut webhook: issues translator registered"
  )
  ok(
    app.backend.webhook_github_translators.issues ~= nil,
    "sourcehut webhook: issues GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_translators.issue_comment ~= nil,
    "sourcehut webhook: issue_comment translator registered"
  )
  ok(app.backend.webhook_translators.label ~= nil, "sourcehut webhook: label translator registered")
  ok(
    app.backend.webhook_translators.workflow_run ~= nil,
    "sourcehut webhook: workflow_run translator registered"
  )
  ok(
    app.backend.webhook_github_translators.workflow_run ~= nil,
    "sourcehut webhook: workflow_run GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_translators.pull_request ~= nil,
    "sourcehut webhook: pull_request translator registered"
  )
  ok(
    app.backend.webhook_github_translators.pull_request ~= nil,
    "sourcehut webhook: pull_request GitHub-shape translator registered"
  )

  local repo_payload = {
    data = {
      webhook = { event = "REPO_CREATED", date = "2026-05-02T01:02:03Z" },
      repository = {
        id = 272,
        rid = "repo-rid",
        name = "confusio",
        description = "Webhook kennel",
        visibility = "PUBLIC",
        owner = { id = 7, canonicalName = "~fido", name = "Fido" },
        HEAD = { name = "refs/heads/main" },
        created = "2026-05-01T00:00:00Z",
        updated = "2026-05-02T01:00:00Z",
      },
    },
  }
  local repo_event = app.backend.webhooks.REPO_CREATED(repo_payload)
  eq(repo_event.event, "repository", "sourcehut webhook: REPO_CREATED maps to repository")
  eq(repo_event.action, "created", "sourcehut webhook: REPO_CREATED maps to created")
  eq(repo_event.provider, "sourcehut", "sourcehut webhook: repository sets provider")
  eq(
    repo_event.data.repository.full_name,
    "fido/confusio",
    "sourcehut webhook: repository full_name translated"
  )
  eq(
    repo_event.data.sender.login,
    "fido",
    "sourcehut webhook: repository sender falls back to owner"
  )
  local repo_envelope = app.backend.webhook_translators.repository(repo_event)
  eq(repo_envelope.type, "repository.created", "sourcehut webhook: normalized repository type")
  local repo_github_payload = app.backend.webhook_github_translators.repository(repo_event)
  eq(
    repo_github_payload.repository.name,
    "confusio",
    "sourcehut webhook: GitHub-shape repository includes repository"
  )
  eq(
    app.backend.webhooks.REPO_UPDATE(repo_payload).action,
    "edited",
    "sourcehut webhook: REPO_UPDATE maps to edited"
  )
  eq(
    app.backend.webhooks.REPO_DELETED(repo_payload).action,
    "deleted",
    "sourcehut webhook: REPO_DELETED maps to deleted"
  )

  local git_payload = {
    data = {
      webhook = { event = "GIT_POST_RECEIVE", date = "2026-05-02T02:03:04Z" },
      repository = {
        id = 272,
        name = "confusio",
        visibility = "PUBLIC",
        owner = { canonicalName = "~fido" },
        HEAD = { name = "refs/heads/main" },
      },
      pusher = { canonicalName = "~rob", name = "Rob" },
      updates = {
        {
          ref = { name = "refs/heads/main" },
          old = { id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" },
          new = { id = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" },
          log = {
            results = {
              {
                id = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                message = "Teach sourcehut pushes",
                author = {
                  name = "Fido",
                  email = "fido@example.test",
                  time = "2026-05-02T02:00:00Z",
                },
                committer = {
                  name = "Rob",
                  email = "rob@example.test",
                  time = "2026-05-02T02:01:00Z",
                },
              },
            },
          },
        },
      },
    },
  }
  local push_event = app.backend.webhooks.GIT_POST_RECEIVE(git_payload)
  eq(push_event.event, "push", "sourcehut webhook: GIT_POST_RECEIVE maps to push")
  eq(push_event.action, "", "sourcehut webhook: push is action-less")
  eq(push_event.data.ref, "refs/heads/main", "sourcehut webhook: push keeps ref")
  eq(
    push_event.data.head_commit.id,
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sourcehut webhook: push sets head commit"
  )
  eq(push_event.data.sender.login, "rob", "sourcehut webhook: push sets sender from pusher")
  local push_envelope = app.backend.webhook_translators.push(push_event)
  eq(push_envelope.type, "push", "sourcehut webhook: normalized push uses actionless type")
  local push_github_payload = app.backend.webhook_github_translators.push(push_event)
  eq(
    push_github_payload.head_commit.message,
    "Teach sourcehut pushes",
    "sourcehut webhook: GitHub-shape push includes head commit"
  )
  eq(push_github_payload.pusher.name, "Rob", "sourcehut webhook: GitHub-shape push includes pusher")

  local create_event = app.backend.webhooks.GIT_PRE_RECEIVE({
    data = {
      webhook = { event = "GIT_PRE_RECEIVE" },
      repository = {
        name = "confusio",
        owner = { canonicalName = "~fido" },
        HEAD = { name = "refs/heads/main" },
      },
      updates = {
        {
          ref = { name = "refs/tags/v1.0.0" },
          old = { id = "0000000000000000000000000000000000000000" },
          new = { id = "cccccccccccccccccccccccccccccccccccccccc" },
        },
      },
    },
  })
  eq(create_event.event, "create", "sourcehut webhook: zero old id maps to create")
  eq(create_event.data.ref, "v1.0.0", "sourcehut webhook: create strips tag ref")
  eq(create_event.data.ref_type, "tag", "sourcehut webhook: create detects tag ref")

  local ticket_payload = {
    data = {
      webhook = { event = "TICKET_CREATED", date = "2026-05-02T03:04:05Z" },
      ticket = {
        id = 42,
        rid = "ticket-rid",
        subject = "Open the tracker gate",
        body = "It sticks.",
        status = "REPORTED",
        created = "2026-05-02T03:00:00Z",
        updated = "2026-05-02T03:01:00Z",
        submitter = { canonicalName = "~fido", username = "fido" },
        tracker = {
          id = 9,
          rid = "tracker-rid",
          name = "confusio",
          visibility = "PUBLIC",
          owner = { canonicalName = "~fido", username = "fido" },
        },
        labels = {
          {
            id = 5,
            name = "bug",
            backgroundColor = "#ff0000",
          },
        },
      },
    },
  }
  local issue_event = app.backend.webhooks.TICKET_CREATED(ticket_payload)
  eq(issue_event.event, "issues", "sourcehut webhook: TICKET_CREATED maps to issues")
  eq(issue_event.action, "opened", "sourcehut webhook: TICKET_CREATED maps to opened")
  eq(issue_event.data.issue.number, 42, "sourcehut webhook: ticket issue number")
  eq(issue_event.data.issue.title, "Open the tracker gate", "sourcehut webhook: ticket subject")
  eq(issue_event.data.issue.labels[1].name, "bug", "sourcehut webhook: ticket labels translated")
  eq(
    issue_event.data.repository.full_name,
    "fido/confusio",
    "sourcehut webhook: ticket tracker maps to repository"
  )
  local issue_envelope = app.backend.webhook_translators.issues(issue_event)
  eq(issue_envelope.type, "issue.opened", "sourcehut webhook: normalized issue type")
  local issue_github_payload = app.backend.webhook_github_translators.issues(issue_event)
  eq(
    issue_github_payload.issue.title,
    "Open the tracker gate",
    "sourcehut webhook: GitHub-shape issue includes issue"
  )
  eq(
    app.backend.webhooks.TICKET_UPDATE(ticket_payload).action,
    "edited",
    "sourcehut webhook: TICKET_UPDATE maps to edited"
  )
  local deleted_issue_event = app.backend.webhooks.TICKET_DELETED({
    data = {
      webhook = { event = "TICKET_DELETED" },
      ticketId = 42,
    },
  })
  eq(deleted_issue_event.action, "deleted", "sourcehut webhook: TICKET_DELETED maps to deleted")
  eq(deleted_issue_event.data.issue.number, 42, "sourcehut webhook: deleted ticket keeps number")

  local label_payload = {
    data = {
      webhook = { event = "LABEL_CREATED", date = "2026-05-02T04:05:06Z" },
      label = {
        id = 6,
        name = "triage",
        backgroundColor = "#00ff00",
        tracker = {
          name = "confusio",
          owner = { canonicalName = "~fido", username = "fido" },
        },
      },
    },
  }
  local label_event = app.backend.webhooks.LABEL_CREATED(label_payload)
  eq(label_event.event, "label", "sourcehut webhook: LABEL_CREATED maps to label")
  eq(label_event.action, "created", "sourcehut webhook: LABEL_CREATED maps to created")
  eq(label_event.data.label.color, "00ff00", "sourcehut webhook: label color strips hash")
  local label_envelope = app.backend.webhook_translators.label(label_event)
  eq(label_envelope.type, "label.created", "sourcehut webhook: normalized label type")
  local label_github_payload = app.backend.webhook_github_translators.label(label_event)
  eq(
    label_github_payload.label.name,
    "triage",
    "sourcehut webhook: GitHub-shape label includes label"
  )
  eq(
    app.backend.webhooks.LABEL_UPDATE(label_payload).action,
    "edited",
    "sourcehut webhook: LABEL_UPDATE maps to edited"
  )
  eq(
    app.backend.webhooks.LABEL_DELETED(label_payload).action,
    "deleted",
    "sourcehut webhook: LABEL_DELETED maps to deleted"
  )

  local comment_event = app.backend.webhooks.EVENT_CREATED({
    data = {
      webhook = { event = "EVENT_CREATED", date = "2026-05-02T05:06:07Z" },
      newEvent = {
        id = 77,
        created = "2026-05-02T05:00:00Z",
        ticket = ticket_payload.data.ticket,
        changes = {
          {
            eventType = "COMMENT",
            author = { canonicalName = "~rob", username = "rob" },
            text = "I found the latch.",
          },
        },
      },
    },
  })
  eq(comment_event.event, "issue_comment", "sourcehut webhook: COMMENT maps to issue_comment")
  eq(comment_event.action, "created", "sourcehut webhook: COMMENT maps to created")
  eq(comment_event.data.comment.body, "I found the latch.", "sourcehut webhook: comment body")
  local comment_github_payload = app.backend.webhook_github_translators.issue_comment(comment_event)
  eq(
    comment_github_payload.comment.body,
    "I found the latch.",
    "sourcehut webhook: GitHub-shape comment includes body"
  )

  local labeled_event = app.backend.webhooks.EVENT_CREATED({
    data = {
      newEvent = {
        id = 78,
        ticket = ticket_payload.data.ticket,
        changes = {
          {
            eventType = "LABEL_ADDED",
            labeler = { canonicalName = "~rob", username = "rob" },
            label = label_payload.data.label,
          },
        },
      },
    },
  })
  eq(labeled_event.event, "issues", "sourcehut webhook: LABEL_ADDED maps to issues")
  eq(labeled_event.action, "labeled", "sourcehut webhook: LABEL_ADDED maps to labeled")
  eq(labeled_event.data.label.name, "triage", "sourcehut webhook: LABEL_ADDED keeps label")

  local closed_event = app.backend.webhooks.EVENT_CREATED({
    data = {
      newEvent = {
        id = 79,
        ticket = ticket_payload.data.ticket,
        changes = {
          {
            eventType = "STATUS_CHANGE",
            editor = { canonicalName = "~rob", username = "rob" },
            oldStatus = "IN_PROGRESS",
            newStatus = "RESOLVED",
          },
        },
      },
    },
  })
  eq(closed_event.action, "closed", "sourcehut webhook: resolved status maps to closed")

  local job_payload = {
    data = {
      webhook = { event = "JOB_UPDATED", date = "2026-05-02T06:07:08Z" },
      repository = {
        id = 272,
        name = "confusio",
        visibility = "PUBLIC",
        owner = { canonicalName = "~fido", username = "fido" },
        HEAD = { name = "refs/heads/main" },
      },
      sender = { canonicalName = "~rob", username = "rob" },
      job = {
        id = 88,
        note = "sourcehut build",
        status = "success",
        commit = "dddddddddddddddddddddddddddddddddddddddd",
        branch = "refs/heads/main",
        url = "https://builds.sr.ht/~fido/job/88",
        created = "2026-05-02T06:00:00Z",
        updated = "2026-05-02T06:05:00Z",
      },
    },
  }
  local job_event = app.backend.webhooks.JOB_UPDATED(job_payload)
  eq(job_event.event, "workflow_run", "sourcehut webhook: JOB_UPDATED maps to workflow_run")
  eq(job_event.action, "completed", "sourcehut webhook: successful job maps to completed")
  eq(
    job_event.data.workflow_run.conclusion,
    "success",
    "sourcehut webhook: successful job conclusion"
  )
  eq(
    job_event.data.workflow_run.head_sha,
    "dddddddddddddddddddddddddddddddddddddddd",
    "sourcehut webhook: job commit maps to head_sha"
  )
  local job_envelope = app.backend.webhook_translators.workflow_run(job_event)
  eq(job_envelope.type, "workflow.run.completed", "sourcehut webhook: normalized workflow_run type")
  local job_github_payload = app.backend.webhook_github_translators.workflow_run(job_event)
  eq(
    job_github_payload.workflow_run.status,
    "completed",
    "sourcehut webhook: GitHub-shape workflow_run includes status"
  )
  eq(
    app.backend.webhooks.JOB_CREATED({
      data = {
        webhook = { event = "JOB_CREATED" },
        job = { id = 89, status = "queued" },
      },
    }).action,
    "requested",
    "sourcehut webhook: JOB_CREATED maps to requested"
  )

  local patchset_payload = {
    data = {
      webhook = { event = "PATCHSET_RECEIVED", date = "2026-05-02T07:08:09Z" },
      repository = {
        id = 272,
        name = "confusio",
        visibility = "PUBLIC",
        owner = { canonicalName = "~fido", username = "fido" },
        HEAD = { name = "refs/heads/main" },
      },
      patchset = {
        id = 17,
        rid = "patchset-rid",
        subject = "Teach sourcehut patchsets",
        coverLetter = "This came in by mail.",
        ref = "patches/v1",
        targetBranch = "main",
        commit = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
        created = "2026-05-02T07:00:00Z",
        updated = "2026-05-02T07:01:00Z",
        url = "https://lists.sr.ht/~fido/confusio/patches/17",
        submitter = { canonicalName = "~rob", username = "rob" },
      },
    },
  }
  local patchset_event = app.backend.webhooks.PATCHSET_RECEIVED(patchset_payload)
  eq(
    patchset_event.event,
    "pull_request",
    "sourcehut webhook: PATCHSET_RECEIVED maps to pull_request"
  )
  eq(patchset_event.action, "opened", "sourcehut webhook: patchset maps to opened")
  eq(
    patchset_event.data.number,
    17,
    "sourcehut webhook: patchset number maps to pull_request number"
  )
  eq(
    patchset_event.data.pull_request.title,
    "Teach sourcehut patchsets",
    "sourcehut webhook: patchset subject maps to pull_request title"
  )
  local patchset_envelope = app.backend.webhook_translators.pull_request(patchset_event)
  eq(patchset_envelope.type, "pull_request.opened", "sourcehut webhook: normalized patchset type")
  local patchset_github_payload =
    app.backend.webhook_github_translators.pull_request(patchset_event)
  eq(
    patchset_github_payload.pull_request.head.ref,
    "patches/v1",
    "sourcehut webhook: GitHub-shape patchset includes head ref"
  )

  app.backend.rest = saved_rest
  app.backend.capabilities = saved_capabilities
  app.backend.webhooks = saved_webhooks
  app.backend.webhook_translators = saved_webhook_translators
  app.backend.webhook_github_translators = saved_webhook_github_translators
  graphql_resolvers = saved_resolvers -- luacheck: globals graphql_resolvers
  config.base_url = saved_base_url
  config.backend = saved_backend
end

-- ============================================================
-- Tuleap webhook handlers
-- ============================================================

do
  local saved_rest = app.backend.rest
  local saved_capabilities = app.backend.capabilities
  local saved_webhooks = app.backend.webhooks
  local saved_webhook_translators = app.backend.webhook_translators
  local saved_webhook_github_translators = app.backend.webhook_github_translators
  local saved_resolvers = graphql_resolvers -- luacheck: globals graphql_resolvers
  local saved_base_url = config.base_url
  local saved_backend = config.backend

  app.backend.rest = {}
  app.backend.capabilities = {}
  app.backend.webhooks = {}
  app.backend.webhook_translators = {}
  app.backend.webhook_github_translators = {}
  graphql_resolvers = {} -- luacheck: globals graphql_resolvers
  config.base_url = ""
  config.backend = "tuleap"
  _real_dofile("backends/tuleap.lua")

  ok(app.backend.webhooks.project_create ~= nil, "tuleap webhook: project_create registered")
  ok(app.backend.webhooks.git_push ~= nil, "tuleap webhook: git_push registered")
  ok(app.backend.webhooks.artifact_create ~= nil, "tuleap webhook: artifact_create registered")
  ok(app.backend.webhooks.artifact_update ~= nil, "tuleap webhook: artifact_update registered")
  ok(
    app.backend.webhook_translators.project ~= nil,
    "tuleap webhook: project translator registered"
  )
  ok(app.backend.webhook_translators.push ~= nil, "tuleap webhook: push translator registered")
  ok(app.backend.webhook_translators.issues ~= nil, "tuleap webhook: issues translator registered")
  ok(
    app.backend.webhook_github_translators.project ~= nil,
    "tuleap webhook: project GitHub translator registered"
  )
  ok(
    app.backend.webhook_github_translators.push ~= nil,
    "tuleap webhook: push GitHub translator registered"
  )
  ok(
    app.backend.webhook_github_translators.issues ~= nil,
    "tuleap webhook: issues GitHub translator registered"
  )

  local function load_tuleap_fixture(name)
    local f = assert(io.open("test/fixtures/webhooks/tuleap/" .. name .. ".json", "rb"))
    local body = f:read("*a")
    f:close()
    return DecodeJson(body)
  end

  local project_event = app.backend.webhooks.project_create(load_tuleap_fixture("project-created"))
  eq(project_event.event, "project", "tuleap webhook: project_create maps to project")
  eq(project_event.action, "created", "tuleap webhook: project_create maps to created")
  eq(project_event.provider, "tuleap", "tuleap webhook: project_create sets provider")
  eq(
    project_event.data.project.name,
    "Hello World",
    "tuleap webhook: project_create keeps project name"
  )
  eq(
    project_event.data.project.path_with_namespace,
    "octocat/hello-world",
    "tuleap webhook: project_create keeps namespace path"
  )
  eq(
    project_event.data.sender.email,
    "alice@example.com",
    "tuleap webhook: project_create maps owner email to sender"
  )
  local project_envelope = app.backend.webhook_translators.project(project_event)
  eq(project_envelope.type, "project.created", "tuleap webhook: normalized project type")
  eq(
    project_envelope.payload.project.name,
    "Hello World",
    "tuleap webhook: normalized project payload includes project"
  )
  local project_github_payload = app.backend.webhook_github_translators.project(project_event)
  eq(project_github_payload.action, "created", "tuleap webhook: GitHub project action")
  eq(
    project_github_payload.project.name,
    "Hello World",
    "tuleap webhook: GitHub project payload includes project"
  )

  local push_event = app.backend.webhooks.git_push(load_tuleap_fixture("push"))
  eq(push_event.event, "push", "tuleap webhook: git_push maps update to push")
  eq(push_event.action, "push", "tuleap webhook: git_push action set")
  eq(push_event.provider, "tuleap", "tuleap webhook: git_push sets provider")
  eq(push_event.data.ref, "refs/heads/main", "tuleap webhook: push keeps full ref")
  eq(push_event.data.repository.name, "hello-world", "tuleap webhook: push maps repository name")
  eq(push_event.data.sender.login, "alice", "tuleap webhook: push maps sender")
  eq(push_event.data.pusher.email, "alice@example.com", "tuleap webhook: push maps pusher")
  local push_envelope = app.backend.webhook_translators.push(push_event)
  eq(push_envelope.type, "push", "tuleap webhook: normalized push uses actionless type")
  local push_github_payload = app.backend.webhook_github_translators.push(push_event)
  eq(push_github_payload.action, nil, "tuleap webhook: GitHub push has no action")
  eq(push_github_payload.ref, "refs/heads/main", "tuleap webhook: GitHub push includes ref")
  eq(
    push_github_payload.pusher.email,
    "alice@example.com",
    "tuleap webhook: GitHub push includes pusher"
  )

  local create_event = app.backend.webhooks.git_push(load_tuleap_fixture("create"))
  eq(create_event.event, "create", "tuleap webhook: zero before maps to create")
  eq(create_event.data.ref, "feature/tuleap-fixtures", "tuleap webhook: create strips branch ref")
  eq(create_event.data.ref_type, "branch", "tuleap webhook: create detects branch ref")
  local create_envelope = app.backend.webhook_translators.create(create_event)
  eq(create_envelope.type, "create", "tuleap webhook: normalized create uses actionless type")
  local create_github_payload = app.backend.webhook_github_translators.create(create_event)
  eq(create_github_payload.ref, "feature/tuleap-fixtures", "tuleap webhook: GitHub create ref")
  eq(create_github_payload.ref_type, "branch", "tuleap webhook: GitHub create ref_type")

  local delete_event = app.backend.webhooks.git_push(load_tuleap_fixture("delete"))
  eq(delete_event.event, "delete", "tuleap webhook: zero after maps to delete")
  eq(delete_event.data.ref, "feature/tuleap-fixtures", "tuleap webhook: delete strips branch ref")
  eq(delete_event.data.ref_type, "branch", "tuleap webhook: delete detects branch ref")

  local tag_create_event = app.backend.webhooks.git_push(load_tuleap_fixture("tag-create"))
  eq(tag_create_event.event, "create", "tuleap webhook: zero before maps tag to create")
  eq(tag_create_event.data.ref, "v1.0.0", "tuleap webhook: tag create strips tag ref")
  eq(tag_create_event.data.ref_type, "tag", "tuleap webhook: tag create detects tag ref")

  local tag_delete_event = app.backend.webhooks.git_push(load_tuleap_fixture("tag-delete"))
  eq(tag_delete_event.event, "delete", "tuleap webhook: zero after maps tag to delete")
  eq(tag_delete_event.data.ref, "v1.0.0", "tuleap webhook: tag delete strips tag ref")
  eq(tag_delete_event.data.ref_type, "tag", "tuleap webhook: tag delete detects tag ref")

  local artifact_created_event =
    app.backend.webhooks.artifact_create(load_tuleap_fixture("artifact-created"))
  eq(artifact_created_event.event, "issues", "tuleap webhook: artifact_create maps to issues")
  eq(artifact_created_event.action, "opened", "tuleap webhook: artifact_create opens issue")
  eq(artifact_created_event.provider, "tuleap", "tuleap webhook: artifact_create sets provider")
  eq(
    artifact_created_event.data.issue.number,
    75291,
    "tuleap webhook: artifact_create maps artifact id to issue number"
  )
  eq(
    artifact_created_event.data.issue.title,
    "Normalize Tuleap webhook payloads",
    "tuleap webhook: artifact_create maps title field"
  )
  eq(
    artifact_created_event.data.issue.body,
    "Tuleap should fan out as a normalized issue event.",
    "tuleap webhook: artifact_create maps description field"
  )
  eq(
    artifact_created_event.data.sender.login,
    "alice",
    "tuleap webhook: artifact_create maps sender"
  )
  local issue_envelope = app.backend.webhook_translators.issues(artifact_created_event)
  eq(issue_envelope.type, "issue.opened", "tuleap webhook: normalized issue type")
  eq(
    issue_envelope.payload.issue.title,
    "Normalize Tuleap webhook payloads",
    "tuleap webhook: normalized issue payload includes issue"
  )
  local issue_github_payload = app.backend.webhook_github_translators.issues(artifact_created_event)
  eq(issue_github_payload.action, "opened", "tuleap webhook: GitHub issue action")
  eq(
    issue_github_payload.issue.number,
    75291,
    "tuleap webhook: GitHub issue payload includes issue"
  )

  local artifact_updated_event =
    app.backend.webhooks.artifact_update(load_tuleap_fixture("artifact-updated"))
  eq(artifact_updated_event.event, "issues", "tuleap webhook: artifact_update maps to issues")
  eq(artifact_updated_event.action, "edited", "tuleap webhook: artifact_update edits issue")
  eq(
    artifact_updated_event.data.issue.number,
    75291,
    "tuleap webhook: artifact_update keeps artifact id"
  )
  eq(
    artifact_updated_event.data.issue.state,
    "open",
    "tuleap webhook: artifact_update maps non-closed status to open"
  )
  eq(artifact_updated_event.data.sender.login, "bob", "tuleap webhook: artifact_update maps sender")

  app.backend.rest = saved_rest
  app.backend.capabilities = saved_capabilities
  app.backend.webhooks = saved_webhooks
  app.backend.webhook_translators = saved_webhook_translators
  app.backend.webhook_github_translators = saved_webhook_github_translators
  graphql_resolvers = saved_resolvers -- luacheck: globals graphql_resolvers
  config.base_url = saved_base_url
  config.backend = saved_backend
end

-- ============================================================
-- RhodeCode webhook handlers
-- ============================================================

do
  local saved_rest = app.backend.rest
  local saved_capabilities = app.backend.capabilities
  local saved_webhooks = app.backend.webhooks
  local saved_webhook_translators = app.backend.webhook_translators
  local saved_webhook_github_translators = app.backend.webhook_github_translators
  local saved_resolvers = graphql_resolvers -- luacheck: globals graphql_resolvers
  local saved_base_url = config.base_url
  local saved_backend = config.backend

  app.backend.rest = {}
  app.backend.capabilities = {}
  app.backend.webhooks = {}
  app.backend.webhook_translators = {}
  app.backend.webhook_github_translators = {}
  graphql_resolvers = {} -- luacheck: globals graphql_resolvers
  config.base_url = "https://rhodecode.example"
  config.backend = "rhodecode"
  _real_dofile("backends/rhodecode.lua")

  ok(app.backend.webhooks.PUSH_HOOK ~= nil, "rhodecode webhook: PUSH_HOOK registered")
  ok(app.backend.webhooks.POST_PUSH ~= nil, "rhodecode webhook: POST_PUSH registered")
  ok(app.backend.webhooks.CREATE_REPO_HOOK ~= nil, "rhodecode webhook: create repo registered")
  ok(app.backend.webhooks.DELETE_REPO_HOOK ~= nil, "rhodecode webhook: delete repo registered")
  ok(app.backend.webhook_translators.push ~= nil, "rhodecode webhook: push translator registered")
  ok(
    app.backend.webhook_github_translators.repository ~= nil,
    "rhodecode webhook: repository GitHub translator registered"
  )

  local function load_rhodecode_fixture(name)
    local f = assert(io.open("test/fixtures/webhooks/rhodecode/" .. name .. ".json", "rb"))
    local body = f:read("*a")
    f:close()
    return DecodeJson(body)
  end

  local push_event = app.backend.webhooks.PUSH_HOOK(load_rhodecode_fixture("push"))
  eq(push_event.event, "push", "rhodecode webhook: PUSH_HOOK update maps to push")
  eq(push_event.action, "push", "rhodecode webhook: push action set")
  eq(push_event.provider, "rhodecode", "rhodecode webhook: push provider set")
  eq(push_event.data.ref, "refs/heads/main", "rhodecode webhook: push keeps full ref")
  eq(
    push_event.data.before,
    "1111111111111111111111111111111111111111",
    "rhodecode webhook: push maps old revision"
  )
  eq(
    push_event.data.after,
    "2222222222222222222222222222222222222222",
    "rhodecode webhook: push maps new revision"
  )
  eq(
    push_event.data.repository.full_name,
    "octocat/hello-world",
    "rhodecode webhook: push maps repository"
  )
  eq(push_event.data.sender.login, "alice", "rhodecode webhook: push maps sender")
  eq(push_event.data.pusher.email, "alice@example.com", "rhodecode webhook: push maps pusher")
  local push_envelope = app.backend.webhook_translators.push(push_event)
  eq(push_envelope.type, "push", "rhodecode webhook: normalized push uses actionless type")
  local push_github_payload = app.backend.webhook_github_translators.push(push_event)
  eq(push_github_payload.action, nil, "rhodecode webhook: GitHub push has no action")
  eq(push_github_payload.ref, "refs/heads/main", "rhodecode webhook: GitHub push includes ref")

  local create_event = app.backend.webhooks.POST_PUSH({
    hook = "POST_PUSH",
    repo_name = "octocat/hello-world",
    username = "alice",
    pushed_revs = { "tag=>v1.2.3" },
  })
  eq(create_event.event, "create", "rhodecode webhook: zero old revision maps to create")
  eq(create_event.data.ref, "v1.2.3", "rhodecode webhook: tag create strips ref prefix")
  eq(create_event.data.ref_type, "tag", "rhodecode webhook: tag create detects ref type")

  local delete_event = app.backend.webhooks.PUSH_HOOK({
    event = "PUSH_HOOK",
    repo = { repo_name = "octocat/hello-world", private = "false" },
    username = "alice",
    ref_updates = {
      {
        ref_name_full = "refs/tags/v0.9.0",
        from_hash = "9999999999999999999999999999999999999999",
        to_hash = "0000000000000000000000000000000000000000",
      },
    },
  })
  eq(delete_event.event, "delete", "rhodecode webhook: zero new revision maps to delete")
  eq(delete_event.data.ref, "v0.9.0", "rhodecode webhook: tag delete strips ref prefix")
  eq(delete_event.data.ref_type, "tag", "rhodecode webhook: tag delete detects ref type")
  eq(
    delete_event.data.repository.visibility,
    "public",
    "rhodecode webhook: string false private maps to public"
  )

  local repo_created = app.backend.webhooks.repository({
    action = "create",
    repo_name = "octocat/new-repo",
    repo_private = "yes",
    created_by = "admin",
  })
  eq(repo_created.event, "repository", "rhodecode webhook: repository action maps event")
  eq(repo_created.action, "created", "rhodecode webhook: repository create normalizes action")
  eq(
    repo_created.data.repository.visibility,
    "private",
    "rhodecode webhook: repository maps private flag"
  )
  eq(repo_created.data.sender.login, "admin", "rhodecode webhook: repository maps sender")
  local repo_created_payload = app.backend.webhook_github_translators.repository(repo_created)
  eq(repo_created_payload.action, "created", "rhodecode webhook: GitHub repository action")
  eq(
    repo_created_payload.repository.full_name,
    "octocat/new-repo",
    "rhodecode webhook: GitHub repository body"
  )

  local repo_deleted = app.backend.webhooks.DELETE_REPO_HOOK({
    repo_name = "octocat/old-repo",
    deleted_by = "admin",
  })
  eq(repo_deleted.action, "deleted", "rhodecode webhook: delete repo hook normalizes action")
  eq(
    repo_deleted.data.repository.full_name,
    "octocat/old-repo",
    "rhodecode webhook: delete repo hook keeps repository"
  )
  local repo_deleted_envelope = app.backend.webhook_translators.repository(repo_deleted)
  eq(
    repo_deleted_envelope.type,
    "repository.deleted",
    "rhodecode webhook: normalized repository includes action"
  )

  local pr_opened =
    app.backend.webhooks.CREATE_PULLREQUEST_HOOK(load_rhodecode_fixture("pull_request-opened"))
  eq(pr_opened.event, "pull_request", "rhodecode webhook: create PR maps event")
  eq(pr_opened.action, "opened", "rhodecode webhook: create PR maps opened action")
  eq(pr_opened.data.number, 7, "rhodecode webhook: PR number")
  eq(pr_opened.data.repository.full_name, "octocat/hello-world", "rhodecode webhook: PR repository")
  eq(pr_opened.data.pull_request.title, "Add webhook fixtures", "rhodecode webhook: PR title")
  eq(pr_opened.data.pull_request.head.ref, "feature/rhodecode", "rhodecode webhook: PR head ref")
  eq(pr_opened.data.pull_request.base.ref, "main", "rhodecode webhook: PR base ref")
  eq(pr_opened.data.pull_request.state, "open", "rhodecode webhook: opened PR state")
  local pr_opened_envelope = app.backend.webhook_translators.pull_request(pr_opened)
  eq(pr_opened_envelope.type, "pull_request.opened", "rhodecode webhook: normalized PR opened type")
  local pr_opened_payload = app.backend.webhook_github_translators.pull_request(pr_opened)
  eq(pr_opened_payload.action, "opened", "rhodecode webhook: GitHub PR opened action")
  eq(
    pr_opened_payload.pull_request.head.label,
    "alice/hello-world:feature/rhodecode",
    "rhodecode webhook: GitHub PR head label"
  )

  local pr_sync = app.backend.webhooks.pull_request({
    action = "update",
    repository = "octocat/hello-world",
    created_by = "alice",
    pull_request_id = 7,
    pull_request = {
      id = 7,
      title = "Add webhook fixtures",
      description = "Updated with another commit.",
      status = "updated",
      owner = "alice",
      org_repo_name = "octocat/hello-world",
      other_repo_name = "alice/hello-world",
      org_ref = "main",
      other_ref = "feature/rhodecode",
      org_rev = "1111111111111111111111111111111111111111",
      other_rev = "2222222222222222222222222222222222222222",
      created_on = "2024-01-15T12:15:00Z",
      updated_on = "2024-01-15T12:20:00Z",
    },
  })
  eq(pr_sync.action, "synchronize", "rhodecode webhook: update maps synchronize action")
  eq(
    pr_sync.data.pull_request.head.sha,
    "2222222222222222222222222222222222222222",
    "rhodecode webhook: PR synchronize maps head sha"
  )
  eq(
    app.backend.webhook_translators.pull_request(pr_sync).type,
    "pull_request.synchronize",
    "rhodecode webhook: normalized PR synchronize type"
  )

  local pr_closed =
    app.backend.webhooks.CLOSE_PULLREQUEST_HOOK(load_rhodecode_fixture("pull_request-closed"))
  eq(pr_closed.action, "closed", "rhodecode webhook: close PR maps closed action")
  eq(pr_closed.data.pull_request.state, "closed", "rhodecode webhook: closed PR state")
  eq(
    pr_closed.data.pull_request.closed_at,
    "2024-01-15T13:30:00Z",
    "rhodecode webhook: closed PR timestamp"
  )

  local pr_merged = app.backend.webhooks.pull_request({
    action = "merged",
    repository = "octocat/hello-world",
    merged_by = "bob",
    pull_request_id = 8,
    pull_request = {
      id = 8,
      title = "Close the loop",
      status = "merged",
      owner = "bob",
      org_repo_name = "octocat/hello-world",
      other_repo_name = "bob/hello-world",
      org_ref = "main",
      other_ref = "cleanup",
      merge_commit_sha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      updated_on = "2024-01-15T13:35:00Z",
    },
  })
  eq(pr_merged.action, "closed", "rhodecode webhook: merged PR maps closed action")
  ok(pr_merged.data.pull_request.merged == true, "rhodecode webhook: merged flag set")
  eq(
    pr_merged.data.pull_request.merged_at,
    "2024-01-15T13:35:00Z",
    "rhodecode webhook: merged timestamp"
  )
  eq(
    pr_merged.data.pull_request.merge_commit_sha,
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "rhodecode webhook: merge commit sha"
  )

  local pr_reopened = app.backend.webhooks.pull_request({
    action = "reopen",
    repository = "octocat/hello-world",
    created_by = "bob",
    pull_request_id = 8,
    pull_request = {
      id = 8,
      title = "Close the loop",
      status = "reopened",
      owner = "bob",
      org_repo_name = "octocat/hello-world",
      other_repo_name = "bob/hello-world",
      org_ref = "main",
      other_ref = "cleanup",
      updated_on = "2024-01-15T13:40:00Z",
    },
  })
  eq(pr_reopened.action, "reopened", "rhodecode webhook: reopen maps reopened action")
  eq(pr_reopened.data.pull_request.state, "open", "rhodecode webhook: reopened PR state")

  app.backend.rest = saved_rest
  app.backend.capabilities = saved_capabilities
  app.backend.webhooks = saved_webhooks
  app.backend.webhook_translators = saved_webhook_translators
  app.backend.webhook_github_translators = saved_webhook_github_translators
  graphql_resolvers = saved_resolvers -- luacheck: globals graphql_resolvers
  config.base_url = saved_base_url
  config.backend = saved_backend
end

-- ============================================================
-- NotABug webhook handlers
-- ============================================================

do
  local saved_rest = app.backend.rest
  local saved_capabilities = app.backend.capabilities
  local saved_webhooks = app.backend.webhooks
  local saved_webhook_translators = app.backend.webhook_translators
  local saved_webhook_github_translators = app.backend.webhook_github_translators
  local saved_resolvers = graphql_resolvers -- luacheck: globals graphql_resolvers
  local saved_base_url = config.base_url
  local saved_backend = config.backend

  app.backend.rest = {}
  app.backend.capabilities = {}
  app.backend.webhooks = {}
  app.backend.webhook_translators = {}
  app.backend.webhook_github_translators = {}
  graphql_resolvers = {} -- luacheck: globals graphql_resolvers
  config.base_url = ""
  config.backend = "notabug"
  _real_dofile("backends/gitea.lua")

  ok(app.backend.webhooks.issues ~= nil, "notabug webhook: issues handler registered")
  ok(app.backend.webhooks.issue_comment ~= nil, "notabug webhook: issue_comment handler registered")
  ok(app.backend.webhooks.pull_request ~= nil, "notabug webhook: pull_request handler registered")
  ok(app.backend.webhooks.push ~= nil, "notabug webhook: push handler registered")
  ok(app.backend.webhooks.release ~= nil, "notabug webhook: release handler registered")
  ok(app.backend.webhooks.label == nil, "notabug webhook: label handler not registered")
  ok(app.backend.webhooks.milestone == nil, "notabug webhook: milestone handler not registered")
  ok(app.backend.webhooks.merge_group == nil, "notabug webhook: merge_group handler not registered")
  ok(app.backend.webhook_translators.issues ~= nil, "notabug webhook: issues translator registered")
  ok(
    app.backend.webhook_translators.label == nil,
    "notabug webhook: label translator not registered"
  )
  ok(
    app.backend.webhook_github_translators.issues ~= nil,
    "notabug webhook: issues GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_github_translators.label == nil,
    "notabug webhook: label GitHub-shape translator not registered"
  )
  ok(
    app.backend.webhook_translators.merge_group == nil,
    "notabug webhook: merge_group translator not registered"
  )

  local issue_event = app.backend.webhooks.issues({
    action = "opened",
    issue = { number = 1, title = "Bug report", updated = "2024-01-15T10:00:00Z" },
    repository = { name = "hello-world", full_name = "octocat/hello-world" },
    sender = { login = "alice" },
  })
  eq(issue_event.provider, "notabug", "notabug webhook: native handler sets provider")
  eq(issue_event.event, "issues", "notabug webhook: issues maps to issues")
  eq(issue_event.action, "opened", "notabug webhook: issues action preserved")

  local issue_envelope = app.backend.webhook_translators.issues(issue_event)
  eq(issue_envelope.type, "issue.opened", "notabug webhook: normalized issue includes action")
  eq(
    issue_envelope.repository.full_name,
    "octocat/hello-world",
    "notabug webhook: normalized issue keeps repository"
  )
  local issue_github_payload = app.backend.webhook_github_translators.issues(issue_event)
  eq(issue_github_payload.action, "opened", "notabug webhook: GitHub-shape issue action")
  eq(issue_github_payload.issue.title, "Bug report", "notabug webhook: GitHub-shape issue body")
  eq(
    issue_github_payload.repository.full_name,
    "octocat/hello-world",
    "notabug webhook: GitHub-shape issue repository"
  )

  app.backend.rest = saved_rest
  app.backend.capabilities = saved_capabilities
  app.backend.webhooks = saved_webhooks
  app.backend.webhook_translators = saved_webhook_translators
  app.backend.webhook_github_translators = saved_webhook_github_translators
  graphql_resolvers = saved_resolvers -- luacheck: globals graphql_resolvers
  config.base_url = saved_base_url
  config.backend = saved_backend
end

-- ============================================================
-- Gitea-family GitHub-shape webhook translators
-- ============================================================

do
  local saved_rest = app.backend.rest
  local saved_capabilities = app.backend.capabilities
  local saved_webhooks = app.backend.webhooks
  local saved_webhook_translators = app.backend.webhook_translators
  local saved_webhook_github_translators = app.backend.webhook_github_translators
  local saved_resolvers = graphql_resolvers -- luacheck: globals graphql_resolvers
  local saved_base_url = config.base_url
  local saved_backend = config.backend

  app.backend.rest = {}
  app.backend.capabilities = {}
  app.backend.webhooks = {}
  app.backend.webhook_translators = {}
  app.backend.webhook_github_translators = {}
  graphql_resolvers = {} -- luacheck: globals graphql_resolvers
  config.base_url = ""
  config.backend = "forgejo"
  _real_dofile("backends/gitea.lua")

  ok(
    app.backend.webhook_github_translators.issues ~= nil,
    "forgejo webhook: issues GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_github_translators.discussion ~= nil,
    "forgejo webhook: discussion GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_github_translators.merge_group ~= nil,
    "forgejo webhook: merge_group GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_github_translators.deploy_key ~= nil,
    "forgejo webhook: deploy_key GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_github_translators.security_and_analysis ~= nil,
    "forgejo webhook: security_and_analysis GitHub-shape translator registered"
  )

  local discussion_event = app.backend.webhooks.discussion({
    action = "labeled",
    discussion = {
      id = 44,
      number = 9,
      title = "Webhook payloads",
      body = "Need GitHub shape.",
      user = { login = "fido" },
      updated = "2026-05-03T10:00:00Z",
    },
    label = { id = 2, name = "triage", color = "5319e7" },
    repository = { name = "confusio", full_name = "rhencke/confusio" },
    sender = { login = "fido" },
  })
  local discussion_github_payload =
    app.backend.webhook_github_translators.discussion(discussion_event)
  eq(discussion_github_payload.action, "labeled", "forgejo webhook: GitHub-shape discussion action")
  eq(
    discussion_github_payload.discussion.title,
    "Webhook payloads",
    "forgejo webhook: GitHub-shape discussion body"
  )
  eq(
    discussion_github_payload.label.name,
    "triage",
    "forgejo webhook: GitHub-shape discussion label"
  )

  local merge_group_event = app.backend.webhooks.merge_group({
    action = "destroyed",
    reason = "dequeued",
    merge_group = {
      head_sha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      head_ref = "gh-readonly-queue/main/pr-1",
      base_sha = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      base_ref = "main",
    },
    repository = { name = "confusio", full_name = "rhencke/confusio" },
    sender = { login = "fido" },
  })
  local merge_group_github_payload =
    app.backend.webhook_github_translators.merge_group(merge_group_event)
  eq(
    merge_group_github_payload.merge_group.head_ref,
    "gh-readonly-queue/main/pr-1",
    "forgejo webhook: GitHub-shape merge_group body"
  )
  eq(
    merge_group_github_payload.reason,
    "dequeued",
    "forgejo webhook: GitHub-shape merge_group reason"
  )

  app.backend.rest = saved_rest
  app.backend.capabilities = saved_capabilities
  app.backend.webhooks = saved_webhooks
  app.backend.webhook_translators = saved_webhook_translators
  app.backend.webhook_github_translators = saved_webhook_github_translators
  graphql_resolvers = saved_resolvers -- luacheck: globals graphql_resolvers
  config.base_url = saved_base_url
  config.backend = saved_backend
end

-- ============================================================
-- GitLab GitHub-shape webhook translators
-- ============================================================

do
  local saved_rest = app.backend.rest
  local saved_capabilities = app.backend.capabilities
  local saved_webhooks = app.backend.webhooks
  local saved_webhook_translators = app.backend.webhook_translators
  local saved_webhook_github_translators = app.backend.webhook_github_translators
  local saved_resolvers = graphql_resolvers -- luacheck: globals graphql_resolvers
  local saved_base_url = config.base_url
  local saved_backend = config.backend

  app.backend.rest = {}
  app.backend.capabilities = {}
  app.backend.webhooks = {}
  app.backend.webhook_translators = {}
  app.backend.webhook_github_translators = {}
  graphql_resolvers = {} -- luacheck: globals graphql_resolvers
  config.base_url = ""
  config.backend = "gitlab"
  _real_dofile("backends/gitlab.lua")

  ok(
    app.backend.webhook_github_translators.issues ~= nil,
    "gitlab webhook: issues GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_github_translators.pull_request ~= nil,
    "gitlab webhook: pull_request GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_github_translators.workflow_run ~= nil,
    "gitlab webhook: workflow_run GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_github_translators.deployment_status ~= nil,
    "gitlab webhook: deployment_status GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_github_translators.code_scanning_alert ~= nil,
    "gitlab webhook: code_scanning_alert GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_github_translators.personal_access_token_request ~= nil,
    "gitlab webhook: personal_access_token_request GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_github_translators.membership ~= nil,
    "gitlab webhook: membership GitHub-shape translator registered"
  )

  local repo = { full_name = "gitlab-org/gitlab", name = "gitlab" }
  local sender = { login = "fido" }
  local issue_event = make_internal_event({
    event = "issues",
    action = "opened",
    provider = "gitlab",
    data = {
      action = "opened",
      issue = { number = 101, title = "Translate GitLab webhooks" },
      repository = repo,
      sender = sender,
    },
  })
  local issue_github_payload = app.backend.webhook_github_translators.issues(issue_event)
  eq(issue_github_payload.action, "opened", "gitlab webhook: GitHub-shape issue action")
  eq(
    issue_github_payload.issue.title,
    "Translate GitLab webhooks",
    "gitlab webhook: GitHub-shape issue body"
  )
  eq(
    issue_github_payload.repository.full_name,
    "gitlab-org/gitlab",
    "gitlab webhook: GitHub-shape issue repository"
  )
  eq(issue_github_payload.sender.login, "fido", "gitlab webhook: GitHub-shape issue sender")

  local pull_request_event = make_internal_event({
    event = "pull_request",
    action = "review_requested",
    provider = "gitlab",
    data = {
      action = "review_requested",
      number = 22,
      pull_request = { number = 22, title = "MR becomes PR" },
      requested_reviewer = { login = "rob" },
      repository = repo,
      sender = sender,
    },
  })
  local pull_request_github_payload =
    app.backend.webhook_github_translators.pull_request(pull_request_event)
  eq(pull_request_github_payload.number, 22, "gitlab webhook: GitHub-shape pull_request number")
  eq(
    pull_request_github_payload.requested_reviewer.login,
    "rob",
    "gitlab webhook: GitHub-shape requested reviewer"
  )

  local workflow_run_event = make_internal_event({
    event = "workflow_run",
    action = "completed",
    provider = "gitlab",
    data = {
      action = "completed",
      workflow_run = { id = 77, status = "completed", conclusion = "success" },
      workflow = { id = 9, name = "test" },
      repository = repo,
      sender = sender,
    },
  })
  local workflow_run_github_payload =
    app.backend.webhook_github_translators.workflow_run(workflow_run_event)
  eq(
    workflow_run_github_payload.workflow_run.conclusion,
    "success",
    "gitlab webhook: GitHub-shape workflow_run body"
  )
  eq(
    workflow_run_github_payload.workflow.name,
    "test",
    "gitlab webhook: GitHub-shape workflow body"
  )

  local alert_event = make_internal_event({
    event = "code_scanning_alert",
    action = "created",
    provider = "gitlab",
    data = {
      action = "created",
      alert = { number = 5, state = "open", rule = { id = "gl-sast" } },
      repository = repo,
      sender = sender,
    },
  })
  local alert_github_payload =
    app.backend.webhook_github_translators.code_scanning_alert(alert_event)
  eq(
    alert_github_payload.alert.rule.id,
    "gl-sast",
    "gitlab webhook: GitHub-shape code scanning alert"
  )

  local membership_event = make_internal_event({
    event = "membership",
    action = "added",
    provider = "gitlab",
    data = {
      action = "added",
      member = { login = "new-member" },
      organization = { login = "gitlab-org" },
      sender = sender,
    },
  })
  local membership_github_payload =
    app.backend.webhook_github_translators.membership(membership_event)
  eq(
    membership_github_payload.member.login,
    "new-member",
    "gitlab webhook: GitHub-shape membership member"
  )
  eq(
    membership_github_payload.organization.login,
    "gitlab-org",
    "gitlab webhook: GitHub-shape membership organization"
  )

  local pat_event = make_internal_event({
    event = "personal_access_token_request",
    action = "created",
    provider = "gitlab",
    data = {
      action = "created",
      personal_access_token_request = { id = 88, reason = "deploy token" },
      organization = { login = "gitlab-org" },
      sender = sender,
    },
  })
  local pat_github_payload =
    app.backend.webhook_github_translators.personal_access_token_request(pat_event, {
      payload = { custom = "override" },
    })
  eq(
    pat_github_payload.personal_access_token_request.id,
    88,
    "gitlab webhook: GitHub-shape personal access token request"
  )
  eq(pat_github_payload.custom, "override", "gitlab webhook: GitHub-shape overrides apply")

  app.backend.rest = saved_rest
  app.backend.capabilities = saved_capabilities
  app.backend.webhooks = saved_webhooks
  app.backend.webhook_translators = saved_webhook_translators
  app.backend.webhook_github_translators = saved_webhook_github_translators
  graphql_resolvers = saved_resolvers -- luacheck: globals graphql_resolvers
  config.base_url = saved_base_url
  config.backend = saved_backend
end

-- ============================================================
-- Azure DevOps GitHub-shape webhook translators
-- ============================================================

do
  local saved_rest = app.backend.rest
  local saved_capabilities = app.backend.capabilities
  local saved_webhooks = app.backend.webhooks
  local saved_webhook_translators = app.backend.webhook_translators
  local saved_webhook_github_translators = app.backend.webhook_github_translators
  local saved_resolvers = graphql_resolvers -- luacheck: globals graphql_resolvers
  local saved_base_url = config.base_url
  local saved_backend = config.backend

  app.backend.rest = {}
  app.backend.capabilities = {}
  app.backend.webhooks = {}
  app.backend.webhook_translators = {}
  app.backend.webhook_github_translators = {}
  graphql_resolvers = {} -- luacheck: globals graphql_resolvers
  config.base_url = ""
  config.backend = "azuredevops"
  _real_dofile("backends/azuredevops.lua")

  ok(
    app.backend.webhook_github_translators.issues ~= nil,
    "azuredevops webhook: issues GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_github_translators.pull_request ~= nil,
    "azuredevops webhook: pull_request GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_github_translators.workflow_run ~= nil,
    "azuredevops webhook: workflow_run GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_github_translators.deployment_status ~= nil,
    "azuredevops webhook: deployment_status GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_github_translators.code_scanning_alert ~= nil,
    "azuredevops webhook: code_scanning_alert GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_github_translators.dependabot_alert ~= nil,
    "azuredevops webhook: dependabot_alert GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_github_translators.secret_scanning_alert ~= nil,
    "azuredevops webhook: secret_scanning_alert GitHub-shape translator registered"
  )

  local issue_event = app.backend.webhooks["workitem.created"]({
    eventType = "workitem.created",
    resource = {
      id = 195,
      fields = {
        ["System.Title"] = "Normalize event payloads",
        ["System.State"] = "Active",
        ["System.Description"] = "One shape for every receiver.",
        ["System.CreatedBy"] = { uniqueName = "alice@example.com", displayName = "Alice" },
        ["System.ChangedBy"] = { uniqueName = "alice@example.com", displayName = "Alice" },
        ["System.CreatedDate"] = "2024-01-15T10:00:00Z",
        ["System.ChangedDate"] = "2024-01-15T10:00:00Z",
      },
    },
    createdDate = "2024-01-15T10:00:00Z",
  })
  local issue_github_payload = app.backend.webhook_github_translators.issues(issue_event)
  eq(issue_github_payload.action, "opened", "azuredevops webhook: GitHub-shape issue action")
  eq(
    issue_github_payload.issue.title,
    "Normalize event payloads",
    "azuredevops webhook: GitHub-shape issue body"
  )
  eq(
    issue_github_payload.sender.login,
    "alice@example.com",
    "azuredevops webhook: GitHub-shape issue sender"
  )

  local repo = {
    id = "repo-id-1",
    name = "confusio",
    remoteUrl = "https://dev.azure.com/rhencke/project/_git/confusio",
    isPrivate = false,
    project = { id = "project-id-1", name = "project" },
  }
  local pull_event = app.backend.webhooks["git.pullrequest.created"]({
    eventType = "git.pullrequest.created",
    resource = {
      pullRequestId = 365,
      title = "Translate Azure hooks",
      description = "Service hooks become GitHub payloads.",
      status = "active",
      sourceRefName = "refs/heads/ado-hooks",
      targetRefName = "refs/heads/main",
      lastMergeSourceCommit = { commitId = "abc123" },
      lastMergeTargetCommit = { commitId = "def456" },
      createdBy = { uniqueName = "fido@example.com", displayName = "Fido" },
      creationDate = "2024-01-15T10:00:00Z",
      repository = repo,
    },
    createdDate = "2024-01-15T10:00:00Z",
  })
  local pull_github_payload = app.backend.webhook_github_translators.pull_request(pull_event)
  eq(pull_github_payload.action, "opened", "azuredevops webhook: GitHub-shape PR action")
  eq(pull_github_payload.number, 365, "azuredevops webhook: GitHub-shape PR number")
  eq(
    pull_github_payload.pull_request.head.ref,
    "ado-hooks",
    "azuredevops webhook: GitHub-shape PR head ref"
  )

  local workflow_event = app.backend.webhooks["build.complete"]({
    eventType = "build.complete",
    resource = {
      id = 101,
      buildNumber = "20240115.1",
      result = "succeeded",
      sourceBranch = "refs/heads/main",
      sourceVersion = "abc123def456",
      queueTime = "2024-01-15T10:00:00Z",
      finishTime = "2024-01-15T10:10:00Z",
      definition = { id = 5, name = "CI Pipeline" },
      repository = repo,
      requestedBy = { uniqueName = "alice@example.com", displayName = "Alice" },
    },
  })
  local workflow_github_payload =
    app.backend.webhook_github_translators.workflow_run(workflow_event)
  eq(
    workflow_github_payload.workflow_run.conclusion,
    "success",
    "azuredevops webhook: GitHub-shape workflow conclusion"
  )
  eq(
    workflow_github_payload.workflow.name,
    "CI Pipeline",
    "azuredevops webhook: GitHub-shape workflow body"
  )

  local deployment_event =
    app.backend.webhooks["ms.azure-devops-release.deployment-completed-event"]({
      eventType = "ms.azure-devops-release.deployment-completed-event",
      resource = {
        deployment = {
          id = 11,
          status = "succeeded",
          completedOn = "2024-01-15T14:10:00Z",
          release = {
            id = 1,
            name = "Release-1",
            releaseDefinition = { id = 7, name = "Fabrikam.CD" },
            project = { id = "proj-id-001", name = "octocat" },
          },
          environment = {
            id = 5,
            name = "Production",
            owner = { displayName = "Alice", uniqueName = "alice@example.com" },
          },
        },
      },
    })
  local deployment_github_payload =
    app.backend.webhook_github_translators.deployment_status(deployment_event)
  eq(
    deployment_github_payload.deployment_status.state,
    "success",
    "azuredevops webhook: GitHub-shape deployment status"
  )
  eq(
    deployment_github_payload.deployment.environment,
    "Production",
    "azuredevops webhook: GitHub-shape deployment body"
  )

  local alert_event = app.backend.webhooks["ms.vss-alerts.alert-created-event"]({
    eventType = "ms.vss-alerts.alert-created-event",
    resource = {
      alertId = 101,
      title = "Path injection",
      repositoryUrl = "https://dev.azure.com/octocat/SecurityProject/_git/hello-world",
      alertType = "code",
      firstSeenDate = "2024-01-15T10:00:00Z",
      state = "active",
      rule = { id = "js/path-injection", name = "Path injection" },
    },
  })
  local alert_github_payload =
    app.backend.webhook_github_translators.code_scanning_alert(alert_event)
  eq(
    alert_github_payload.alert.rule.id,
    "js/path-injection",
    "azuredevops webhook: GitHub-shape code scanning alert"
  )
  eq(
    alert_github_payload.repository.full_name,
    "SecurityProject/hello-world",
    "azuredevops webhook: GitHub-shape alert repository"
  )

  app.backend.rest = saved_rest
  app.backend.capabilities = saved_capabilities
  app.backend.webhooks = saved_webhooks
  app.backend.webhook_translators = saved_webhook_translators
  app.backend.webhook_github_translators = saved_webhook_github_translators
  graphql_resolvers = saved_resolvers -- luacheck: globals graphql_resolvers
  config.base_url = saved_base_url
  config.backend = saved_backend
end

-- ============================================================
-- Bitbucket-family GitHub-shape webhook translators
-- ============================================================

do
  local saved_rest = app.backend.rest
  local saved_capabilities = app.backend.capabilities
  local saved_webhooks = app.backend.webhooks
  local saved_webhook_translators = app.backend.webhook_translators
  local saved_webhook_github_translators = app.backend.webhook_github_translators
  local saved_resolvers = graphql_resolvers -- luacheck: globals graphql_resolvers
  local saved_base_url = config.base_url
  local saved_backend = config.backend

  app.backend.rest = {}
  app.backend.capabilities = {}
  app.backend.webhooks = {}
  app.backend.webhook_translators = {}
  app.backend.webhook_github_translators = {}
  graphql_resolvers = {} -- luacheck: globals graphql_resolvers
  config.base_url = ""
  config.backend = "bitbucket"
  _real_dofile("backends/bitbucket.lua")

  ok(
    app.backend.webhook_github_translators.issues ~= nil,
    "bitbucket webhook: issues GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_github_translators.pull_request ~= nil,
    "bitbucket webhook: pull_request GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_github_translators.workflow_run ~= nil,
    "bitbucket webhook: workflow_run GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_github_translators.fork ~= nil,
    "bitbucket webhook: fork GitHub-shape translator registered"
  )

  local bb_repo = {
    slug = "confusio",
    full_name = "rhencke/confusio",
    owner = { nickname = "rhencke" },
    mainbranch = { name = "main" },
  }
  local issue_event = app.backend.webhooks["issue:created"]({
    actor = { nickname = "fido", display_name = "Fido" },
    repository = bb_repo,
    issue = {
      id = 195,
      title = "Normalize webhook payloads",
      content = { raw = "Fetch once; cache twice." },
      reporter = { nickname = "rob" },
      created_on = "2026-05-03T01:02:03Z",
    },
  })
  local issue_github_payload = app.backend.webhook_github_translators.issues(issue_event)
  eq(issue_github_payload.action, "opened", "bitbucket webhook: GitHub-shape issue action")
  eq(
    issue_github_payload.issue.title,
    "Normalize webhook payloads",
    "bitbucket webhook: GitHub-shape issue body"
  )
  eq(
    issue_github_payload.repository.full_name,
    "rhencke/confusio",
    "bitbucket webhook: GitHub-shape issue repository"
  )
  eq(issue_github_payload.sender.login, "fido", "bitbucket webhook: GitHub-shape sender")

  local pull_event = app.backend.webhooks["pullrequest:created"]({
    actor = { nickname = "fido" },
    repository = bb_repo,
    pullrequest = {
      id = 365,
      title = "Emit Bitbucket payloads",
      author = { nickname = "fido" },
      source = { branch = { name = "bitbucket-shape" }, commit = { hash = "abc123" } },
      destination = { branch = { name = "main" }, commit = { hash = "def456" } },
      created_on = "2026-05-03T02:00:00Z",
      updated_on = "2026-05-03T02:01:00Z",
    },
  })
  local pull_github_payload = app.backend.webhook_github_translators.pull_request(pull_event)
  eq(pull_github_payload.action, "opened", "bitbucket webhook: GitHub-shape PR action")
  eq(pull_github_payload.number, 365, "bitbucket webhook: GitHub-shape PR number")
  eq(
    pull_github_payload.pull_request.title,
    "Emit Bitbucket payloads",
    "bitbucket webhook: GitHub-shape PR body"
  )

  app.backend.rest = saved_rest
  app.backend.capabilities = saved_capabilities
  app.backend.webhooks = saved_webhooks
  app.backend.webhook_translators = saved_webhook_translators
  app.backend.webhook_github_translators = saved_webhook_github_translators
  graphql_resolvers = saved_resolvers -- luacheck: globals graphql_resolvers
  config.base_url = saved_base_url
  config.backend = saved_backend
end

do
  local saved_rest = app.backend.rest
  local saved_capabilities = app.backend.capabilities
  local saved_webhooks = app.backend.webhooks
  local saved_webhook_translators = app.backend.webhook_translators
  local saved_webhook_github_translators = app.backend.webhook_github_translators
  local saved_resolvers = graphql_resolvers -- luacheck: globals graphql_resolvers
  local saved_base_url = config.base_url
  local saved_backend = config.backend

  app.backend.rest = {}
  app.backend.capabilities = {}
  app.backend.webhooks = {}
  app.backend.webhook_translators = {}
  app.backend.webhook_github_translators = {}
  graphql_resolvers = {} -- luacheck: globals graphql_resolvers
  config.base_url = ""
  config.backend = "bitbucket_datacenter"
  _real_dofile("backends/bitbucket_datacenter.lua")

  ok(
    app.backend.webhook_github_translators.pull_request ~= nil,
    "bitbucket_datacenter webhook: pull_request GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_github_translators.status ~= nil,
    "bitbucket_datacenter webhook: status GitHub-shape translator registered"
  )
  ok(
    app.backend.webhook_github_translators.repository ~= nil,
    "bitbucket_datacenter webhook: repository GitHub-shape translator registered"
  )

  local dc_repo = {
    slug = "confusio",
    name = "confusio",
    project = { key = "RH", id = 12 },
    default_branch = "main",
  }
  local dc_pr = {
    id = 365,
    title = "Translate Data Center payloads",
    state = "OPEN",
    author = { user = { name = "fido", displayName = "Fido" } },
    fromRef = { displayId = "bbdc-shape", latestCommit = "abc123", repository = dc_repo },
    toRef = { displayId = "main", latestCommit = "def456", repository = dc_repo },
    createdDate = 1777770000000,
    updatedDate = 1777770060000,
  }
  local dc_pull_event = app.backend.webhooks["pr:opened"]({
    actor = { name = "fido", displayName = "Fido" },
    pullRequest = dc_pr,
  })
  local dc_pull_github_payload = app.backend.webhook_github_translators.pull_request(dc_pull_event)
  eq(
    dc_pull_github_payload.action,
    "opened",
    "bitbucket_datacenter webhook: GitHub-shape PR action"
  )
  eq(
    dc_pull_github_payload.repository.full_name,
    "RH/confusio",
    "bitbucket_datacenter webhook: GitHub-shape repository"
  )
  eq(
    dc_pull_github_payload.pull_request.title,
    "Translate Data Center payloads",
    "bitbucket_datacenter webhook: GitHub-shape PR body"
  )

  local dc_status_event = app.backend.webhooks["build:status_created"]({
    actor = { name = "fido" },
    repository = dc_repo,
    commit = { id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" },
    buildStatus = {
      state = "SUCCESSFUL",
      key = "test",
      description = "Tests passed",
      url = "https://ci.example.test/build/1",
      createdDate = 1777770000000,
    },
  })
  local dc_status_github_payload = app.backend.webhook_github_translators.status(dc_status_event)
  eq(
    dc_status_github_payload.state,
    "success",
    "bitbucket_datacenter webhook: GitHub-shape status state"
  )
  eq(
    dc_status_github_payload.sha,
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "bitbucket_datacenter webhook: GitHub-shape status sha"
  )

  app.backend.rest = saved_rest
  app.backend.capabilities = saved_capabilities
  app.backend.webhooks = saved_webhooks
  app.backend.webhook_translators = saved_webhook_translators
  app.backend.webhook_github_translators = saved_webhook_github_translators
  graphql_resolvers = saved_resolvers -- luacheck: globals graphql_resolvers
  config.base_url = saved_base_url
  config.backend = saved_backend
end

-- ============================================================
-- make_webhook_receiver
-- ============================================================

ok(type(make_webhook_receiver) == "function", "make_webhook_receiver: exported as global function")
ok(type(app.webhook_receiver) == "function", "app.webhook_receiver: installed on app by .init.lua")

do
  -- Helper: call app.webhook_receiver() with stubbed HTTP context and return status.
  local function call_webhook(opts)
    local saved_config = app.config
    local configured_backend = opts.configured_backend
      or (opts.path or ""):match("^/webhooks/([^/]+)$")
      or saved_config.backend
    app.config = {
      backend = configured_backend,
      base_url = saved_config.base_url,
      webhook_secrets = saved_config.webhook_secrets or {},
    }
    reset_request(opts)
    reset_response()
    app.webhook_receiver()
    local status = _last_status
    app.config = saved_config
    return status
  end

  -- 404 for unknown backend
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/notabackend",
      headers = { ["Content-Type"] = "application/json" },
      body = "{}",
    }),
    404,
    "webhook_receiver: unknown backend → 404"
  )

  -- 404 for trailing path segment
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/gitea/extra",
      headers = { ["Content-Type"] = "application/json" },
      body = "{}",
    }),
    404,
    "webhook_receiver: extra path segment → 404"
  )

  -- 404 for known providers that do not match the configured provider.
  local _mismatch_logs = {}
  local _real_Log = Log
  Log = function(level, msg) -- luacheck: globals Log
    _mismatch_logs[#_mismatch_logs + 1] = { level = level, msg = msg }
  end
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/gitlab",
      configured_backend = "gitea",
      headers = {
        ["Content-Type"] = "application/json",
        ["X-Gitlab-Event"] = "Issue Hook",
      },
      body = "{}",
    }),
    404,
    "webhook_receiver: provider mismatch → 404"
  )
  ok(#_mismatch_logs == 1, "webhook_receiver: provider mismatch is logged")
  eq(_mismatch_logs[1].level, kLogWarn, "webhook_receiver: provider mismatch logs at kLogWarn") -- luacheck: globals kLogWarn
  ok(
    _mismatch_logs[1].msg:find("configured_provider=gitea", 1, true) ~= nil,
    "webhook_receiver: provider mismatch log includes configured provider"
  )
  ok(
    _mismatch_logs[1].msg:find("requested_provider=gitlab", 1, true) ~= nil,
    "webhook_receiver: provider mismatch log includes requested provider"
  )
  Log = _real_Log

  -- 405 for non-POST method
  eq(
    call_webhook({
      method = "GET",
      path = "/webhooks/gitea",
      headers = { ["Content-Type"] = "application/json" },
      body = "{}",
    }),
    405,
    "webhook_receiver: non-POST → 405"
  )

  -- 400 for wrong Content-Type
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/gitea",
      headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
      body = "",
    }),
    400,
    "webhook_receiver: non-JSON Content-Type → 400"
  )
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/tuleap",
      headers = { ["Content-Type"] = "text/plain" },
      body = "",
    }),
    400,
    "webhook_receiver: unsupported Tuleap Content-Type → 400"
  )

  -- 400 for missing Content-Type
  eq(
    call_webhook({ method = "POST", path = "/webhooks/gitea", headers = {}, body = "{}" }),
    400,
    "webhook_receiver: missing Content-Type → 400"
  )

  -- With no secret configured (trust-the-network) and no handlers, 422
  -- because no event-type header is set for gitea.
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/gitea",
      headers = { ["Content-Type"] = "application/json" },
      body = "{}",
    }),
    422,
    "webhook_receiver: no X-Gitea-Event header → 422 missing event"
  )

  -- 422 when event-type header present but no handler registered
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/gitea",
      headers = {
        ["Content-Type"] = "application/json",
        ["X-Gitea-Event"] = "push",
      },
      body = "{}",
    }),
    422,
    "webhook_receiver: known event header but no handler → 422"
  )

  -- 200 when handler is registered and succeeds
  local saved_webhooks = app.backend.webhooks
  app.backend.webhooks = {
    push = function(_payload)
      return { event = "push" }, nil
    end,
  }
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/gitea",
      headers = {
        ["Content-Type"] = "application/json",
        ["X-Gitea-Event"] = "push",
      },
      body = '{"ref":"refs/heads/main"}',
    }),
    200,
    "webhook_receiver: registered handler succeeds → 200"
  )

  -- Tuleap natively sends application/x-www-form-urlencoded with a payload
  -- field containing the JSON webhook body.
  local tuleap_payload_seen = nil
  app.backend.webhooks = {
    ["test-event"] = function(payload)
      tuleap_payload_seen = payload
      return { event = "repository" }, nil
    end,
  }
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/tuleap",
      headers = {
        ["Content-Type"] = "application/x-www-form-urlencoded; charset=utf-8",
      },
      body = "payload=%7B%22eventType%22%3A%22test-event%22%2C%22message%22%3A%22hello+world+%26+100%25%22%7D&ignored=1",
    }),
    200,
    "webhook_receiver: tuleap form payload succeeds → 200"
  )
  eq(
    tuleap_payload_seen and tuleap_payload_seen.message,
    "hello world & 100%",
    "webhook_receiver: tuleap form payload is URL-decoded before JSON parse"
  )
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/tuleap",
      headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
      body = "not_payload=%7B%7D",
    }),
    400,
    "webhook_receiver: tuleap form without payload → 400"
  )
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/tuleap",
      headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
      body = "payload=%7B%22eventType%22%3A%22test-event%22%7",
    }),
    400,
    "webhook_receiver: tuleap malformed form encoding → 400"
  )
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/tuleap",
      headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
      body = "payload=not-json",
    }),
    400,
    "webhook_receiver: tuleap form payload with invalid JSON → 400"
  )

  app.backend.webhooks = {
    project_create = function(payload)
      tuleap_payload_seen = payload
      return { event = "project" }, nil
    end,
  }
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/tuleap",
      headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
      body = "payload=%7B%22event_name%22%3A%22project_create%22%2C%22project_id%22%3A126%7D",
    }),
    200,
    "webhook_receiver: tuleap event_name project_create handler succeeds → 200"
  )
  eq(
    tuleap_payload_seen and tuleap_payload_seen.project_id,
    126,
    "webhook_receiver: tuleap project payload is dispatched intact"
  )

  app.backend.webhooks = {
    git_push = function(payload)
      tuleap_payload_seen = payload
      return { event = "push" }, nil
    end,
  }
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/tuleap",
      headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
      body = "payload=%7B%22ref%22%3A%22refs%2Fheads%2Fmain%22%2C%22before%22%3A%221111%22%2C%22after%22%3A%222222%22%2C%22repository%22%3A%7B%22id%22%3A%22123%22%7D%7D",
    }),
    200,
    "webhook_receiver: tuleap git push shape infers git_push → 200"
  )
  eq(
    tuleap_payload_seen and tuleap_payload_seen.ref,
    "refs/heads/main",
    "webhook_receiver: tuleap git payload is dispatched intact"
  )

  app.backend.webhooks = {
    artifact_create = function(_payload)
      return { event = "issues", action = "opened" }, nil
    end,
    artifact_update = function(_payload)
      return { event = "issues", action = "edited" }, nil
    end,
  }
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/tuleap",
      headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
      body = "payload=%7B%22id%22%3A182%2C%22action%22%3A%22create%22%2C%22current%22%3A%7B%22id%22%3A355743%7D%7D",
    }),
    200,
    "webhook_receiver: tuleap tracker create infers artifact_create → 200"
  )
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/tuleap",
      headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
      body = "payload=%7B%22id%22%3A182%2C%22action%22%3A%22update%22%2C%22current%22%3A%7B%22id%22%3A355743%7D%2C%22previous%22%3A%7B%22id%22%3A355742%7D%7D",
    }),
    200,
    "webhook_receiver: tuleap tracker update infers artifact_update → 200"
  )

  -- Gogs-family backends use their own event-type header, not X-Gitea-Event.
  app.backend.webhooks = {
    push = function(_payload)
      return { event = "push" }, nil
    end,
  }
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/gogs",
      headers = {
        ["Content-Type"] = "application/json",
        ["X-Gogs-Event"] = "push",
      },
      body = '{"ref":"refs/heads/main"}',
    }),
    200,
    "webhook_receiver: gogs X-Gogs-Event handler succeeds → 200"
  )
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/gogs",
      headers = {
        ["Content-Type"] = "application/json",
        ["X-Gitea-Event"] = "push",
      },
      body = '{"ref":"refs/heads/main"}',
    }),
    422,
    "webhook_receiver: gogs ignores X-Gitea-Event → 422"
  )
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/notabug",
      headers = {
        ["Content-Type"] = "application/json",
        ["X-Gogs-Event"] = "push",
      },
      body = '{"ref":"refs/heads/main"}',
    }),
    200,
    "webhook_receiver: notabug X-Gogs-Event handler succeeds → 200"
  )
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/notabug",
      headers = {
        ["Content-Type"] = "application/json",
        ["X-Gitea-Event"] = "push",
      },
      body = '{"ref":"refs/heads/main"}',
    }),
    422,
    "webhook_receiver: notabug ignores X-Gitea-Event → 422"
  )

  -- Launchpad uses X-Launchpad-Event-Type.
  app.backend.webhooks = {
    ["git:push:0.1"] = function(_payload)
      return { event = "push" }, nil
    end,
  }
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/launchpad",
      headers = {
        ["Content-Type"] = "application/json",
        ["X-Launchpad-Event-Type"] = "git:push:0.1",
      },
      body = "{}",
    }),
    200,
    "webhook_receiver: launchpad X-Launchpad-Event-Type handler succeeds → 200"
  )

  -- Kallithea embeds its event name in the JSON body.
  app.backend.webhooks = {
    push = function(_payload)
      return { event = "push" }, nil
    end,
  }
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/kallithea",
      headers = { ["Content-Type"] = "application/json" },
      body = '{"event":"push"}',
    }),
    200,
    "webhook_receiver: kallithea root event handler succeeds → 200"
  )
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/kallithea",
      headers = { ["Content-Type"] = "application/json" },
      body = '{"data":{"event_type":"push"}}',
    }),
    200,
    "webhook_receiver: kallithea nested data.event_type handler succeeds → 200"
  )
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/kallithea",
      headers = { ["Content-Type"] = "application/json" },
      body = '{"payload":{"hook_type":"push"}}',
    }),
    200,
    "webhook_receiver: kallithea nested payload.hook_type handler succeeds → 200"
  )

  -- Radicle CI adapter requests embed the event family in the JSON body.
  app.backend.webhooks = {
    push = function(_payload)
      return { event = "push" }, nil
    end,
    patch = function(_payload)
      return { event = "pull_request" }, nil
    end,
  }
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/radicle",
      headers = { ["Content-Type"] = "application/json" },
      body = '{"request":"trigger","version":1,"event_type":"push"}',
    }),
    200,
    "webhook_receiver: radicle event_type push handler succeeds → 200"
  )
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/radicle",
      headers = { ["Content-Type"] = "application/json" },
      body = '{"request":"trigger","version":1,"event_type":"patch"}',
    }),
    200,
    "webhook_receiver: radicle event_type patch handler succeeds → 200"
  )

  -- Sourcehut GraphQL webhooks can embed the event name under data.webhook.
  app.backend.webhooks = {
    push = function(_payload)
      return { event = "push" }, nil
    end,
    ["patchset:created"] = function(_payload)
      return { event = "pull_request" }, nil
    end,
  }
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/sourcehut",
      headers = { ["Content-Type"] = "application/json" },
      body = '{"event":"push"}',
    }),
    200,
    "webhook_receiver: sourcehut root event handler succeeds → 200"
  )
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/sourcehut",
      headers = { ["Content-Type"] = "application/json" },
      body = '{"webhook":{"event":"push"}}',
    }),
    200,
    "webhook_receiver: sourcehut webhook.event handler succeeds → 200"
  )
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/sourcehut",
      headers = { ["Content-Type"] = "application/json" },
      body = '{"data":{"webhook":{"event":"patchset:created"}}}',
    }),
    200,
    "webhook_receiver: sourcehut data.webhook.event handler succeeds → 200"
  )

  -- Phabricator embeds the object family in object.type or the PHID prefix.
  app.backend.webhooks = {
    TASK = function(_payload)
      return { event = "issues" }, nil
    end,
  }
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/phabricator",
      headers = { ["Content-Type"] = "application/json" },
      body = '{"object":{"type":"TASK","phid":"PHID-TASK-abcd"}}',
    }),
    200,
    "webhook_receiver: phabricator object.type handler succeeds → 200"
  )
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/phabricator",
      headers = { ["Content-Type"] = "application/json" },
      body = '{"object":{"phid":"PHID-TASK-abcd"}}',
    }),
    200,
    "webhook_receiver: phabricator object PHID prefix handler succeeds → 200"
  )

  -- 422 when handler returns nil (normalisation failed)
  app.backend.webhooks = {
    push = function(_payload)
      return nil, "bad payload"
    end,
  }
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/gitea",
      headers = {
        ["Content-Type"] = "application/json",
        ["X-Gitea-Event"] = "push",
      },
      body = '{"ref":"refs/heads/main"}',
    }),
    422,
    "webhook_receiver: handler returns nil → 422"
  )

  -- 401 when secret is configured and X-Gitea-Signature is absent.
  -- (GetCryptoHash stub returns aaa…; absent header → verify_signature returns false.)
  app.backend.webhooks = {}
  local saved_config = app.config
  app.config = { backend = "gitea", base_url = "", webhook_secrets = { gitea = "mysecret" } }
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/gitea",
      headers = { ["Content-Type"] = "application/json" },
      body = "{}",
    }),
    401,
    "webhook_receiver: secret set but no signature header → 401"
  )
  app.config = saved_config

  app.backend.webhooks = saved_webhooks

  -- make_dispatcher routes /webhooks/* to the receiver, bypassing auth.
  -- Simulate allow_anonymous=false with no Authorization header: a REST path
  -- gets 401, but a webhook path is handled by webhook_receiver (not blocked).
  local saved_anon = app.allow_anonymous
  local saved_dispatch_config = app.config
  app.config = { backend = "gitea", base_url = "", webhook_secrets = {} }
  app.allow_anonymous = false
  -- REST path with no auth → 401
  reset_request({ method = "GET", path = "/repos/alice/myrepo", headers = {}, body = nil })
  reset_response()
  OnHttpRequest()
  eq(_last_status, 401, "dispatcher: REST path with no auth and allow_anonymous=false → 401")

  -- Webhook path with no auth header → reaches webhook_receiver (not blocked by auth gate).
  -- It gets 422 because no event-type header is set, which proves auth was bypassed.
  reset_request({
    method = "POST",
    path = "/webhooks/gitea",
    headers = { ["Content-Type"] = "application/json" },
    body = "{}",
  })
  reset_response()
  OnHttpRequest()
  eq(_last_status, 422, "dispatcher: /webhooks/* bypasses auth gate (allow_anonymous=false)")

  app.allow_anonymous = saved_anon
  app.config = saved_dispatch_config
end

-- ============================================================
-- verify_signature: comprehensive per-backend tests
--
-- Covers all 24 backends in KNOWN_BACKENDS.  For each:
--   (a) trust-the-network (no secret configured) → not 401
--   (b) valid credential/signature → not 401
--   (c) bad credential/signature → 401
--   (d) missing header/token → 401
-- Pagure gets extra cases for its dual-header scheme.
-- Kallithea gets extra cases for its body-embedded secret.
-- codecommit/sourcehut get both trust-the-network
-- and "secret configured → always 401" cases.
-- ============================================================
do
  -- GetCryptoHash stub always returns 32 bytes of 0xaa.
  -- to_hex() converts that to 64 lowercase 'a' characters.
  local STUB_HEX = string.rep("aa", 32)
  local SECRET = "mysecret"

  -- Call the webhook receiver for `backend` with the given extra headers and
  -- body.  `secrets` controls app.config.webhook_secrets.
  local function call_sig(backend, extra_headers, body, secrets)
    local saved_config = app.config
    app.config = {
      backend = backend,
      base_url = "",
      webhook_secrets = secrets or {},
    }
    local h = { ["Content-Type"] = "application/json" }
    for k, v in pairs(extra_headers or {}) do
      h[k] = v
    end
    reset_request({
      method = "POST",
      path = "/webhooks/" .. backend,
      headers = h,
      body = body or "{}",
    })
    reset_response()
    app.webhook_receiver()
    local status = _last_status
    app.config = saved_config
    return status
  end

  -- Convenience wrappers
  local function no_secret(backend, hdrs, body)
    return call_sig(backend, hdrs, body, {})
  end
  local function with_secret(backend, hdrs, body)
    return call_sig(backend, hdrs, body, { [backend] = SECRET })
  end

  -- ── HMAC-SHA256 / no prefix: gitea family (X-Gitea-Signature)
  for _, be in ipairs({ "gitea", "forgejo", "codeberg" }) do
    ok(no_secret(be, {}) ~= 401, "verify_signature " .. be .. ": no secret → not 401")
    ok(
      with_secret(be, { ["X-Gitea-Signature"] = STUB_HEX }) ~= 401,
      "verify_signature " .. be .. ": valid X-Gitea-Signature → not 401"
    )
    eq(
      with_secret(be, { ["X-Gitea-Signature"] = "deadbeef" }),
      401,
      "verify_signature " .. be .. ": bad X-Gitea-Signature → 401"
    )
    eq(with_secret(be, {}), 401, "verify_signature " .. be .. ": missing X-Gitea-Signature → 401")
  end

  -- ── HMAC-SHA256 / no prefix: Gogs family (X-Gogs-Signature)
  for _, be in ipairs({ "gogs", "notabug" }) do
    ok(no_secret(be, {}) ~= 401, "verify_signature " .. be .. ": no secret → not 401")
    ok(
      with_secret(be, { ["X-Gogs-Signature"] = STUB_HEX }) ~= 401,
      "verify_signature " .. be .. ": valid X-Gogs-Signature → not 401"
    )
    eq(
      with_secret(be, { ["X-Gogs-Signature"] = "deadbeef" }),
      401,
      "verify_signature " .. be .. ": bad X-Gogs-Signature → 401"
    )
    eq(with_secret(be, {}), 401, "verify_signature " .. be .. ": missing X-Gogs-Signature → 401")
  end

  -- ── Verbatim shared token: gitlab (X-Gitlab-Token)
  ok(no_secret("gitlab", {}) ~= 401, "verify_signature gitlab: no secret → not 401")
  ok(
    with_secret("gitlab", { ["X-Gitlab-Token"] = SECRET }) ~= 401,
    "verify_signature gitlab: valid X-Gitlab-Token → not 401"
  )
  eq(
    with_secret("gitlab", { ["X-Gitlab-Token"] = "wrongtoken" }),
    401,
    "verify_signature gitlab: bad X-Gitlab-Token → 401"
  )
  eq(with_secret("gitlab", {}), 401, "verify_signature gitlab: missing X-Gitlab-Token → 401")

  -- ── HMAC-SHA256 / sha256= prefix: bitbucket + bitbucket_datacenter (X-Hub-Signature)
  for _, be in ipairs({ "bitbucket", "bitbucket_datacenter" }) do
    ok(no_secret(be, {}) ~= 401, "verify_signature " .. be .. ": no secret → not 401")
    ok(
      with_secret(be, { ["X-Hub-Signature"] = "sha256=" .. STUB_HEX }) ~= 401,
      "verify_signature " .. be .. ": valid X-Hub-Signature sha256= → not 401"
    )
    eq(
      with_secret(be, { ["X-Hub-Signature"] = "sha256=deadbeef" }),
      401,
      "verify_signature " .. be .. ": bad X-Hub-Signature → 401"
    )
    eq(with_secret(be, {}), 401, "verify_signature " .. be .. ": missing X-Hub-Signature → 401")
  end

  -- ── HMAC-SHA1 / sha1= prefix: gitbucket + launchpad (X-Hub-Signature)
  for _, be in ipairs({ "gitbucket", "launchpad" }) do
    ok(no_secret(be, {}) ~= 401, "verify_signature " .. be .. ": no secret → not 401")
    ok(
      with_secret(be, { ["X-Hub-Signature"] = "sha1=" .. STUB_HEX }) ~= 401,
      "verify_signature " .. be .. ": valid X-Hub-Signature sha1= → not 401"
    )
    eq(
      with_secret(be, { ["X-Hub-Signature"] = "sha1=deadbeef" }),
      401,
      "verify_signature " .. be .. ": bad X-Hub-Signature → 401"
    )
    eq(with_secret(be, {}), 401, "verify_signature " .. be .. ": missing X-Hub-Signature → 401")
  end

  -- ── HMAC-SHA256 / no prefix: phabricator (X-Phabricator-Webhook-Signature)
  ok(no_secret("phabricator", {}) ~= 401, "verify_signature phabricator: no secret → not 401")
  ok(
    with_secret("phabricator", { ["X-Phabricator-Webhook-Signature"] = STUB_HEX }) ~= 401,
    "verify_signature phabricator: valid X-Phabricator-Webhook-Signature → not 401"
  )
  eq(
    with_secret("phabricator", { ["X-Phabricator-Webhook-Signature"] = "deadbeef" }),
    401,
    "verify_signature phabricator: bad X-Phabricator-Webhook-Signature → 401"
  )
  eq(
    with_secret("phabricator", {}),
    401,
    "verify_signature phabricator: missing X-Phabricator-Webhook-Signature → 401"
  )

  -- ── Pagure: dual-header scheme (X-Pagure-Signature-256 / X-Pagure-Signature)
  -- Prefers SHA-256; falls back to SHA-512; both must verify when both present.
  ok(no_secret("pagure", {}) ~= 401, "verify_signature pagure: no secret → not 401")
  ok(
    with_secret("pagure", { ["X-Pagure-Signature-256"] = STUB_HEX }) ~= 401,
    "verify_signature pagure: valid sig256 only → not 401"
  )
  ok(
    with_secret("pagure", { ["X-Pagure-Signature"] = STUB_HEX }) ~= 401,
    "verify_signature pagure: valid sig512 only → not 401"
  )
  ok(with_secret("pagure", {
    ["X-Pagure-Signature-256"] = STUB_HEX,
    ["X-Pagure-Signature"] = STUB_HEX,
  }) ~= 401, "verify_signature pagure: both sig256+sig512 valid → not 401")
  eq(
    with_secret("pagure", { ["X-Pagure-Signature-256"] = "bad" }),
    401,
    "verify_signature pagure: bad sig256 → 401"
  )
  eq(
    with_secret("pagure", { ["X-Pagure-Signature"] = "bad" }),
    401,
    "verify_signature pagure: bad sig512 → 401"
  )
  eq(
    with_secret("pagure", {
      ["X-Pagure-Signature-256"] = STUB_HEX,
      ["X-Pagure-Signature"] = "bad",
    }),
    401,
    "verify_signature pagure: sig256 valid but sig512 bad → 401"
  )
  eq(with_secret("pagure", {}), 401, "verify_signature pagure: no signature headers → 401")

  -- ── Verbatim shared token: harness (X-Harness-Token)
  ok(no_secret("harness", {}) ~= 401, "verify_signature harness: no secret → not 401")
  ok(
    with_secret("harness", { ["X-Harness-Token"] = SECRET }) ~= 401,
    "verify_signature harness: valid X-Harness-Token → not 401"
  )
  eq(
    with_secret("harness", { ["X-Harness-Token"] = "bad" }),
    401,
    "verify_signature harness: bad X-Harness-Token → 401"
  )
  eq(with_secret("harness", {}), 401, "verify_signature harness: missing X-Harness-Token → 401")

  -- ── OneDev: X-OneDev-Signature, verbatim shared token
  ok(no_secret("onedev", {}) ~= 401, "verify_signature onedev: no secret → not 401")
  ok(
    with_secret("onedev", { ["X-OneDev-Signature"] = SECRET }) ~= 401,
    "verify_signature onedev: valid X-OneDev-Signature → not 401"
  )
  eq(
    with_secret("onedev", { ["X-OneDev-Signature"] = "badtoken" }),
    401,
    "verify_signature onedev: bad X-OneDev-Signature → 401"
  )
  eq(
    with_secret("onedev", { ["Authorization"] = "Bearer " .. SECRET }),
    401,
    "verify_signature onedev: Authorization header is ignored → 401"
  )
  eq(with_secret("onedev", {}), 401, "verify_signature onedev: missing X-OneDev-Signature → 401")

  -- ── Verbatim Authorization header: radicle (raw token, no prefix)
  ok(no_secret("radicle", {}) ~= 401, "verify_signature radicle: no secret → not 401")
  ok(
    with_secret("radicle", { ["Authorization"] = SECRET }) ~= 401,
    "verify_signature radicle: valid Authorization → not 401"
  )
  eq(
    with_secret("radicle", { ["Authorization"] = "bad" }),
    401,
    "verify_signature radicle: bad Authorization → 401"
  )
  eq(with_secret("radicle", {}), 401, "verify_signature radicle: missing Authorization → 401")

  -- ── Gerrit: Authorization header as raw token, Bearer token, or Basic creds
  ok(no_secret("gerrit", {}) ~= 401, "verify_signature gerrit: no secret → not 401")
  ok(
    with_secret("gerrit", { ["Authorization"] = SECRET }) ~= 401,
    "verify_signature gerrit: valid raw Authorization → not 401"
  )
  ok(
    with_secret("gerrit", { ["Authorization"] = "Bearer " .. SECRET }) ~= 401,
    "verify_signature gerrit: valid Bearer token → not 401"
  )
  ok(
    with_secret("gerrit", { ["Authorization"] = "bearer " .. SECRET }) ~= 401,
    "verify_signature gerrit: Bearer scheme is case-insensitive → not 401"
  )
  ok(
    with_secret("gerrit", { ["Authorization"] = "Basic " .. SECRET }) ~= 401,
    "verify_signature gerrit: valid Basic creds → not 401"
  )
  ok(
    with_secret("gerrit", { ["Authorization"] = "basic " .. SECRET }) ~= 401,
    "verify_signature gerrit: Basic scheme is case-insensitive → not 401"
  )
  eq(
    with_secret("gerrit", { ["Authorization"] = "bad" }),
    401,
    "verify_signature gerrit: bad raw Authorization → 401"
  )
  eq(
    with_secret("gerrit", { ["Authorization"] = "Bearer bad" }),
    401,
    "verify_signature gerrit: bad Bearer token → 401"
  )
  eq(
    with_secret("gerrit", { ["Authorization"] = "Basic bad" }),
    401,
    "verify_signature gerrit: bad Basic creds → 401"
  )
  eq(with_secret("gerrit", {}), 401, "verify_signature gerrit: missing Authorization → 401")

  -- ── Verbatim shared token: gitblit (X-Gitblit-Token)
  ok(no_secret("gitblit", {}) ~= 401, "verify_signature gitblit: no secret → not 401")
  ok(
    with_secret("gitblit", { ["X-Gitblit-Token"] = SECRET }) ~= 401,
    "verify_signature gitblit: valid X-Gitblit-Token → not 401"
  )
  eq(
    with_secret("gitblit", { ["X-Gitblit-Token"] = "bad" }),
    401,
    "verify_signature gitblit: bad X-Gitblit-Token → 401"
  )
  eq(with_secret("gitblit", {}), 401, "verify_signature gitblit: missing X-Gitblit-Token → 401")

  -- ── Verbatim shared token: rhodecode (X-RhodeCode-Signature)
  ok(no_secret("rhodecode", {}) ~= 401, "verify_signature rhodecode: no secret → not 401")
  ok(
    with_secret("rhodecode", { ["X-RhodeCode-Signature"] = SECRET }) ~= 401,
    "verify_signature rhodecode: valid X-RhodeCode-Signature → not 401"
  )
  eq(
    with_secret("rhodecode", { ["X-RhodeCode-Signature"] = "bad" }),
    401,
    "verify_signature rhodecode: bad X-RhodeCode-Signature → 401"
  )
  eq(
    with_secret("rhodecode", {}),
    401,
    "verify_signature rhodecode: missing X-RhodeCode-Signature → 401"
  )

  -- ── SourceForge / Allura: X-Allura-Signature, HMAC-SHA1, sha1= prefix
  ok(no_secret("sourceforge", {}) ~= 401, "verify_signature sourceforge: no secret → not 401")
  ok(
    with_secret("sourceforge", { ["X-Allura-Signature"] = "sha1=" .. STUB_HEX }) ~= 401,
    "verify_signature sourceforge: valid X-Allura-Signature → not 401"
  )
  eq(
    with_secret("sourceforge", { ["X-Allura-Signature"] = "sha1=deadbeef" }),
    401,
    "verify_signature sourceforge: bad X-Allura-Signature → 401"
  )
  eq(
    with_secret("sourceforge", {}),
    401,
    "verify_signature sourceforge: missing X-Allura-Signature → 401"
  )

  -- ── Verbatim shared token: tuleap (X-Tuleap-Webhook-Secret)
  ok(no_secret("tuleap", {}) ~= 401, "verify_signature tuleap: no secret → not 401")
  ok(
    with_secret("tuleap", { ["X-Tuleap-Webhook-Secret"] = SECRET }) ~= 401,
    "verify_signature tuleap: valid X-Tuleap-Webhook-Secret → not 401"
  )
  eq(
    with_secret("tuleap", { ["X-Tuleap-Webhook-Secret"] = "bad" }),
    401,
    "verify_signature tuleap: bad X-Tuleap-Webhook-Secret → 401"
  )
  eq(
    with_secret("tuleap", {}),
    401,
    "verify_signature tuleap: missing X-Tuleap-Webhook-Secret → 401"
  )

  -- ── Azure DevOps: Authorization: Basic <creds> (DecodeBase64 is identity stub)
  -- SECRET = "mysecret"; DecodeBase64("mysecret") = "mysecret" (identity), so
  -- "Basic mysecret" is the valid credential when secret = "mysecret".
  ok(no_secret("azuredevops", {}) ~= 401, "verify_signature azuredevops: no secret → not 401")
  ok(
    with_secret("azuredevops", { ["Authorization"] = "Basic " .. SECRET }) ~= 401,
    "verify_signature azuredevops: valid Basic creds → not 401"
  )
  ok(
    with_secret("azuredevops", { ["Authorization"] = "basic " .. SECRET }) ~= 401,
    "verify_signature azuredevops: Basic scheme is case-insensitive → not 401"
  )
  eq(
    with_secret("azuredevops", { ["Authorization"] = "Basic badcreds" }),
    401,
    "verify_signature azuredevops: bad Basic creds → 401"
  )
  eq(
    with_secret("azuredevops", { ["Authorization"] = "Bearer " .. SECRET }),
    401,
    "verify_signature azuredevops: non-Basic scheme → 401"
  )
  eq(
    with_secret("azuredevops", {}),
    401,
    "verify_signature azuredevops: missing Authorization → 401"
  )

  -- ── Kallithea: body-embedded secret (exception to verify-before-parse rule)
  ok(no_secret("kallithea", {}) ~= 401, "verify_signature kallithea: no secret → not 401")
  ok(
    with_secret("kallithea", {}, '{"secret":"' .. SECRET .. '"}') ~= 401,
    "verify_signature kallithea: secret in root JSON field → not 401"
  )
  ok(
    with_secret("kallithea", {}, '{"data":{"secret":"' .. SECRET .. '"}}') ~= 401,
    "verify_signature kallithea: secret in data.secret JSON field → not 401"
  )
  ok(
    with_secret("kallithea", {}, '{"payload":{"webhook_token":"' .. SECRET .. '"}}') ~= 401,
    "verify_signature kallithea: secret in payload.webhook_token JSON field → not 401"
  )
  ok(
    with_secret("kallithea", {}, '{"auth_token":"' .. SECRET .. '"}') ~= 401,
    "verify_signature kallithea: secret in root auth_token JSON field → not 401"
  )
  eq(
    with_secret("kallithea", {}, '{"secret":"bad"}'),
    401,
    "verify_signature kallithea: bad body secret → 401"
  )
  eq(
    with_secret("kallithea", {}, '{"secret":{"nested":"' .. SECRET .. '"}}'),
    401,
    "verify_signature kallithea: non-scalar body secret → 401"
  )
  eq(
    with_secret("kallithea", {}, '{"event":"push"}'),
    401,
    "verify_signature kallithea: no secret field in body → 401"
  )
  eq(
    with_secret("kallithea", {}, "not-valid-json"),
    401,
    "verify_signature kallithea: invalid JSON body → 401"
  )

  -- ── CodeCommit: Amazon SNS X.509 signature verification
  -- No secret → trust-the-network; configured secret enables SNS signature verification.
  ok(
    no_secret("codecommit", {}) ~= 401,
    "verify_signature codecommit: no secret (trust-the-network) → not 401"
  )

  local saved_fetch = Fetch
  local saved_codecommit_sns_verify = CodeCommitVerifySnsSignature
  local fetched_cert_url = nil
  local captured_sns = nil
  local sns_cert = "-----BEGIN CERTIFICATE-----\ntest-cert\n-----END CERTIFICATE-----\n"
  local sns_cert_url = "https://sns.us-east-1.amazonaws.com/SimpleNotificationService-test.pem"
  local sns_topic = "arn:aws:sns:us-east-1:123456789012:codecommit"
  local sns_timestamp = "2024-01-15T12:00:00.000Z"
  local sns_body = '{"Type":"Notification","MessageId":"mid-1","TopicArn":"'
    .. sns_topic
    .. '","Subject":"subject","Message":"hello","Timestamp":"'
    .. sns_timestamp
    .. '","SignatureVersion":"1","Signature":"good-signature","SigningCertURL":"'
    .. sns_cert_url
    .. '","UnsubscribeURL":"https://sns.us-east-1.amazonaws.com/?Action=Unsubscribe"}'
  local sns_expected_string = table.concat({
    "Message",
    "hello",
    "MessageId",
    "mid-1",
    "Subject",
    "subject",
    "Timestamp",
    sns_timestamp,
    "TopicArn",
    sns_topic,
    "Type",
    "Notification",
  }, "\n")

  Fetch = function(url, _opts)
    fetched_cert_url = url
    return 200, {}, sns_cert
  end
  CodeCommitVerifySnsSignature = function(cert, string_to_sign, signature, alg)
    captured_sns = {
      cert = cert,
      string_to_sign = string_to_sign,
      signature = signature,
      alg = alg,
    }
    return cert == sns_cert
      and string_to_sign == sns_expected_string
      and signature == "good-signature"
      and alg == "sha1"
  end
  ok(
    call_sig("codecommit", {}, sns_body, { codecommit = SECRET }) ~= 401,
    "verify_signature codecommit: valid SNS notification signature → not 401"
  )
  eq(
    fetched_cert_url,
    sns_cert_url,
    "verify_signature codecommit: fetches certificate from SigningCertURL"
  )
  eq(
    captured_sns and captured_sns.string_to_sign,
    sns_expected_string,
    "verify_signature codecommit: builds canonical SNS notification string"
  )
  eq(captured_sns and captured_sns.alg, "sha1", "verify_signature codecommit: version 1 uses SHA1")

  local sns_v2_body = sns_body:gsub('"SignatureVersion":"1"', '"SignatureVersion":"2"')
  CodeCommitVerifySnsSignature = function(_cert, _string_to_sign, _signature, alg)
    return alg == "sha256"
  end
  ok(
    call_sig("codecommit", {}, sns_v2_body, { codecommit = SECRET }) ~= 401,
    "verify_signature codecommit: valid SNS SignatureVersion 2 → not 401"
  )

  local sub_body = '{"Type":"SubscriptionConfirmation","MessageId":"sub-1","Token":"token-1","TopicArn":"'
    .. sns_topic
    .. '","Message":"confirm","SubscribeURL":"https://sns.us-east-1.amazonaws.com/?Action=ConfirmSubscription","Timestamp":"'
    .. sns_timestamp
    .. '","SignatureVersion":"2","Signature":"good-signature","SigningCertURL":"'
    .. sns_cert_url
    .. '"}'
  local sub_expected_string = table.concat({
    "Message",
    "confirm",
    "MessageId",
    "sub-1",
    "SubscribeURL",
    "https://sns.us-east-1.amazonaws.com/?Action=ConfirmSubscription",
    "Timestamp",
    sns_timestamp,
    "Token",
    "token-1",
    "TopicArn",
    sns_topic,
    "Type",
    "SubscriptionConfirmation",
  }, "\n")
  CodeCommitVerifySnsSignature = function(_cert, string_to_sign, _signature, alg)
    return string_to_sign == sub_expected_string and alg == "sha256"
  end
  ok(
    call_sig("codecommit", {}, sub_body, { codecommit = SECRET }) ~= 401,
    "verify_signature codecommit: valid SNS subscription confirmation → not 401"
  )

  CodeCommitVerifySnsSignature = function()
    return false
  end
  eq(
    call_sig("codecommit", {}, sns_body, { codecommit = SECRET }),
    401,
    "verify_signature codecommit: bad SNS signature → 401"
  )

  eq(
    call_sig(
      "codecommit",
      {},
      sns_body:gsub("https://sns.us-east-1.amazonaws.com", "https://example.com"),
      { codecommit = SECRET }
    ),
    401,
    "verify_signature codecommit: untrusted SigningCertURL → 401"
  )
  eq(
    call_sig(
      "codecommit",
      {},
      sns_body:gsub('"SignatureVersion":"1"', '"SignatureVersion":"3"'),
      { codecommit = SECRET }
    ),
    401,
    "verify_signature codecommit: unsupported SignatureVersion → 401"
  )
  eq(
    call_sig("codecommit", {}, '{"Records":[]}', { codecommit = SECRET }),
    401,
    "verify_signature codecommit: configured verification rejects unsigned direct payloads"
  )
  Fetch = saved_fetch
  CodeCommitVerifySnsSignature = saved_codecommit_sns_verify

  -- ── Sourcehut: X-Payload-Signature, Ed25519 over raw body
  -- Unit tests use identity base64 decoding and a stub verifier.  The hurl
  -- suite exercises the OpenSSL-backed verifier with a real Ed25519 keypair.
  local SOURCEHUT_PUBLIC_KEY = string.rep("k", 32)
  local SOURCEHUT_SIGNATURE = string.rep("s", 64)
  ok(no_secret("sourcehut", {}) ~= 401, "verify_signature sourcehut: no public key → not 401")
  ok(
    call_sig(
      "sourcehut",
      { ["X-Payload-Signature"] = SOURCEHUT_SIGNATURE },
      nil,
      { sourcehut = SOURCEHUT_PUBLIC_KEY }
    ) ~= 401,
    "verify_signature sourcehut: valid X-Payload-Signature → not 401"
  )
  eq(
    call_sig(
      "sourcehut",
      { ["X-Payload-Signature"] = string.rep("x", 64) },
      nil,
      { sourcehut = SOURCEHUT_PUBLIC_KEY }
    ),
    401,
    "verify_signature sourcehut: bad X-Payload-Signature → 401"
  )
  eq(
    call_sig("sourcehut", {}, nil, { sourcehut = SOURCEHUT_PUBLIC_KEY }),
    401,
    "verify_signature sourcehut: missing X-Payload-Signature → 401"
  )
  eq(
    call_sig(
      "sourcehut",
      { ["X-Payload-Signature"] = "short" },
      nil,
      { sourcehut = SOURCEHUT_PUBLIC_KEY }
    ),
    401,
    "verify_signature sourcehut: malformed signature length → 401"
  )
  eq(
    call_sig(
      "sourcehut",
      { ["X-Payload-Signature"] = SOURCEHUT_SIGNATURE },
      nil,
      { sourcehut = "short" }
    ),
    401,
    "verify_signature sourcehut: malformed public key length → 401"
  )

  -- ── Confusio-normalized: X-Confusio-Signature-256, HMAC-SHA256 + timestamp
  -- Header format: "sha256=<hex>, v=1, ts=<unix>"
  -- HMAC basestring: "v1:<ts>:<body>"  Replay window: 300 seconds.
  ok(no_secret("confusio", {}) ~= 401, "verify_signature confusio: no secret → not 401")

  -- Valid: current timestamp, correct stub HMAC hex.
  -- Using os.time() so the timestamp is within the replay window when the test runs.
  local confusio_now = os.time()
  local confusio_valid_hdr = "sha256=" .. STUB_HEX .. ", v=1, ts=" .. tostring(confusio_now)
  ok(
    with_secret("confusio", { ["X-Confusio-Signature-256"] = confusio_valid_hdr }) ~= 401,
    "verify_signature confusio: valid X-Confusio-Signature-256 (current ts) → not 401"
  )

  -- Stale past timestamp (January 2001): outside replay window.
  local confusio_stale_past = "sha256=" .. STUB_HEX .. ", v=1, ts=980000000"
  eq(
    with_secret("confusio", { ["X-Confusio-Signature-256"] = confusio_stale_past }),
    401,
    "verify_signature confusio: stale past timestamp → 401 (replay rejected)"
  )

  -- Stale future timestamp (year 5138): outside replay window.
  local confusio_stale_future = "sha256=" .. STUB_HEX .. ", v=1, ts=99999999999"
  eq(
    with_secret("confusio", { ["X-Confusio-Signature-256"] = confusio_stale_future }),
    401,
    "verify_signature confusio: stale future timestamp → 401 (replay rejected)"
  )

  -- Bad HMAC (current timestamp but wrong hex): rejected even with fresh ts.
  local confusio_bad_hmac = "sha256=deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
    .. ", v=1, ts="
    .. tostring(confusio_now)
  eq(
    with_secret("confusio", { ["X-Confusio-Signature-256"] = confusio_bad_hmac }),
    401,
    "verify_signature confusio: bad HMAC hex → 401"
  )

  -- Missing header.
  eq(with_secret("confusio", {}), 401, "verify_signature confusio: missing header → 401")

  -- Malformed header: missing v=1.
  local confusio_no_v = "sha256=" .. STUB_HEX .. ", ts=" .. tostring(confusio_now)
  eq(
    with_secret("confusio", { ["X-Confusio-Signature-256"] = confusio_no_v }),
    401,
    "verify_signature confusio: header missing v=1 → 401"
  )

  -- Malformed header: missing ts.
  local confusio_no_ts = "sha256=" .. STUB_HEX .. ", v=1"
  eq(
    with_secret("confusio", { ["X-Confusio-Signature-256"] = confusio_no_ts }),
    401,
    "verify_signature confusio: header missing ts → 401"
  )
end

-- ============================================================
-- sign_github / sign_for_backend
-- ============================================================

do
  -- GetCryptoHash stub returns 32 bytes of 0xaa → hex is 64 'a' chars.
  local STUB_HEX = string.rep("aa", 32)
  local SECRET = "mysecret"
  local BODY = '{"action":"opened"}'

  -- ── sign_github ──────────────────────────────────────────

  ok(type(sign_github) == "function", "sign_github: exported as global function")

  -- No secret → both return values are nil.
  local s256, s1 = sign_github(nil, BODY)
  ok(s256 == nil, "sign_github(nil): sha256 value is nil")
  ok(s1 == nil, "sign_github(nil): sha1 value is nil")

  s256, s1 = sign_github("", BODY)
  ok(s256 == nil, "sign_github(''): sha256 value is nil")
  ok(s1 == nil, "sign_github(''): sha1 value is nil")

  -- With secret → returns "sha256=<hex>" and "sha1=<hex>".
  s256, s1 = sign_github(SECRET, BODY)
  eq(s256, "sha256=" .. STUB_HEX, "sign_github: sha256 value has correct prefix and hex")
  eq(s1, "sha1=" .. STUB_HEX, "sign_github: sha1 value has correct prefix and hex")

  -- Return values are strings (header-value ready).
  ok(type(s256) == "string", "sign_github: sha256 return is a string")
  ok(type(s1) == "string", "sign_github: sha1 return is a string")

  -- ── sign_for_backend ─────────────────────────────────────
  -- luacheck: globals sign_for_backend
  ok(type(sign_for_backend) == "function", "sign_for_backend: exported as global function")

  -- No secret: returns empty table for any backend.
  local sfb_empty = sign_for_backend("gitea", nil, BODY)
  ok(type(sfb_empty) == "table", "sign_for_backend(nil): returns table")
  ok(next(sfb_empty) == nil, "sign_for_backend(nil): empty table")

  -- Gitea family: X-Gitea-Signature, HMAC-SHA256, no prefix.
  for _, be in ipairs({ "gitea", "forgejo", "codeberg" }) do
    local h = sign_for_backend(be, SECRET, BODY)
    ok(h["X-Gitea-Signature"] ~= nil, "sign_for_backend " .. be .. ": X-Gitea-Signature present")
    ok(h["X-Hub-Signature-256"] == nil, "sign_for_backend " .. be .. ": no X-Hub-Signature-256")
  end

  -- Gogs family: X-Gogs-Signature, HMAC-SHA256, no prefix.
  for _, be in ipairs({ "gogs", "notabug" }) do
    local h = sign_for_backend(be, SECRET, BODY)
    ok(h["X-Gogs-Signature"] ~= nil, "sign_for_backend " .. be .. ": X-Gogs-Signature present")
    ok(h["X-Gitea-Signature"] == nil, "sign_for_backend " .. be .. ": no X-Gitea-Signature")
  end

  -- GitLab: verbatim token.
  local sfb_gl = sign_for_backend("gitlab", SECRET, BODY)
  eq(sfb_gl["X-Gitlab-Token"], SECRET, "sign_for_backend gitlab: X-Gitlab-Token is the secret")

  -- OneDev: verbatim token in X-OneDev-Signature.
  local sfb_onedev = sign_for_backend("onedev", SECRET, BODY)
  eq(
    sfb_onedev["X-OneDev-Signature"],
    SECRET,
    "sign_for_backend onedev: X-OneDev-Signature is the secret"
  )
  ok(sfb_onedev["Authorization"] == nil, "sign_for_backend onedev: no Authorization header")

  -- HMAC-SHA1 via X-Hub-Signature.
  for _, be in ipairs({ "gitbucket", "launchpad" }) do
    local h = sign_for_backend(be, SECRET, BODY)
    eq(
      h["X-Hub-Signature"],
      "sha1=" .. STUB_HEX,
      "sign_for_backend " .. be .. ": X-Hub-Signature sha1= present"
    )
    ok(h["X-Hub-Signature-256"] == nil, "sign_for_backend " .. be .. ": no X-Hub-Signature-256")
  end

  -- SourceForge / Allura: HMAC-SHA1 via X-Allura-Signature.
  local sfb_sourceforge = sign_for_backend("sourceforge", SECRET, BODY)
  eq(
    sfb_sourceforge["X-Allura-Signature"],
    "sha1=" .. STUB_HEX,
    "sign_for_backend sourceforge: X-Allura-Signature sha1= present"
  )
  ok(
    sfb_sourceforge["X-Sourceforge-Webhook-Secret"] == nil,
    "sign_for_backend sourceforge: no legacy shared-token header"
  )

  -- Default (unknown backend): GitHub-style.
  local sfb_def = sign_for_backend("unknown_backend", SECRET, BODY)
  ok(sfb_def["X-Hub-Signature-256"] ~= nil, "sign_for_backend unknown: X-Hub-Signature-256 present")
  ok(sfb_def["X-Hub-Signature"] ~= nil, "sign_for_backend unknown: X-Hub-Signature present")
end

-- ============================================================
-- make_internal_event
-- ============================================================

ok(type(webhook_event_catalog) == "table", "webhook_event_catalog: exported as global table")
ok(type(webhook_catalog_events) == "function", "webhook_catalog_events: exported as function")
ok(type(webhook_catalog_providers) == "function", "webhook_catalog_providers: exported as function")
ok(
  type(webhook_catalog_event_names) == "function",
  "webhook_catalog_event_names: exported as function"
)
ok(type(webhook_catalog_event) == "function", "webhook_catalog_event: exported as function")
ok(
  type(webhook_catalog_event_known) == "function",
  "webhook_catalog_event_known: exported as function"
)
ok(
  type(webhook_catalog_normalized_base) == "function",
  "webhook_catalog_normalized_base: exported as function"
)
ok(type(make_internal_event) == "function", "make_internal_event: exported as global function")
ok(
  type(normalized_webhook_event_type) == "function",
  "normalized_webhook_event_type: exported as global function"
)
ok(
  type(make_normalized_webhook_envelope) == "function",
  "make_normalized_webhook_envelope: exported as global function"
)

do
  local providers = webhook_catalog_providers()
  ok(#providers >= 25, "webhook_catalog_providers: includes all supported webhook sources")

  local names = webhook_catalog_event_names()
  ok(names.issues == true, "webhook_catalog_event_names: includes issues")
  ok(names.pull_request == true, "webhook_catalog_event_names: includes pull_request")
  ok(names.workflow_run == true, "webhook_catalog_event_names: includes workflow_run")
  ok(
    names.not_a_github_event == nil,
    "webhook_catalog_event_names: excludes unsupported event names"
  )
  ok(webhook_catalog_event_known("release"), "webhook_catalog_event_known: known event")
  ok(
    not webhook_catalog_event_known("not_a_github_event"),
    "webhook_catalog_event_known: unknown event"
  )

  local issues_def = webhook_catalog_event("issues")
  eq(issues_def.normalized_base, "issue", "webhook_catalog_event: issues normalized base")
  ok(#issues_def.actions > 1, "webhook_catalog_event: issues records action coverage")
  ok(
    issues_def.providers.gitea.status == "supported",
    "webhook_catalog_event: provider source status recorded"
  )
  ok(
    type(issues_def.providers.gitblit) == "table",
    "webhook_catalog_event: unsupported/no-analog provider entries are explicit"
  )

  local rhodecode_push = webhook_catalog_event("push").providers.rhodecode
  eq(rhodecode_push.status, "supported", "webhook_catalog_event: rhodecode push supported")
  eq(
    table.concat(rhodecode_push.sources, ","),
    "PUSH_HOOK,POST_PUSH",
    "webhook_catalog_event: rhodecode push native sources recorded"
  )

  local rhodecode_pr = webhook_catalog_event("pull_request").providers.rhodecode
  eq(
    table.concat(rhodecode_pr.sources, ","),
    "webhook integration pull_request,CREATE_PULLREQUEST_HOOK,CLOSE_PULLREQUEST_HOOK",
    "webhook_catalog_event: rhodecode pull_request native sources recorded"
  )

  local security_def = webhook_catalog_event("security_advisory")
  eq(
    security_def.providers.gitea.status,
    "no_analog",
    "webhook_catalog_event: no-analog provider status is explicit"
  )
  eq(
    webhook_catalog_normalized_base("workflow_run"),
    "workflow.run",
    "webhook_catalog_normalized_base: dotted bases come from catalog"
  )
end

do
  -- All required fields present → table with correct keys.
  local ev = make_internal_event({
    event = "issues",
    action = "opened",
    provider = "gitea",
    raw = { action = "opened" },
    data = { issue = { id = 1 } },
  })
  eq(ev.event, "issues", "make_internal_event: event field")
  eq(ev.action, "opened", "make_internal_event: action field")
  eq(ev.provider, "gitea", "make_internal_event: provider field")
  eq(type(ev.raw), "table", "make_internal_event: raw is a table")
  eq(type(ev.data), "table", "make_internal_event: data is a table")
  eq(ev.timestamp, "", "make_internal_event: timestamp defaults to empty string")
  ok(ev.raw_action == nil, "make_internal_event: raw_action absent for known action")

  -- With explicit timestamp → preserved.
  local ev2 = make_internal_event({
    event = "push",
    action = "",
    provider = "gitlab",
    timestamp = "2024-01-15T10:00:00Z",
    raw = {},
    data = {},
  })
  eq(ev2.timestamp, "2024-01-15T10:00:00Z", "make_internal_event: explicit timestamp preserved")

  -- Unknown action → action == "unknown" and raw_action set.
  local ev3 = make_internal_event({
    event = "issues",
    action = "unknown",
    raw_action = "some_new_action",
    provider = "gitea",
    raw = { action = "some_new_action" },
    data = {},
  })
  eq(ev3.action, "unknown", "make_internal_event: action == 'unknown' preserved")
  eq(ev3.raw_action, "some_new_action", "make_internal_event: raw_action preserved")

  -- Missing optional fields default gracefully.
  local ev4 = make_internal_event({ event = "label", action = "created", provider = "gitea" })
  eq(ev4.timestamp, "", "make_internal_event: missing timestamp defaults to ''")
  eq(type(ev4.raw), "table", "make_internal_event: missing raw defaults to {}")
  eq(type(ev4.data), "table", "make_internal_event: missing data defaults to {}")
end

-- ============================================================
-- normalized webhook event model core
-- ============================================================

do
  eq(
    normalized_webhook_event_type("issues", "opened"),
    "issue.opened",
    "normalized_webhook_event_type: issues action maps to issue namespace"
  )
  eq(
    normalized_webhook_event_type("issue_comment", "created"),
    "issue.comment.created",
    "normalized_webhook_event_type: issue_comment action maps to dotted namespace"
  )
  eq(
    normalized_webhook_event_type("pull_request_review", "submitted"),
    "pull_request.review.submitted",
    "normalized_webhook_event_type: pull_request_review maps to review namespace"
  )
  eq(
    normalized_webhook_event_type("push", ""),
    "push",
    "normalized_webhook_event_type: empty action returns event namespace"
  )
  eq(
    normalized_webhook_event_type("custom_backend_event", "created"),
    "custom_backend_event.created",
    "normalized_webhook_event_type: unknown event preserves backend event key"
  )

  local internal = make_internal_event({
    event = "issue_comment",
    action = "created",
    provider = "gitea",
    timestamp = "2026-04-28T10:11:12Z",
    raw = {
      sender = { login = "octocat" },
      repository = { full_name = "octo/repo" },
    },
    data = {
      payload = { comment = { id = 10, body = "nice" } },
    },
  })
  local env = make_normalized_webhook_envelope(internal, { id = "delivery-1" })
  eq(env.id, "delivery-1", "make_normalized_webhook_envelope: explicit id preserved")
  eq(
    env.type,
    "issue.comment.created",
    "make_normalized_webhook_envelope: type derived from event and action"
  )
  eq(
    env.occurred_at,
    "2026-04-28T10:11:12Z",
    "make_normalized_webhook_envelope: timestamp preserved"
  )
  eq(env.actor.login, "octocat", "make_normalized_webhook_envelope: actor falls back to raw sender")
  eq(
    env.repository.full_name,
    "octo/repo",
    "make_normalized_webhook_envelope: repository falls back to raw repository"
  )
  eq(
    env.payload.comment.id,
    10,
    "make_normalized_webhook_envelope: payload uses normalized data payload"
  )

  local override = make_normalized_webhook_envelope(internal, {
    id = "delivery-2",
    type = "issue.comment.custom",
    occurred_at = "2026-04-28T12:00:00Z",
    actor = { login = "override" },
    repository = { full_name = "override/repo" },
    payload = { ok = true },
  })
  eq(override.type, "issue.comment.custom", "make_normalized_webhook_envelope: type override")
  eq(
    override.occurred_at,
    "2026-04-28T12:00:00Z",
    "make_normalized_webhook_envelope: occurred_at override"
  )
  eq(override.actor.login, "override", "make_normalized_webhook_envelope: actor override")
  eq(
    override.repository.full_name,
    "override/repo",
    "make_normalized_webhook_envelope: repository override"
  )
  ok(override.payload.ok == true, "make_normalized_webhook_envelope: payload override")

  local generated = make_normalized_webhook_envelope(make_internal_event({
    event = "push",
    provider = "gitea",
    raw = {},
    data = {},
  }))
  eq(#generated.id, 36, "make_normalized_webhook_envelope: generated id is UUID length")
  ok(
    generated.occurred_at:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$") ~= nil,
    "make_normalized_webhook_envelope: empty timestamp falls back to current ISO time"
  )
  eq(generated.type, "push", "make_normalized_webhook_envelope: action-less event type")
end

-- ============================================================
-- GitHub webhook payload builders
-- ============================================================

ok(type(github_webhook_payload) == "function", "github_webhook_payload: exported")
ok(type(github_webhook_repository) == "function", "github_webhook_repository: exported")
ok(type(github_webhook_sender) == "function", "github_webhook_sender: exported")
ok(type(github_webhook_issue) == "function", "github_webhook_issue: exported")
ok(type(github_webhook_pull_request) == "function", "github_webhook_pull_request: exported")
ok(type(github_webhook_release) == "function", "github_webhook_release: exported")
ok(type(github_webhook_installation) == "function", "github_webhook_installation: exported")
ok(type(github_webhook_projects_v2) == "function", "github_webhook_projects_v2: exported")

do
  local repo = github_webhook_repository({
    id = 42,
    name = "confusio",
    full_name = "rhencke/confusio",
    owner = { login = "rhencke", id = 7 },
    private = true,
  }, {
    allow_forking = false,
  })
  eq(repo.id, 42, "github_webhook_repository: preserves provider id")
  eq(repo.full_name, "rhencke/confusio", "github_webhook_repository: preserves full name")
  eq(repo.owner.login, "rhencke", "github_webhook_repository: normalizes owner")
  eq(repo.owner.node_id, "", "github_webhook_repository: owner keeps GitHub defaults")
  eq(repo.visibility, "private", "github_webhook_repository: derives private visibility")
  ok(repo.allow_forking == false, "github_webhook_repository: override can force false")
  eq(repo.has_issues, true, "github_webhook_repository: stable boolean default")

  local issue = github_webhook_issue({
    number = 19,
    title = "Normalize webhooks",
    user = { login = "fido" },
  })
  eq(issue.number, 19, "github_webhook_issue: preserves issue number")
  eq(issue.state, "open", "github_webhook_issue: defaults state")
  eq(issue.user.login, "fido", "github_webhook_issue: normalizes user")
  eq(issue.user.type, "User", "github_webhook_issue: user keeps GitHub defaults")
  eq(issue.author_association, "NONE", "github_webhook_issue: defaults author association")

  local pr = github_webhook_pull_request({
    number = 365,
    title = "Webhook translation",
    head = { ref = "normalize-webhook-payloads" },
    base = { ref = "main" },
  }, {
    mergeable_state = "clean",
  })
  eq(pr.number, 365, "github_webhook_pull_request: preserves number")
  eq(pr.head.ref, "normalize-webhook-payloads", "github_webhook_pull_request: preserves head")
  eq(pr.base.ref, "main", "github_webhook_pull_request: preserves base")
  eq(pr.mergeable_state, "clean", "github_webhook_pull_request: override point")

  local release = github_webhook_release({
    id = 5,
    tag_name = "v3",
    author = { login = "release-bot" },
  })
  eq(release.tag_name, "v3", "github_webhook_release: preserves tag")
  ok(release.draft == false, "github_webhook_release: defaults draft false")
  eq(release.author.login, "release-bot", "github_webhook_release: normalizes author")

  local installation = github_webhook_installation({
    id = 99,
    account = { login = "rhencke" },
  })
  eq(installation.id, 99, "github_webhook_installation: preserves id")
  eq(installation.repository_selection, "all", "github_webhook_installation: default selection")
  eq(installation.app_slug, "confusio", "github_webhook_installation: confusio default app slug")

  local project_v2 = github_webhook_projects_v2({ number = 2, title = "Event side" })
  eq(project_v2.number, 2, "github_webhook_projects_v2: preserves number")
  eq(project_v2.title, "Event side", "github_webhook_projects_v2: preserves title")
  ok(project_v2.closed == false, "github_webhook_projects_v2: defaults closed false")
end

do
  local event = make_internal_event({
    event = "issues",
    action = "opened",
    provider = "gitea",
    data = {
      issue = { number = 12, title = "A thing", user = { login = "fido" } },
      repository = { full_name = "rhencke/confusio", owner = { login = "rhencke" } },
      sender = { login = "fido" },
      label = { name = "Insight", color = "5319e7" },
    },
  })
  local payload = github_webhook_payload(event)
  eq(payload.action, "opened", "github_webhook_payload: action envelope")
  eq(payload.issue.number, 12, "github_webhook_payload: issues includes issue")
  eq(
    payload.repository.full_name,
    "rhencke/confusio",
    "github_webhook_payload: includes repository"
  )
  eq(payload.sender.login, "fido", "github_webhook_payload: includes sender")
  eq(payload.label.name, "Insight", "github_webhook_payload: includes action-specific label")

  local overridden = github_webhook_payload(event, {
    action = "edited",
    issue = { number = 99 },
    payload = { enterprise = { slug = "test-enterprise" } },
  })
  eq(overridden.action, "edited", "github_webhook_payload: action override")
  eq(overridden.issue.number, 99, "github_webhook_payload: entity override")
  eq(
    overridden.enterprise.slug,
    "test-enterprise",
    "github_webhook_payload: top-level payload override"
  )

  local push_payload = github_webhook_payload(make_internal_event({
    event = "push",
    action = "push",
    provider = "sourceforge",
    data = {
      ref = "refs/heads/main",
      before = "0000",
      after = "1111",
      repository = { full_name = "rhencke/confusio" },
      sender = { login = "fido" },
      commits = { { id = "1111", message = "fetch stick" } },
      head_commit = { id = "1111" },
      pusher = { name = "Fido" },
    },
  }))
  ok(push_payload.action == nil, "github_webhook_payload: push has no action")
  eq(push_payload.ref, "refs/heads/main", "github_webhook_payload: push ref")
  eq(push_payload.commits[1].id, "1111", "github_webhook_payload: push commits")
end

-- ============================================================
-- webhook_receiver: unknown-action sidecar header
-- ============================================================

do
  local function call_webhook_full(opts)
    local saved_config = app.config
    app.config = {
      backend = (opts.path or ""):match("^/webhooks/([^/]+)$") or saved_config.backend,
      base_url = saved_config.base_url,
      webhook_secrets = saved_config.webhook_secrets or {},
    }
    reset_request(opts)
    reset_response()
    app.webhook_receiver()
    local status, headers = _last_status, _last_headers
    app.config = saved_config
    return status, headers
  end

  local saved_webhooks = app.backend.webhooks

  -- Known action: no X-Confusio-Raw-Action header on 200.
  app.backend.webhooks = {
    issues = function(payload)
      return make_internal_event({
        event = "issues",
        action = "opened",
        provider = "gitea",
        raw = payload,
        data = {},
      })
    end,
  }
  local status1, hdrs1 = call_webhook_full({
    method = "POST",
    path = "/webhooks/gitea",
    headers = { ["Content-Type"] = "application/json", ["X-Gitea-Event"] = "issues" },
    body = '{"action":"opened"}',
  })
  eq(status1, 200, "webhook_receiver: known action → 200")
  ok(
    hdrs1["X-Confusio-Raw-Action"] == nil,
    "webhook_receiver: known action → no X-Confusio-Raw-Action"
  )

  -- Unknown action: X-Confusio-Raw-Action set with raw action string.
  app.backend.webhooks = {
    issues = function(payload)
      return make_internal_event({
        event = "issues",
        action = "unknown",
        raw_action = payload.action,
        provider = "gitea",
        raw = payload,
        data = {},
      })
    end,
  }
  local status2, hdrs2 = call_webhook_full({
    method = "POST",
    path = "/webhooks/gitea",
    headers = { ["Content-Type"] = "application/json", ["X-Gitea-Event"] = "issues" },
    body = '{"action":"pinned"}',
  })
  eq(status2, 200, "webhook_receiver: unknown action → still 200")
  eq(
    hdrs2["X-Confusio-Raw-Action"],
    "pinned",
    "webhook_receiver: unknown action → X-Confusio-Raw-Action set"
  )

  -- Unknown action but raw_action not set: no header emitted.
  app.backend.webhooks = {
    issues = function(payload)
      return make_internal_event({
        event = "issues",
        action = "unknown",
        provider = "gitea",
        raw = payload,
        data = {},
      })
    end,
  }
  local status3, hdrs3 = call_webhook_full({
    method = "POST",
    path = "/webhooks/gitea",
    headers = { ["Content-Type"] = "application/json", ["X-Gitea-Event"] = "issues" },
    body = '{"action":"pinned"}',
  })
  eq(status3, 200, "webhook_receiver: unknown action without raw_action → 200")
  ok(
    hdrs3["X-Confusio-Raw-Action"] == nil,
    "webhook_receiver: action=unknown, no raw_action → no header"
  )

  app.backend.webhooks = saved_webhooks
end

-- ============================================================
-- make_uuid / iso8601 / now_iso8601 (internal/util.lua)
-- ============================================================

-- make_uuid: format validation with the deterministic GetRandomBytes stub.
-- Stub returns bytes [17, 34, 51, 68, 85, 102, 119, 136, 153, 170, 187, 204, 221, 238, 255, 16].
-- byte 7 (119 = 0x77) → (0x77 & 0x0f) | 0x40 = 0x47
-- byte 9 (153 = 0x99) → (0x99 & 0x3f) | 0x80 = 0x99
-- Expected UUID: "11223344-5566-4788-99aa-bbccddeeff10"
local uuid1 = make_uuid() -- luacheck: globals make_uuid
eq(#uuid1, 36, "make_uuid: length is 36")
eq(uuid1:sub(9, 9), "-", "make_uuid: dash at position 9")
eq(uuid1:sub(14, 14), "-", "make_uuid: dash at position 14")
eq(uuid1:sub(19, 19), "-", "make_uuid: dash at position 19")
eq(uuid1:sub(24, 24), "-", "make_uuid: dash at position 24")
eq(uuid1:sub(15, 15), "4", "make_uuid: version nibble is 4")
ok(
  uuid1:sub(20, 20):match("[89ab]") ~= nil,
  "make_uuid: variant nibble is 8, 9, a, or b (got " .. uuid1:sub(20, 20) .. ")"
)
ok(
  uuid1:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil,
  "make_uuid: matches xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx pattern"
)
eq(uuid1, "11223344-5566-4788-99aa-bbccddeeff10", "make_uuid: deterministic from stub")

-- make_uuid: two successive calls return the same value when the stub is deterministic.
local uuid2 = make_uuid()
eq(uuid1, uuid2, "make_uuid: stub is deterministic — same bytes → same UUID")

-- iso8601: known epoch values.
local ts0 = iso8601(0) -- luacheck: globals iso8601
eq(ts0, "1970-01-01T00:00:00Z", "iso8601(0): Unix epoch")
local ts1 = iso8601(1000000000)
eq(ts1, "2001-09-09T01:46:40Z", "iso8601(1000000000): known timestamp")
local ts2 = iso8601(1714003200)
eq(ts2, "2024-04-25T00:00:00Z", "iso8601(1714003200): 2024-04-25T00:00:00Z")

-- iso8601: format shape — 20 characters, ends with Z.
eq(#ts0, 20, "iso8601: length is 20")
eq(ts0:sub(20, 20), "Z", "iso8601: ends with Z")
eq(ts0:sub(5, 5), "-", "iso8601: first dash after year")
eq(ts0:sub(8, 8), "-", "iso8601: second dash after month")
eq(ts0:sub(11, 11), "T", "iso8601: T separator")
eq(ts0:sub(14, 14), ":", "iso8601: first colon")
eq(ts0:sub(17, 17), ":", "iso8601: second colon")

-- now_iso8601: returns a 20-character ISO 8601 string matching the current minute.
local now_str = now_iso8601() -- luacheck: globals now_iso8601
eq(#now_str, 20, "now_iso8601: length is 20")
ok(
  now_str:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$") ~= nil,
  "now_iso8601: matches yyyy-mm-ddThh:mm:ssZ pattern"
)
-- Verify it's within 5 seconds of os.time().
local expected_prefix = iso8601(os.time()):sub(1, 16)
eq(now_str:sub(1, 16), expected_prefix, "now_iso8601: within same minute as os.time()")

-- ============================================================
-- fanout_body (internal/fanout.lua)
-- ============================================================

do
  -- luacheck: globals fanout_body
  local payload = { ref = "refs/heads/main", after = "abc123" }

  -- "github" shape: body is EncodeJson(payload) — raw payload forwarded unchanged.
  local gb = fanout_body("gitea", "push", payload, "github")
  ok(type(gb) == "string", "fanout_body github: returns a string")
  local decoded_gb = DecodeJson(gb) -- luacheck: globals DecodeJson
  ok(type(decoded_gb) == "table", "fanout_body github: body is valid JSON")
  eq(decoded_gb.ref, "refs/heads/main", "fanout_body github: payload fields forwarded")
  ok(decoded_gb.source == nil, "fanout_body github: no envelope wrapper")

  local internal = make_internal_event({ -- luacheck: globals make_internal_event
    event = "issues",
    action = "opened",
    provider = "gitea",
    raw = payload,
    data = {
      payload = { normalized = true },
    },
  })
  local gtb = fanout_body("gitea", "issues", payload, "github", internal, nil, {
    id = "github-delivery-123",
  }, {
    issues = function(ev, fields)
      return {
        action = ev.action,
        delivery_id = fields.id,
        issue = ev.data.payload,
      }
    end,
  })
  local decoded_gtb = DecodeJson(gtb)
  eq(decoded_gtb.action, "opened", "fanout_body github translator: action forwarded")
  eq(
    decoded_gtb.delivery_id,
    "github-delivery-123",
    "fanout_body github translator: receives delivery id"
  )
  ok(decoded_gtb.issue.normalized == true, "fanout_body github translator: normalized payload used")

  -- "confusio" shape: body is the normalized event envelope.
  local cb = fanout_body("gitea", "push", payload, "confusio")
  ok(type(cb) == "string", "fanout_body confusio: returns a string")
  local decoded_cb = DecodeJson(cb)
  ok(type(decoded_cb) == "table", "fanout_body confusio: body is valid JSON")
  eq(decoded_cb.type, "push", "fanout_body confusio: type is normalized event type")
  ok(type(decoded_cb.id) == "string", "fanout_body confusio: id is present")
  ok(type(decoded_cb.payload) == "table", "fanout_body confusio: payload is a table")
  eq(decoded_cb.payload.ref, "refs/heads/main", "fanout_body confusio: payload fields preserved")

  local tb = fanout_body("gitea", "issues", payload, "confusio", internal, {
    issues = function(ev, fields)
      return {
        id = fields.id,
        type = "custom." .. ev.event,
        payload = ev.data.payload,
      }
    end,
  }, { id = "delivery-123" })
  local decoded_tb = DecodeJson(tb)
  eq(decoded_tb.id, "delivery-123", "fanout_body confusio translator: receives delivery id")
  eq(decoded_tb.type, "custom.issues", "fanout_body confusio translator: event translator used")
  ok(
    decoded_tb.payload.normalized == true,
    "fanout_body confusio translator: normalized payload used"
  )

  -- Unknown shape falls back to "github" behaviour.
  local ub = fanout_body("gitea", "push", payload, "unknown")
  local decoded_ub = DecodeJson(ub)
  ok(decoded_ub.source == nil, "fanout_body unknown shape: falls back to raw payload (no wrapper)")

  -- nil shape also falls back to "github" behaviour.
  local nb = fanout_body("gitea", "push", payload, nil)
  local decoded_nb = DecodeJson(nb)
  ok(decoded_nb.source == nil, "fanout_body nil shape: falls back to raw payload (no wrapper)")
end

-- fanout_register_target / fanout_dispatch (internal/fanout.lua)
-- ============================================================

-- luacheck: globals fanout_register_target fanout_dispatch deliver_fire

-- fanout_register_target: invalid entries are silently ignored.
fanout_register_target(nil)
fanout_register_target({})
fanout_register_target({ url = "" })
fanout_register_target({ url = 42 })

do
  -- The main init call registered three startup targets:
  --   fido        → release + workflow_run, github shape
  --   auditor     → workflow_run, confusio shape
  --   wt-coverage → push + pull_request, github shape
  -- Exercise the real fanout_dispatch → deliver_fire path before replacing
  -- deliver_fire below.
  local _real_Fetch = Fetch
  local _real_Log = Log
  local _startup_fetch_calls = {}
  local _startup_log_calls = {}
  Fetch = function(url, opts) -- luacheck: globals Fetch
    _startup_fetch_calls[#_startup_fetch_calls + 1] = { url = url, opts = opts }
    if url:find("/fido", 1, true) then
      error("startup target unavailable")
    end
    return 204, {}, ""
  end
  Log = function(level, msg) -- luacheck: globals Log
    _startup_log_calls[#_startup_log_calls + 1] = { level = level, msg = msg }
  end

  local fd_startup_count = fanout_dispatch("gitea", "workflow_run", {
    action = "completed",
    workflow_run = { id = 123 },
  })
  eq(
    fd_startup_count,
    2,
    "fanout_dispatch startup targets: workflow_run matches repeated target filters only"
  )
  eq(
    #_startup_fetch_calls,
    2,
    "fanout_dispatch startup targets: failed first target does not block second target"
  )
  eq(
    _startup_fetch_calls[1].url,
    "https://hook.example.com/fido",
    "fanout_dispatch startup targets: first repeated target delivered"
  )
  eq(
    _startup_fetch_calls[2].url,
    "https://hook.example.com/audit",
    "fanout_dispatch startup targets: second repeated target delivered"
  )
  eq(
    _startup_fetch_calls[1].opts.headers["X-GitHub-Event"],
    "workflow_run",
    "fanout_dispatch startup targets: github shape uses GitHub event header"
  )
  ok(
    _startup_fetch_calls[1].opts.headers["X-Confusio-Event"] == nil,
    "fanout_dispatch startup targets: github shape omits Confusio event header"
  )
  eq(
    _startup_fetch_calls[2].opts.headers["X-Confusio-Event"],
    "workflow_run",
    "fanout_dispatch startup targets: confusio shape uses Confusio event header"
  )
  ok(
    _startup_fetch_calls[2].opts.headers["X-GitHub-Event"] == nil,
    "fanout_dispatch startup targets: confusio shape omits GitHub event header"
  )
  eq(
    DecodeJson(_startup_fetch_calls[2].opts.body).type,
    "workflow.run",
    "fanout_dispatch startup targets: confusio shape body records normalized event type"
  )
  eq(#_startup_log_calls, 2, "fanout_dispatch startup targets: every delivery attempt is logged")
  eq(
    _startup_log_calls[1].level,
    kLogWarn, -- luacheck: globals kLogWarn
    "fanout_dispatch startup targets: failed delivery is logged as warning"
  )
  eq(
    _startup_log_calls[2].level,
    kLogVerbose, -- luacheck: globals kLogVerbose
    "fanout_dispatch startup targets: successful delivery is logged as verbose"
  )
  ok(
    _startup_log_calls[1].msg:find("target=fido", 1, true) ~= nil,
    "fanout_dispatch startup targets: failed target name logged"
  )
  ok(
    _startup_log_calls[1].msg:find("error=", 1, true) ~= nil,
    "fanout_dispatch startup targets: failed target log includes error"
  )
  ok(
    _startup_log_calls[2].msg:find("target=auditor", 1, true) ~= nil,
    "fanout_dispatch startup targets: succeeding target name logged"
  )
  ok(
    _startup_fetch_calls[1].url ~= _startup_fetch_calls[2].url,
    "fanout_dispatch startup targets: no retry or duplicate delivery attempt created"
  )

  _startup_fetch_calls = {}
  _startup_log_calls = {}
  local fd_push_count = fanout_dispatch("gitea", "push", {
    ref = "refs/heads/main",
  })
  eq(
    fd_push_count,
    1,
    "fanout_dispatch startup targets: push matches only the legacy target filter"
  )
  eq(
    #_startup_fetch_calls,
    1,
    "fanout_dispatch startup targets: filtered-out targets receive no delivery attempt"
  )
  eq(
    _startup_fetch_calls[1].url,
    "https://hook.example.com/wt-coverage",
    "fanout_dispatch startup targets: legacy target still participates in fanout"
  )

  Fetch = _real_Fetch -- luacheck: globals Fetch
  Log = _real_Log -- luacheck: globals Log
end

-- Mock deliver_fire for all fanout tests so no real HTTP calls are made.
-- The startup wiring (webhook_target CLI arg) already registered one target
-- with events=["push"].  Tests use an event type of "create" to get a clean baseline
-- (the pre-registered target only subscribes to "push").
local _fd_calls = {}
local _real_deliver_fire = deliver_fire
deliver_fire = function(
  tgt,
  backend,
  event_type,
  payload,
  internal_event,
  translators,
  github_translators
) -- luacheck: globals deliver_fire
  _fd_calls[#_fd_calls + 1] = {
    tgt = tgt,
    backend = backend,
    event_type = event_type,
    payload = payload,
    internal_event = internal_event,
    translators = translators,
    github_translators = github_translators,
  }
  return true, 200, nil
end

-- fanout_dispatch with no matching targets (event "create" vs. pre-registered "push") → 0.
local fd0 = fanout_dispatch("gitea", "create", { ref = "refs/tags/v1.0" })
eq(fd0, 0, "fanout_dispatch no matching targets: returns 0 for unsubscribed event")

-- Register a wildcard target and verify dispatch calls deliver_fire.
fanout_register_target({
  url = "https://fd-test.example.com/hook",
  name = "fd-wildcard",
  events = { "*" },
})

_fd_calls = {}
local fd1 = fanout_dispatch("gitea", "create", { ref = "refs/tags/v1.0" })
eq(fd1, 1, "fanout_dispatch wildcard: returns 1 for matching wildcard target")
ok(#_fd_calls == 1, "fanout_dispatch wildcard: deliver_fire called once")
eq(_fd_calls[1].backend, "gitea", "fanout_dispatch wildcard: backend passed to deliver_fire")
eq(_fd_calls[1].event_type, "create", "fanout_dispatch wildcard: event_type passed")
eq(_fd_calls[1].tgt.url, "https://fd-test.example.com/hook", "fanout_dispatch wildcard: target url")
eq(_fd_calls[1].tgt.name, "fd-wildcard", "fanout_dispatch wildcard: target name")

-- fanout_dispatch with non-matching event type for an issues-only target.
fanout_register_target({ url = "https://filtered.example.com/hook", events = { "issues" } })
_fd_calls = {}
local fd2 = fanout_dispatch("gitea", "create", { ref = "refs/tags/v1.0" })
-- Only the wildcard matches "create"; issues-only target does not.
eq(fd2, 1, "fanout_dispatch filtered: issues-only target does not match create")
eq(
  _fd_calls[1].tgt.url,
  "https://fd-test.example.com/hook",
  "fanout_dispatch filtered: correct target fired"
)
eq(_fd_calls[1].tgt.name, "fd-wildcard", "fanout_dispatch filtered: preserves named target")

-- Matching event type delivers to both wildcard and issues targets.
_fd_calls = {}
local fd3_internal = make_internal_event({
  event = "issues",
  action = "opened",
  provider = "gitea",
  raw = { action = "opened" },
  data = {},
})
local fd3_translators = { issues = function() end }
local fd3_github_translators = { issues = function() end }
local fd3 = fanout_dispatch(
  "gitea",
  "issues",
  { action = "opened" },
  fd3_internal,
  fd3_translators,
  fd3_github_translators
)
eq(fd3, 2, "fanout_dispatch match: wildcard and issues targets both match issues event")
eq(_fd_calls[2].tgt.name, "default", "fanout_dispatch default: unnamed target defaults to default")
eq(_fd_calls[1].internal_event, fd3_internal, "fanout_dispatch: forwards internal event")
eq(_fd_calls[1].translators, fd3_translators, "fanout_dispatch: forwards normalized translators")
eq(
  _fd_calls[1].github_translators,
  fd3_github_translators,
  "fanout_dispatch: forwards GitHub-shape translators"
)

deliver_fire = _real_deliver_fire -- luacheck: globals deliver_fire

-- ============================================================
-- deliver_fire (internal/deliver.lua)
-- ============================================================

-- luacheck: globals deliver_fire sign_for_backend

do
  -- Set up a mock Fetch to capture outbound calls.
  local _df_last_url = nil
  local _df_last_opts = nil
  local _df_mock_status = 200
  local _df_mock_error = nil
  local _real_Fetch = Fetch
  Fetch = function(url, opts) -- luacheck: globals Fetch
    _df_last_url = url
    _df_last_opts = opts
    if _df_mock_error ~= nil then
      error(_df_mock_error)
    end
    return _df_mock_status, {}, "{}"
  end

  local target_github = {
    url = "https://df-test.example.com/hook",
    shape = "github",
    secret = "",
  }

  -- deliver_fire: 200 → ok=true, http_status=200, no error.
  _df_mock_status = 200
  local ok1, s1, e1 = deliver_fire(target_github, "gitea", "push", { ref = "refs/heads/main" })
  ok(ok1 == true, "deliver_fire 200: ok is true")
  eq(s1, 200, "deliver_fire 200: http_status is 200")
  ok(e1 == nil, "deliver_fire 200: error is nil")
  eq(_df_last_url, "https://df-test.example.com/hook", "deliver_fire: posts to target url")
  eq(_df_last_opts.method, "POST", "deliver_fire: method is POST")
  ok(_df_last_opts.body ~= nil, "deliver_fire: body is set")
  eq(
    _df_last_opts.headers["Content-Type"],
    "application/json",
    "deliver_fire: Content-Type is application/json"
  )
  eq(
    _df_last_opts.headers["X-GitHub-Event"],
    "push",
    "deliver_fire github shape: X-GitHub-Event header"
  )
  ok(
    _df_last_opts.headers["X-GitHub-Delivery"] ~= nil,
    "deliver_fire github shape: X-GitHub-Delivery header present"
  )

  local github_internal = make_internal_event({
    event = "issues",
    action = "opened",
    provider = "gitea",
    raw = { action = "opened" },
    data = { issue = { number = 1 } },
  })
  local ok_github_translated = deliver_fire(
    target_github,
    "gitea",
    "issues",
    { action = "opened" },
    github_internal,
    nil,
    {
      issues = function(ev, fields)
        return {
          action = ev.action,
          delivery_id = fields.id,
          issue = ev.data.issue,
        }
      end,
    }
  )
  ok(ok_github_translated == true, "deliver_fire github translator: ok is true")
  local github_translated_body = DecodeJson(_df_last_opts.body)
  eq(
    github_translated_body.delivery_id,
    _df_last_opts.headers["X-GitHub-Delivery"],
    "deliver_fire github translator: body id matches delivery header"
  )
  eq(github_translated_body.issue.number, 1, "deliver_fire github translator: body translated")

  -- deliver_fire: 503 → ok=false.
  _df_mock_status = 503
  local ok2, s2, e2 = deliver_fire(target_github, "gitea", "push", { ref = "refs/heads/main" })
  ok(ok2 == false, "deliver_fire 503: ok is false")
  eq(s2, 503, "deliver_fire 503: http_status is 503")
  ok(e2 == nil, "deliver_fire 503: no error string on HTTP failure")

  -- deliver_fire: network error → ok=false, http_status=nil, error message set.
  _df_mock_status = 200
  _df_mock_error = "connection refused"
  local ok3, s3, e3 = deliver_fire(target_github, "gitea", "push", { ref = "refs/heads/main" })
  ok(ok3 == false, "deliver_fire network error: ok is false")
  ok(s3 == nil, "deliver_fire network error: http_status is nil")
  ok(e3 ~= nil, "deliver_fire network error: error message set")
  _df_mock_error = nil

  -- deliver_fire: confusio shape uses X-Confusio-* headers.
  local target_confusio = {
    url = "https://df-confusio.example.com/hook",
    shape = "confusio",
    secret = "",
  }
  _df_mock_status = 200
  local ok4 = deliver_fire(target_confusio, "gitea", "push", { ref = "refs/heads/main" })
  ok(ok4 == true, "deliver_fire confusio shape: ok is true")
  eq(
    _df_last_opts.headers["X-Confusio-Event"],
    "push",
    "deliver_fire confusio shape: X-Confusio-Event header"
  )
  eq(
    _df_last_opts.headers["X-Confusio-Source"],
    "gitea",
    "deliver_fire confusio shape: X-Confusio-Source is backend"
  )
  ok(
    _df_last_opts.headers["X-Confusio-Delivery"] ~= nil,
    "deliver_fire confusio shape: X-Confusio-Delivery present"
  )
  ok(
    _df_last_opts.headers["X-GitHub-Event"] == nil,
    "deliver_fire confusio shape: no X-GitHub-Event header"
  )
  local confusio_body = DecodeJson(_df_last_opts.body)
  eq(
    confusio_body.id,
    _df_last_opts.headers["X-Confusio-Delivery"],
    "deliver_fire confusio shape: body id matches delivery header"
  )
  eq(confusio_body.type, "push", "deliver_fire confusio shape: body type is normalized event")

  -- deliver_fire: secret present → backend-native signature header included.
  local target_signed = {
    url = "https://df-signed.example.com/hook",
    shape = "github",
    secret = "test-hmac-secret",
  }
  _df_mock_status = 200
  deliver_fire(target_signed, "gitea", "push", { ref = "refs/heads/main" })
  ok(
    _df_last_opts.headers["X-Gitea-Signature"] ~= nil,
    "deliver_fire with secret: X-Gitea-Signature header present for gitea backend"
  )

  -- deliver_fire: delivery attempts are logged in Redbean-style request form.
  local target_logged = {
    name = "logged-target",
    url = "https://df-logged.example.com/hook",
    shape = "github",
    secret = "",
  }
  local _log_calls = {}
  local _real_Log = Log
  Log = function(level, msg) -- luacheck: globals Log
    _log_calls[#_log_calls + 1] = { level = level, msg = msg }
  end

  _df_mock_status = 202
  _log_calls = {}
  deliver_fire(target_logged, "gitea", "push", { ref = "refs/heads/main" })
  ok(#_log_calls == 1, "deliver_fire success: Log called once")
  eq(_log_calls[1].level, kLogVerbose, "deliver_fire success: logged at kLogVerbose") -- luacheck: globals kLogVerbose
  ok(
    _log_calls[1].msg:find('"POST https://df%-logged%.example%.com/hook HTTP/1%.1" 202') ~= nil,
    "deliver_fire success: log uses Redbean-style request format"
  )
  ok(_log_calls[1].msg:find("target=logged%-target") ~= nil, "deliver_fire success: target logged")
  ok(_log_calls[1].msg:find("backend=gitea") ~= nil, "deliver_fire success: backend logged")
  ok(_log_calls[1].msg:find("event=push") ~= nil, "deliver_fire success: event logged")
  ok(
    _log_calls[1].msg:find("delivery=" .. _df_last_opts.headers["X-GitHub-Delivery"], 1, true)
      ~= nil,
    "deliver_fire success: delivery id logged"
  )
  ok(_log_calls[1].msg:find("ms") ~= nil, "deliver_fire success: duration logged")
  ok(_log_calls[1].msg:find("error=") == nil, "deliver_fire success: no error logged")

  -- deliver_fire: HTTP failures are logged with status and no error string.
  _df_mock_status = 503
  _log_calls = {}
  deliver_fire(target_logged, "gitea", "push", { ref = "refs/heads/main" })
  ok(#_log_calls == 1, "deliver_fire 503: Log called once")
  eq(_log_calls[1].level, kLogWarn, "deliver_fire 503: logged at kLogWarn") -- luacheck: globals kLogWarn
  ok(
    _log_calls[1].msg:find('"POST https://df%-logged%.example%.com/hook HTTP/1%.1" 503') ~= nil,
    "deliver_fire 503: log contains request and status"
  )
  ok(_log_calls[1].msg:find("error=") == nil, "deliver_fire 503: no error logged")

  -- deliver_fire: network failures are logged with an error and no status.
  _df_mock_status = 200
  _df_mock_error = "connection refused"
  _log_calls = {}
  deliver_fire(target_logged, "gitea", "push", { ref = "refs/heads/main" })
  ok(#_log_calls == 1, "deliver_fire network error: Log called once")
  eq(_log_calls[1].level, kLogWarn, "deliver_fire network error: logged at kLogWarn")
  ok(
    _log_calls[1].msg:find('"POST https://df%-logged%.example%.com/hook HTTP/1%.1" 000') ~= nil,
    "deliver_fire network error: log uses zero status"
  )
  ok(_log_calls[1].msg:find("error=") ~= nil, "deliver_fire network error: log contains error=")
  ok(
    _log_calls[1].msg:find("connection refused", 1, true) ~= nil,
    "deliver_fire network error: error text logged"
  )
  _df_mock_error = nil

  -- Restore Log and Fetch.
  Log = _real_Log
  Fetch = _real_Fetch
end

-- ============================================================
-- webhook_target CLI SCRIPTARG wiring
-- ============================================================

do
  -- Verify fanout_register_target is callable and accepts valid/invalid entries.
  -- The startup webhook_target=URL arg already registered a target at load time;
  -- here we only verify the function's guard behaviour.
  -- We cannot enumerate _fanout_targets directly, but dispatch to the
  -- startup-registered URL should hit it.  Instead, verify fanout_register_target
  -- is callable (wired correctly) and that valid/invalid entries behave correctly.

  -- Valid entry: silently accepted (no error).
  local ok_reg = pcall(fanout_register_target, {
    url = "https://hook.example.com/wt-unit",
    events = { "push", "pull_request" },
    shape = "confusio",
  })
  ok(ok_reg, "webhook_target CLI arg: fanout_register_target with valid entry succeeds")

  -- Invalid entries: silently ignored.
  local ok_bad1 = pcall(fanout_register_target, {})
  local ok_bad2 = pcall(fanout_register_target, { url = "" })
  local ok_bad3 = pcall(fanout_register_target, { url = 42 })
  ok(ok_bad1, "webhook_target CLI arg: empty table silently ignored")
  ok(ok_bad2, "webhook_target CLI arg: empty url silently ignored")
  ok(ok_bad3, "webhook_target CLI arg: non-string url silently ignored")
end

-- ============================================================
-- Summary line placeholder (kept to end-of-file)
-- ============================================================

-- NOTE: outbox, target CRUD, deliver_attempt, deliveries_api, pruner, retry,
-- and circuit_breaker modules were removed.  The webhook system now uses
-- fire-and-record delivery: deliver_fire is called synchronously with no
-- persistence, retry scheduler, or circuit breaker.  See CLAUDE.md.

-- (end of webhook fire-and-record tests)

-- ============================================================
-- synthesize_startup_events (internal/startup.lua)
-- ============================================================

do
  -- luacheck: globals synthesize_startup_events fanout_dispatch

  -- Stub fanout_dispatch to capture dispatch calls without real delivery.
  local _se_calls = {}
  local _real_fanout_dispatch = fanout_dispatch
  fanout_dispatch = function(backend, event_type, payload) -- luacheck: globals fanout_dispatch
    _se_calls[#_se_calls + 1] = {
      backend = backend,
      event_type = event_type,
      payload = payload,
    }
    return 0
  end

  -- No-op when backend is "" (no backend configured).
  _se_calls = {}
  synthesize_startup_events("", "https://example.com")
  eq(#_se_calls, 0, "synthesize_startup_events: empty backend → no dispatch calls")

  -- Two events dispatched when backend is non-empty.
  _se_calls = {}
  synthesize_startup_events("testbackend", "https://git.example.com")
  eq(#_se_calls, 2, "synthesize_startup_events: two events dispatched for non-empty backend")

  -- First event: installation.created
  eq(_se_calls[1].backend, "testbackend", "synthesize_startup_events: event 1 backend")
  eq(
    _se_calls[1].event_type,
    "installation",
    "synthesize_startup_events: event 1 type is installation"
  )
  eq(
    _se_calls[1].payload.action,
    "created",
    "synthesize_startup_events: installation action is 'created'"
  )
  ok(
    type(_se_calls[1].payload.installation) == "table",
    "synthesize_startup_events: installation field is a table"
  )
  eq(
    _se_calls[1].payload.installation.app_slug,
    "confusio",
    "synthesize_startup_events: installation.app_slug is 'confusio'"
  )
  eq(
    _se_calls[1].payload.installation.account.login,
    "testbackend",
    "synthesize_startup_events: installation.account.login is backend name"
  )
  eq(
    _se_calls[1].payload.installation.account.url,
    "https://git.example.com",
    "synthesize_startup_events: installation.account.url is base_url"
  )
  eq(
    _se_calls[1].payload.installation.repository_selection,
    "all",
    "synthesize_startup_events: installation.repository_selection is 'all'"
  )
  ok(
    type(_se_calls[1].payload.sender) == "table",
    "synthesize_startup_events: sender field is a table"
  )
  eq(
    _se_calls[1].payload.sender.login,
    "confusio",
    "synthesize_startup_events: sender.login is 'confusio'"
  )

  -- Second event: installation_repositories.added
  eq(
    _se_calls[2].event_type,
    "installation_repositories",
    "synthesize_startup_events: event 2 type is installation_repositories"
  )
  eq(
    _se_calls[2].payload.action,
    "added",
    "synthesize_startup_events: installation_repositories action is 'added'"
  )
  eq(
    _se_calls[2].payload.repository_selection,
    "all",
    "synthesize_startup_events: installation_repositories.repository_selection is 'all'"
  )
  ok(
    type(_se_calls[2].payload.repositories_added) == "table",
    "synthesize_startup_events: repositories_added is a table"
  )
  ok(
    type(_se_calls[2].payload.repositories_removed) == "table",
    "synthesize_startup_events: repositories_removed is a table"
  )

  -- Both events share the same installation object (same content at minimum).
  eq(
    _se_calls[1].payload.installation.app_slug,
    _se_calls[2].payload.installation.app_slug,
    "synthesize_startup_events: both events share same installation object"
  )

  -- created_at / updated_at are ISO 8601 strings.
  local inst = _se_calls[1].payload.installation
  ok(
    type(inst.created_at) == "string" and inst.created_at:match("^%d%d%d%d%-%d%d%-%d%dT"),
    "synthesize_startup_events: installation.created_at is ISO 8601 string"
  )
  eq(inst.created_at, inst.updated_at, "synthesize_startup_events: created_at == updated_at")

  -- Restore fanout_dispatch.
  fanout_dispatch = _real_fanout_dispatch -- luacheck: globals fanout_dispatch
end

-- ============================================================
-- Summary
-- ============================================================

io.write(string.format("\n%d passed, %d failed\n", PASS, FAIL))
if FAIL > 0 then
  os.exit(1)
end
