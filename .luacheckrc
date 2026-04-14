-- luacheck configuration for confusio
std = "lua54"
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
  "EscapeParam",
  -- Redbean built-ins: routing
  "Route",
  "OnHttpRequest",
  -- App globals defined in .init.lua, read by backends/*.lua
  "provider_families",
  "config",
  "set_preamble",
  "respond_json",
  "proxy_json",
  "proxy_json_paged",
  "proxy_json_created",
  "rewrite_link_header",
  "append_page_params",
  "make_fetch_opts",
  "make_proxy_handler",
  "translate_repo",
  "translate_user",
  "translate_migration",
  -- Set by backends/*.lua, read by .init.lua
  "backend_impl",
  "backend_allow_anonymous",
  -- Endpoint catalog: populated by .init.lua, read by scripts/dump-endpoints.lua
  "endpoints",
}
