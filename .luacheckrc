-- luacheck configuration for confusio
std = "lua54"
exclude_files = { ".luarocks/" }
max_line_length = 200

globals = {
  -- Redbean built-ins: request inspection
  "GetMethod",
  "GetPath",
  "GetHeader",
  "GetParam",
  "GetBody",
  -- Redbean built-ins: response building
  "SetStatus",
  "SetHeader",
  "Write",
  -- Redbean built-ins: networking and encoding
  "Fetch",
  "EncodeJson",
  "DecodeJson",
  "EncodeBase64",
  -- Redbean built-ins: routing
  "Route",
  "OnHttpRequest",
  -- App globals defined in .init.lua, read by backends/*.lua
  "config",
  "respond_json",
  "proxy_json",
  "proxy_json_created",
  "append_page_params",
  "make_fetch_opts",
  "make_proxy_handler",
  "translate_repo",
  "translate_user",
  -- Set by backends/*.lua, read by .init.lua
  "backend_impl",
}
