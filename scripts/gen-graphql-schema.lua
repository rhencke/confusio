-- Parse the vendored GitHub GraphQL SDL and emit internal/graphql_schema_data.lua.
--
-- Usage: ./redbean.com -i scripts/gen-graphql-schema.lua [sdl] [output]
--
--   sdl     path to SDL file  (default: vendor/github-graphql-schema/schema.docs.graphql)
--   output  path to write Lua (default: internal/graphql_schema_data.lua)
--
-- The output is a Lua table literal assigning a global `graphql_schema_data`.
-- Only types reachable from the Query and Mutation root types are included,
-- plus built-in scalars and introspection meta-types.

local sdl_path = (arg and arg[1]) or "vendor/github-graphql-schema/schema.docs.graphql" -- luacheck: globals arg
local out_path = (arg and arg[2]) or "internal/graphql_schema_data.lua" -- luacheck: globals arg

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function read_file(path)
  local f = assert(io.open(path, "r"))
  local text = f:read("*a")
  f:close()
  return text
end

-- ---------------------------------------------------------------------------
-- SDL tokeniser
-- ---------------------------------------------------------------------------

local function dedent_block_string(raw)
  local lines = {}
  for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
  end
  -- Find common indent of non-empty lines after the first
  local common_indent
  for i = 2, #lines do
    local stripped = lines[i]:match("^[ \t]*(.*)")
    if stripped ~= "" then
      local indent = #lines[i] - #stripped
      if common_indent == nil or indent < common_indent then
        common_indent = indent
      end
    end
  end
  if common_indent and common_indent > 0 then
    for i = 2, #lines do
      if #lines[i] >= common_indent then
        lines[i] = lines[i]:sub(common_indent + 1)
      end
    end
  end
  -- Strip leading blank lines
  while #lines > 0 and lines[1]:match("^%s*$") do
    table.remove(lines, 1)
  end
  -- Strip trailing blank lines
  while #lines > 0 and lines[#lines]:match("^%s*$") do
    table.remove(lines)
  end
  return table.concat(lines, "\n")
end

local function tokenize(text)
  local tokens = {}
  local pos = 1
  local len = #text
  while pos <= len do
    local ch = text:sub(pos, pos)
    -- Whitespace
    if ch:match("%s") then
      pos = pos + 1
    -- Comment
    elseif ch == "#" then
      local nl = text:find("\n", pos)
      pos = nl and (nl + 1) or (len + 1)
    -- Block string
    elseif text:sub(pos, pos + 2) == '"""' then
      local end_pos = text:find('"""', pos + 3, true)
      assert(end_pos, "unterminated block string at position " .. pos)
      local raw = text:sub(pos + 3, end_pos - 1)
      tokens[#tokens + 1] = { "STRING", dedent_block_string(raw) }
      pos = end_pos + 3
    -- String
    elseif ch == '"' then
      local end_pos = pos + 1
      while end_pos <= len do
        local c = text:sub(end_pos, end_pos)
        if c == "\\" then
          end_pos = end_pos + 2
        elseif c == '"' then
          break
        else
          end_pos = end_pos + 1
        end
      end
      local raw = text:sub(pos + 1, end_pos - 1)
      raw = raw:gsub('\\"', '"'):gsub("\\\\", "\\")
      tokens[#tokens + 1] = { "STRING", raw }
      pos = end_pos + 1
    -- Number (including negative)
    elseif
      ch:match("%d") or (ch == "-" and pos + 1 <= len and text:sub(pos + 1, pos + 1):match("%d"))
    then
      local _, e = text:find("%-?%d+%.?%d*", pos)
      -- Handle exponent
      if e and e + 1 <= len and text:sub(e + 1, e + 1):match("[eE]") then
        local _, e2 = text:find("[eE][%+%-]?%d+", e + 1)
        if e2 then
          e = e2
        end
      end
      tokens[#tokens + 1] = { "NUMBER", text:sub(pos, e) }
      pos = e + 1
    -- Name
    elseif ch:match("[_%a]") then
      local _, e = text:find("[_%w]+", pos)
      tokens[#tokens + 1] = { "NAME", text:sub(pos, e) }
      pos = e + 1
    -- Punctuation
    elseif
      ch == "{"
      or ch == "}"
      or ch == "("
      or ch == ")"
      or ch == "["
      or ch == "]"
      or ch == "!"
      or ch == ":"
      or ch == "="
      or ch == "|"
      or ch == "&"
      or ch == "@"
    then
      tokens[#tokens + 1] = { "PUNCT", ch }
      pos = pos + 1
    else
      -- Skip unknown characters
      pos = pos + 1
    end
  end
  return tokens
end

-- ---------------------------------------------------------------------------
-- SDL parser
-- ---------------------------------------------------------------------------

local function make_parser(text)
  local tokens = tokenize(text)
  local pos = 1

  local P = {}

  function P.peek(offset)
    local i = pos + (offset or 0)
    if i <= #tokens then
      return tokens[i]
    end
    return { "EOF", "" }
  end

  function P.advance()
    local tok = tokens[pos]
    pos = pos + 1
    return tok
  end

  function P.expect(kind, value)
    local tok = P.advance()
    if tok[1] ~= kind or (value ~= nil and tok[2] ~= value) then
      error(
        string.format(
          "Expected (%s, %s), got (%s, %s) at pos %d",
          kind,
          tostring(value),
          tok[1],
          tok[2],
          pos
        )
      )
    end
    return tok
  end

  function P.expect_punct(ch)
    return P.expect("PUNCT", ch)
  end

  function P.at_end()
    return pos > #tokens
  end

  -- Forward declarations
  local maybe_description, parse_implements, skip_directives, parse_field_defs
  local parse_field_def, parse_arguments_def, parse_input_value_def
  local parse_type_ref, parse_default_value, parse_value_literal
  local has_deprecated_directive, skip_balanced, parse_directive_def
  local skip_schema_def, skip_extend_def

  maybe_description = function()
    if not P.at_end() and P.peek()[1] == "STRING" then
      return P.advance()[2]
    end
    return nil
  end

  parse_implements = function()
    local interfaces = {}
    if not P.at_end() and P.peek()[1] == "NAME" and P.peek()[2] == "implements" then
      P.advance()
      -- Optional leading &
      if not P.at_end() and P.peek()[1] == "PUNCT" and P.peek()[2] == "&" then
        P.advance()
      end
      interfaces[#interfaces + 1] = P.expect("NAME")[2]
      while not P.at_end() and P.peek()[1] == "PUNCT" and P.peek()[2] == "&" do
        P.advance()
        interfaces[#interfaces + 1] = P.expect("NAME")[2]
      end
    end
    return interfaces
  end

  skip_balanced = function(open_ch, close_ch)
    P.expect_punct(open_ch)
    local depth = 1
    while depth > 0 and not P.at_end() do
      local tok = P.advance()
      if tok[1] == "PUNCT" and tok[2] == open_ch then
        depth = depth + 1
      elseif tok[1] == "PUNCT" and tok[2] == close_ch then
        depth = depth - 1
      end
    end
  end

  skip_directives = function()
    while not P.at_end() and P.peek()[1] == "PUNCT" and P.peek()[2] == "@" do
      P.advance() -- @
      P.expect("NAME") -- directive name
      if not P.at_end() and P.peek()[1] == "PUNCT" and P.peek()[2] == "(" then
        skip_balanced("(", ")")
      end
    end
  end

  has_deprecated_directive = function()
    if
      not P.at_end()
      and P.peek()[1] == "PUNCT"
      and P.peek()[2] == "@"
      and pos + 1 <= #tokens
      and tokens[pos + 1][1] == "NAME"
      and tokens[pos + 1][2] == "deprecated"
    then
      return true
    end
    return false
  end

  parse_type_ref = function()
    local s
    if not P.at_end() and P.peek()[1] == "PUNCT" and P.peek()[2] == "[" then
      P.advance()
      local inner = parse_type_ref()
      P.expect_punct("]")
      s = "[" .. inner .. "]"
    else
      s = P.expect("NAME")[2]
    end
    if not P.at_end() and P.peek()[1] == "PUNCT" and P.peek()[2] == "!" then
      P.advance()
      s = s .. "!"
    end
    return s
  end

  local parse_list_value, parse_object_value

  parse_value_literal = function()
    local tok = P.peek()
    if tok[1] == "STRING" then
      P.advance()
      return '"' .. tok[2] .. '"'
    elseif tok[1] == "NAME" then
      P.advance()
      return tok[2]
    elseif tok[1] == "NUMBER" then
      P.advance()
      return tok[2]
    elseif tok[1] == "PUNCT" and tok[2] == "[" then
      return parse_list_value()
    elseif tok[1] == "PUNCT" and tok[2] == "{" then
      return parse_object_value()
    else
      P.advance()
      return tok[2]
    end
  end

  parse_list_value = function()
    P.advance() -- [
    local items = {}
    while not P.at_end() and not (P.peek()[1] == "PUNCT" and P.peek()[2] == "]") do
      items[#items + 1] = parse_value_literal()
    end
    P.expect_punct("]")
    return "[" .. table.concat(items, ", ") .. "]"
  end

  parse_object_value = function()
    P.advance() -- {
    local pairs_list = {}
    while not P.at_end() and not (P.peek()[1] == "PUNCT" and P.peek()[2] == "}") do
      local k = P.expect("NAME")[2]
      P.expect_punct(":")
      local v = parse_value_literal()
      pairs_list[#pairs_list + 1] = k .. ": " .. v
    end
    P.expect_punct("}")
    return "{" .. table.concat(pairs_list, ", ") .. "}"
  end

  parse_default_value = function()
    if P.at_end() or P.peek()[1] ~= "PUNCT" or P.peek()[2] ~= "=" then
      return nil
    end
    P.advance() -- =
    return parse_value_literal()
  end

  parse_input_value_def = function()
    local desc = maybe_description()
    local name = P.expect("NAME")[2]
    P.expect_punct(":")
    local type_ref = parse_type_ref()
    local default = parse_default_value()
    skip_directives()
    return { name = name, type = type_ref, description = desc, default_value = default }
  end

  parse_arguments_def = function()
    if P.at_end() or P.peek()[1] ~= "PUNCT" or P.peek()[2] ~= "(" then
      return {}
    end
    P.advance() -- (
    local args = {}
    while not P.at_end() and not (P.peek()[1] == "PUNCT" and P.peek()[2] == ")") do
      args[#args + 1] = parse_input_value_def()
    end
    P.expect_punct(")")
    return args
  end

  parse_field_def = function()
    local desc = maybe_description()
    local name = P.expect("NAME")[2]
    local args = parse_arguments_def()
    P.expect_punct(":")
    local type_ref = parse_type_ref()
    skip_directives()
    return { name = name, type = type_ref, description = desc, args = args }
  end

  parse_field_defs = function()
    P.expect_punct("{")
    local fields = {}
    while not P.at_end() and not (P.peek()[1] == "PUNCT" and P.peek()[2] == "}") do
      fields[#fields + 1] = parse_field_def()
    end
    P.expect_punct("}")
    return fields
  end

  local function parse_object_type(desc)
    P.expect("NAME", "type")
    local name = P.expect("NAME")[2]
    local interfaces = parse_implements()
    skip_directives()
    local fields = parse_field_defs()
    return {
      kind = "OBJECT",
      name = name,
      description = desc,
      interfaces = interfaces,
      fields = fields,
    }
  end

  local function parse_interface_type(desc)
    P.expect("NAME", "interface")
    local name = P.expect("NAME")[2]
    local interfaces = parse_implements()
    skip_directives()
    local fields = parse_field_defs()
    return {
      kind = "INTERFACE",
      name = name,
      description = desc,
      interfaces = interfaces,
      fields = fields,
    }
  end

  local function parse_union_type(desc)
    P.expect("NAME", "union")
    local name = P.expect("NAME")[2]
    skip_directives()
    P.expect_punct("=")
    -- Optional leading |
    if not P.at_end() and P.peek()[1] == "PUNCT" and P.peek()[2] == "|" then
      P.advance()
    end
    local members = { P.expect("NAME")[2] }
    while not P.at_end() and P.peek()[1] == "PUNCT" and P.peek()[2] == "|" do
      P.advance()
      members[#members + 1] = P.expect("NAME")[2]
    end
    return { kind = "UNION", name = name, description = desc, possible_types = members }
  end

  local function parse_enum_type(desc)
    P.expect("NAME", "enum")
    local name = P.expect("NAME")[2]
    skip_directives()
    P.expect_punct("{")
    local values = {}
    while not P.at_end() and not (P.peek()[1] == "PUNCT" and P.peek()[2] == "}") do
      local vdesc = maybe_description()
      local vname = P.expect("NAME")[2]
      local deprecated = has_deprecated_directive()
      skip_directives()
      values[#values + 1] = { name = vname, description = vdesc, is_deprecated = deprecated }
    end
    P.expect_punct("}")
    return { kind = "ENUM", name = name, description = desc, values = values }
  end

  local function parse_input_object_type(desc)
    P.expect("NAME", "input")
    local name = P.expect("NAME")[2]
    skip_directives()
    P.expect_punct("{")
    local fields = {}
    while not P.at_end() and not (P.peek()[1] == "PUNCT" and P.peek()[2] == "}") do
      fields[#fields + 1] = parse_input_value_def()
    end
    P.expect_punct("}")
    return { kind = "INPUT_OBJECT", name = name, description = desc, input_fields = fields }
  end

  local function parse_scalar_type(desc)
    P.expect("NAME", "scalar")
    local name = P.expect("NAME")[2]
    skip_directives()
    return { kind = "SCALAR", name = name, description = desc }
  end

  parse_directive_def = function(desc)
    P.expect("NAME", "directive")
    P.expect_punct("@")
    local name = P.expect("NAME")[2]
    local args = parse_arguments_def()
    local is_repeatable = false
    if not P.at_end() and P.peek()[1] == "NAME" and P.peek()[2] == "repeatable" then
      P.advance()
      is_repeatable = true
    end
    P.expect("NAME", "on")
    local locations = { P.expect("NAME")[2] }
    while not P.at_end() and P.peek()[1] == "PUNCT" and P.peek()[2] == "|" do
      P.advance()
      locations[#locations + 1] = P.expect("NAME")[2]
    end
    return {
      name = name,
      description = desc,
      args = args,
      locations = locations,
      is_repeatable = is_repeatable,
    }
  end

  skip_schema_def = function()
    P.expect("NAME", "schema")
    skip_directives()
    if not P.at_end() and P.peek()[1] == "PUNCT" and P.peek()[2] == "{" then
      skip_balanced("{", "}")
    end
  end

  skip_extend_def = function()
    P.expect("NAME", "extend")
    local tok = P.peek()
    if tok[1] == "NAME" and tok[2] == "schema" then
      skip_schema_def()
    elseif
      tok[1] == "NAME" and (tok[2] == "type" or tok[2] == "interface" or tok[2] == "input")
    then
      P.advance()
      P.expect("NAME")
      parse_implements()
      skip_directives()
      if not P.at_end() and P.peek()[1] == "PUNCT" and P.peek()[2] == "{" then
        skip_balanced("{", "}")
      end
    elseif tok[1] == "NAME" and tok[2] == "union" then
      P.advance()
      P.expect("NAME")
      skip_directives()
      if not P.at_end() and P.peek()[1] == "PUNCT" and P.peek()[2] == "=" then
        P.advance()
        P.expect("NAME")
        while not P.at_end() and P.peek()[1] == "PUNCT" and P.peek()[2] == "|" do
          P.advance()
          P.expect("NAME")
        end
      end
    elseif tok[1] == "NAME" and tok[2] == "enum" then
      P.advance()
      P.expect("NAME")
      skip_directives()
      if not P.at_end() and P.peek()[1] == "PUNCT" and P.peek()[2] == "{" then
        skip_balanced("{", "}")
      end
    elseif tok[1] == "NAME" and tok[2] == "scalar" then
      P.advance()
      P.expect("NAME")
      skip_directives()
    end
  end

  function P.parse()
    local types = {}
    local directives = {}
    while not P.at_end() do
      local desc = maybe_description()
      if P.at_end() then
        break
      end
      local tok = P.peek()
      if tok[1] == "NAME" then
        local td
        if tok[2] == "type" then
          td = parse_object_type(desc)
        elseif tok[2] == "interface" then
          td = parse_interface_type(desc)
        elseif tok[2] == "union" then
          td = parse_union_type(desc)
        elseif tok[2] == "enum" then
          td = parse_enum_type(desc)
        elseif tok[2] == "input" then
          td = parse_input_object_type(desc)
        elseif tok[2] == "scalar" then
          td = parse_scalar_type(desc)
        elseif tok[2] == "directive" then
          local dd = parse_directive_def(desc)
          directives[dd.name] = dd
        elseif tok[2] == "schema" then
          skip_schema_def()
        elseif tok[2] == "extend" then
          skip_extend_def()
        else
          P.advance()
        end
        if td then
          types[td.name] = td
        end
      else
        P.advance()
      end
    end
    return types, directives
  end

  return P
end

-- ---------------------------------------------------------------------------
-- Reachability analysis
-- ---------------------------------------------------------------------------

local function base_type(type_ref)
  return type_ref:match("[_%a][_%w]*")
end

local function compute_reachable(types, roots)
  local visited = {}
  local stack = {}
  for _, r in ipairs(roots) do
    stack[#stack + 1] = r
  end
  while #stack > 0 do
    local name = table.remove(stack)
    if visited[name] then
      goto continue
    end
    visited[name] = true
    local td = types[name]
    if td == nil then
      goto continue
    end
    local kind = td.kind
    if kind == "OBJECT" or kind == "INTERFACE" then
      for _, iface in ipairs(td.interfaces or {}) do
        stack[#stack + 1] = iface
      end
      for _, field in ipairs(td.fields or {}) do
        local bt = base_type(field.type)
        if bt then
          stack[#stack + 1] = bt
        end
        for _, a in ipairs(field.args or {}) do
          bt = base_type(a.type)
          if bt then
            stack[#stack + 1] = bt
          end
        end
      end
    elseif kind == "UNION" then
      for _, member in ipairs(td.possible_types or {}) do
        stack[#stack + 1] = member
      end
    elseif kind == "INPUT_OBJECT" then
      for _, f in ipairs(td.input_fields or {}) do
        local bt = base_type(f.type)
        if bt then
          stack[#stack + 1] = bt
        end
      end
    end
    ::continue::
  end
  return visited
end

-- ---------------------------------------------------------------------------
-- Populate interface possible_types (reverse mapping)
-- ---------------------------------------------------------------------------

local function populate_possible_types(types, reachable)
  local iface_impls = {}
  for name in pairs(reachable) do
    local td = types[name]
    if td and td.kind == "OBJECT" then
      for _, iface in ipairs(td.interfaces or {}) do
        if reachable[iface] then
          if not iface_impls[iface] then
            iface_impls[iface] = {}
          end
          iface_impls[iface][#iface_impls[iface] + 1] = name
        end
      end
    end
  end
  for name in pairs(reachable) do
    local td = types[name]
    if td and td.kind == "INTERFACE" then
      local impls = iface_impls[name] or {}
      table.sort(impls)
      td.possible_types = impls
    end
  end
end

-- ---------------------------------------------------------------------------
-- Built-in scalars and introspection meta-types
-- ---------------------------------------------------------------------------

local BUILTIN_SCALARS = {
  String = {
    kind = "SCALAR",
    name = "String",
    description = "The `String` scalar type represents textual data, represented as UTF-8 character sequences.",
  },
  Int = {
    kind = "SCALAR",
    name = "Int",
    description = "The `Int` scalar type represents non-fractional signed whole numeric values.",
  },
  Float = {
    kind = "SCALAR",
    name = "Float",
    description = "The `Float` scalar type represents signed double-precision fractional values.",
  },
  Boolean = {
    kind = "SCALAR",
    name = "Boolean",
    description = "The `Boolean` scalar type represents `true` or `false`.",
  },
  ID = {
    kind = "SCALAR",
    name = "ID",
    description = "The `ID` scalar type represents a unique identifier.",
  },
}

local INTROSPECTION_TYPES = {
  __Schema = {
    kind = "OBJECT",
    name = "__Schema",
    description = "A GraphQL Schema defines the capabilities of a GraphQL server.",
    interfaces = {},
    fields = {
      { name = "description", type = "String", description = nil, args = {} },
      {
        name = "types",
        type = "[__Type!]!",
        description = "A list of all types supported by this server.",
        args = {},
      },
      {
        name = "queryType",
        type = "__Type!",
        description = "The type that query operations will be rooted at.",
        args = {},
      },
      {
        name = "mutationType",
        type = "__Type",
        description = "If this server supports mutation, the type that mutation operations will be rooted at.",
        args = {},
      },
      {
        name = "subscriptionType",
        type = "__Type",
        description = "If this server support subscription, the type that subscription operations will be rooted at.",
        args = {},
      },
      {
        name = "directives",
        type = "[__Directive!]!",
        description = "A list of all directives supported by this server.",
        args = {},
      },
    },
  },
  __Type = {
    kind = "OBJECT",
    name = "__Type",
    description = "The fundamental unit of any GraphQL Schema is the type.",
    interfaces = {},
    fields = {
      { name = "kind", type = "__TypeKind!", description = nil, args = {} },
      { name = "name", type = "String", description = nil, args = {} },
      { name = "description", type = "String", description = nil, args = {} },
      {
        name = "fields",
        type = "[__Field!]",
        description = nil,
        args = {
          {
            name = "includeDeprecated",
            type = "Boolean",
            description = nil,
            default_value = "false",
          },
        },
      },
      { name = "interfaces", type = "[__Type!]", description = nil, args = {} },
      { name = "possibleTypes", type = "[__Type!]", description = nil, args = {} },
      {
        name = "enumValues",
        type = "[__EnumValue!]",
        description = nil,
        args = {
          {
            name = "includeDeprecated",
            type = "Boolean",
            description = nil,
            default_value = "false",
          },
        },
      },
      {
        name = "inputFields",
        type = "[__InputValue!]",
        description = nil,
        args = {
          {
            name = "includeDeprecated",
            type = "Boolean",
            description = nil,
            default_value = "false",
          },
        },
      },
      { name = "ofType", type = "__Type", description = nil, args = {} },
      { name = "specifiedByURL", type = "String", description = nil, args = {} },
    },
  },
  __Field = {
    kind = "OBJECT",
    name = "__Field",
    description = "Object and Interface types are described by a list of Fields.",
    interfaces = {},
    fields = {
      { name = "name", type = "String!", description = nil, args = {} },
      { name = "description", type = "String", description = nil, args = {} },
      {
        name = "args",
        type = "[__InputValue!]!",
        description = nil,
        args = {
          {
            name = "includeDeprecated",
            type = "Boolean",
            description = nil,
            default_value = "false",
          },
        },
      },
      { name = "type", type = "__Type!", description = nil, args = {} },
      { name = "isDeprecated", type = "Boolean!", description = nil, args = {} },
      { name = "deprecationReason", type = "String", description = nil, args = {} },
    },
  },
  __InputValue = {
    kind = "OBJECT",
    name = "__InputValue",
    description = "Arguments provided to Fields or Directives and the input fields of an InputObject.",
    interfaces = {},
    fields = {
      { name = "name", type = "String!", description = nil, args = {} },
      { name = "description", type = "String", description = nil, args = {} },
      { name = "type", type = "__Type!", description = nil, args = {} },
      {
        name = "defaultValue",
        type = "String",
        description = "A GraphQL-formatted string representing the default value for this input value.",
        args = {},
      },
      { name = "isDeprecated", type = "Boolean!", description = nil, args = {} },
      { name = "deprecationReason", type = "String", description = nil, args = {} },
    },
  },
  __EnumValue = {
    kind = "OBJECT",
    name = "__EnumValue",
    description = "One possible value for a given Enum.",
    interfaces = {},
    fields = {
      { name = "name", type = "String!", description = nil, args = {} },
      { name = "description", type = "String", description = nil, args = {} },
      { name = "isDeprecated", type = "Boolean!", description = nil, args = {} },
      { name = "deprecationReason", type = "String", description = nil, args = {} },
    },
  },
  __Directive = {
    kind = "OBJECT",
    name = "__Directive",
    description = "A Directive provides a way to describe alternate runtime execution and type validation behavior.",
    interfaces = {},
    fields = {
      { name = "name", type = "String!", description = nil, args = {} },
      { name = "description", type = "String", description = nil, args = {} },
      { name = "isRepeatable", type = "Boolean!", description = nil, args = {} },
      { name = "locations", type = "[__DirectiveLocation!]!", description = nil, args = {} },
      {
        name = "args",
        type = "[__InputValue!]!",
        description = nil,
        args = {
          {
            name = "includeDeprecated",
            type = "Boolean",
            description = nil,
            default_value = "false",
          },
        },
      },
    },
  },
  __TypeKind = {
    kind = "ENUM",
    name = "__TypeKind",
    description = "An enum describing what kind of type a given `__Type` is.",
    values = {
      { name = "SCALAR", description = "Indicates this type is a scalar.", is_deprecated = false },
      { name = "OBJECT", description = "Indicates this type is an object.", is_deprecated = false },
      {
        name = "INTERFACE",
        description = "Indicates this type is an interface.",
        is_deprecated = false,
      },
      { name = "UNION", description = "Indicates this type is a union.", is_deprecated = false },
      { name = "ENUM", description = "Indicates this type is an enum.", is_deprecated = false },
      {
        name = "INPUT_OBJECT",
        description = "Indicates this type is an input object.",
        is_deprecated = false,
      },
      { name = "LIST", description = "Indicates this type is a list.", is_deprecated = false },
      {
        name = "NON_NULL",
        description = "Indicates this type is a non-null.",
        is_deprecated = false,
      },
    },
  },
  __DirectiveLocation = {
    kind = "ENUM",
    name = "__DirectiveLocation",
    description = "A Directive can be adjacent to many parts of the GraphQL language.",
    values = {
      {
        name = "QUERY",
        description = "Location adjacent to a query operation.",
        is_deprecated = false,
      },
      {
        name = "MUTATION",
        description = "Location adjacent to a mutation operation.",
        is_deprecated = false,
      },
      {
        name = "SUBSCRIPTION",
        description = "Location adjacent to a subscription operation.",
        is_deprecated = false,
      },
      { name = "FIELD", description = "Location adjacent to a field.", is_deprecated = false },
      {
        name = "FRAGMENT_DEFINITION",
        description = "Location adjacent to a fragment definition.",
        is_deprecated = false,
      },
      {
        name = "FRAGMENT_SPREAD",
        description = "Location adjacent to a fragment spread.",
        is_deprecated = false,
      },
      {
        name = "INLINE_FRAGMENT",
        description = "Location adjacent to an inline fragment.",
        is_deprecated = false,
      },
      {
        name = "VARIABLE_DEFINITION",
        description = "Location adjacent to a variable definition.",
        is_deprecated = false,
      },
      {
        name = "SCHEMA",
        description = "Location adjacent to a schema definition.",
        is_deprecated = false,
      },
      {
        name = "SCALAR",
        description = "Location adjacent to a scalar definition.",
        is_deprecated = false,
      },
      {
        name = "OBJECT",
        description = "Location adjacent to an object type definition.",
        is_deprecated = false,
      },
      {
        name = "FIELD_DEFINITION",
        description = "Location adjacent to a field definition.",
        is_deprecated = false,
      },
      {
        name = "ARGUMENT_DEFINITION",
        description = "Location adjacent to an argument definition.",
        is_deprecated = false,
      },
      {
        name = "INTERFACE",
        description = "Location adjacent to an interface definition.",
        is_deprecated = false,
      },
      {
        name = "UNION",
        description = "Location adjacent to a union definition.",
        is_deprecated = false,
      },
      {
        name = "ENUM",
        description = "Location adjacent to an enum definition.",
        is_deprecated = false,
      },
      {
        name = "ENUM_VALUE",
        description = "Location adjacent to an enum value definition.",
        is_deprecated = false,
      },
      {
        name = "INPUT_OBJECT",
        description = "Location adjacent to an input object type definition.",
        is_deprecated = false,
      },
      {
        name = "INPUT_FIELD_DEFINITION",
        description = "Location adjacent to an input object field definition.",
        is_deprecated = false,
      },
    },
  },
}

local BUILTIN_DIRECTIVES = {
  skip = {
    name = "skip",
    description = "Directs the executor to skip this field or fragment when the `if` argument is true.",
    args = {
      { name = "if", type = "Boolean!", description = "Skipped when true.", default_value = nil },
    },
    locations = { "FIELD", "FRAGMENT_SPREAD", "INLINE_FRAGMENT" },
    is_repeatable = false,
  },
  include = {
    name = "include",
    description = "Directs the executor to include this field or fragment only when the `if` argument is true.",
    args = {
      { name = "if", type = "Boolean!", description = "Included when true.", default_value = nil },
    },
    locations = { "FIELD", "FRAGMENT_SPREAD", "INLINE_FRAGMENT" },
    is_repeatable = false,
  },
  deprecated = {
    name = "deprecated",
    description = "Marks an element of a GraphQL schema as no longer supported.",
    args = {
      {
        name = "reason",
        type = "String",
        description = "Explains why this element was deprecated.",
        default_value = '"No longer supported"',
      },
    },
    locations = { "FIELD_DEFINITION", "ARGUMENT_DEFINITION", "INPUT_FIELD_DEFINITION", "ENUM_VALUE" },
    is_repeatable = false,
  },
  specifiedBy = {
    name = "specifiedBy",
    description = "Exposes a URL that specifies the behavior of this scalar.",
    args = {
      { name = "url", type = "String!", description = "The URL that specifies the behavior of this scalar.", default_value = nil },
    },
    locations = { "SCALAR" },
    is_repeatable = false,
  },
}

-- ---------------------------------------------------------------------------
-- Lua emitter
-- ---------------------------------------------------------------------------

local function lua_escape(s)
  if s == nil then
    return "nil"
  end
  return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
end

local function lua_bool(b)
  return b and "true" or "false"
end

local function lua_string_list(items)
  if #items == 0 then
    return "{}"
  end
  local parts = {}
  for i, s in ipairs(items) do
    parts[i] = lua_escape(s)
  end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

local emit_field, emit_input_value

emit_input_value = function(iv, out, indent)
  local pad = string.rep(" ", indent)
  local dv
  if iv.default_value == nil then
    dv = "nil"
  else
    dv = lua_escape(iv.default_value)
  end
  out[#out + 1] = pad
    .. "{ name = "
    .. lua_escape(iv.name)
    .. ", type = "
    .. lua_escape(iv.type)
    .. ", description = "
    .. lua_escape(iv.description)
    .. ", default_value = "
    .. dv
    .. " },\n"
end

emit_field = function(field, out, indent)
  local pad = string.rep(" ", indent)
  local args = field.args or {}
  if #args > 0 then
    out[#out + 1] = pad
      .. "{ name = "
      .. lua_escape(field.name)
      .. ", type = "
      .. lua_escape(field.type)
      .. ", description = "
      .. lua_escape(field.description)
      .. ", args = {\n"
    for _, a in ipairs(args) do
      emit_input_value(a, out, indent + 2)
    end
    out[#out + 1] = pad .. "} },\n"
  else
    out[#out + 1] = pad
      .. "{ name = "
      .. lua_escape(field.name)
      .. ", type = "
      .. lua_escape(field.type)
      .. ", description = "
      .. lua_escape(field.description)
      .. ", args = {} },\n"
  end
end

local function emit_type(td, out)
  local kind = td.kind
  out[#out + 1] = "    [" .. lua_escape(td.name) .. "] = {\n"
  out[#out + 1] = "      kind        = " .. lua_escape(kind) .. ",\n"
  out[#out + 1] = "      name        = " .. lua_escape(td.name) .. ",\n"
  out[#out + 1] = "      description = " .. lua_escape(td.description) .. ",\n"

  if kind == "OBJECT" or kind == "INTERFACE" then
    out[#out + 1] = "      interfaces  = " .. lua_string_list(td.interfaces or {}) .. ",\n"
    if kind == "INTERFACE" then
      out[#out + 1] = "      possible_types = " .. lua_string_list(td.possible_types or {}) .. ",\n"
    end
    out[#out + 1] = "      fields      = {\n"
    for _, field in ipairs(td.fields or {}) do
      emit_field(field, out, 8)
    end
    out[#out + 1] = "      },\n"
  elseif kind == "UNION" then
    out[#out + 1] = "      possible_types = " .. lua_string_list(td.possible_types or {}) .. ",\n"
  elseif kind == "ENUM" then
    out[#out + 1] = "      values      = {\n"
    for _, val in ipairs(td.values or {}) do
      out[#out + 1] = "        { name = "
        .. lua_escape(val.name)
        .. ", description = "
        .. lua_escape(val.description)
        .. ", is_deprecated = "
        .. lua_bool(val.is_deprecated)
        .. " },\n"
    end
    out[#out + 1] = "      },\n"
  elseif kind == "INPUT_OBJECT" then
    out[#out + 1] = "      input_fields = {\n"
    for _, f in ipairs(td.input_fields or {}) do
      emit_input_value(f, out, 8)
    end
    out[#out + 1] = "      },\n"
  end

  out[#out + 1] = "    },\n"
end

local function emit_directive(dir, out)
  out[#out + 1] = "    {\n"
  out[#out + 1] = "      name          = " .. lua_escape(dir.name) .. ",\n"
  out[#out + 1] = "      description   = " .. lua_escape(dir.description) .. ",\n"
  out[#out + 1] = "      is_repeatable = " .. lua_bool(dir.is_repeatable) .. ",\n"
  out[#out + 1] = "      locations     = " .. lua_string_list(dir.locations) .. ",\n"
  local args = dir.args or {}
  if #args > 0 then
    out[#out + 1] = "      args          = {\n"
    for _, a in ipairs(args) do
      emit_input_value(a, out, 8)
    end
    out[#out + 1] = "      },\n"
  else
    out[#out + 1] = "      args          = {},\n"
  end
  out[#out + 1] = "    },\n"
end

local function emit_lua(types, reachable, directives)
  -- Collect and sort type names
  local names = {}
  for name in pairs(reachable) do
    names[#names + 1] = name
  end
  table.sort(names)

  local out = {}
  out[#out + 1] = "-- AUTO-GENERATED by scripts/gen-graphql-schema.lua \226\128\148 do not edit.\n"
  out[#out + 1] = "-- Source: vendor/github-graphql-schema/schema.docs.graphql\n"
  out[#out + 1] = "\n"
  out[#out + 1] = "graphql_schema_data = {\n"
  out[#out + 1] = '  query_type        = "Query",\n'
  out[#out + 1] = '  mutation_type     = "Mutation",\n'
  out[#out + 1] = "  subscription_type = nil,\n"
  out[#out + 1] = "\n"
  out[#out + 1] = "  types = {\n"

  for _, name in ipairs(names) do
    emit_type(types[name], out)
  end

  out[#out + 1] = "  },\n"
  out[#out + 1] = "\n"

  -- Emit directives sorted by name
  local dir_names = {}
  for name in pairs(directives) do
    dir_names[#dir_names + 1] = name
  end
  table.sort(dir_names)

  out[#out + 1] = "  directives = {\n"
  for _, name in ipairs(dir_names) do
    emit_directive(directives[name], out)
  end
  out[#out + 1] = "  },\n"

  out[#out + 1] = "}\n"
  return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------------

local sdl_text = read_file(sdl_path)
local parser = make_parser(sdl_text)
local types, sdl_directives = parser.parse()

-- Add built-in scalars (SDL usually omits them)
for name, td in pairs(BUILTIN_SCALARS) do
  if not types[name] then
    types[name] = td
  end
end

-- Add introspection meta-types
for name, td in pairs(INTROSPECTION_TYPES) do
  types[name] = td
end

-- Compute reachability from Query and Mutation roots
local reachable = compute_reachable(types, { "Query", "Mutation" })

-- Always include introspection types and built-in scalars
for name in pairs(INTROSPECTION_TYPES) do
  reachable[name] = true
end
for name in pairs(BUILTIN_SCALARS) do
  reachable[name] = true
end

-- Populate possible_types for interfaces
populate_possible_types(types, reachable)

-- Verify all reachable types exist
local missing = {}
for name in pairs(reachable) do
  if not types[name] then
    missing[#missing + 1] = name
  end
end
if #missing > 0 then
  table.sort(missing)
  local shown = {}
  for i = 1, math.min(10, #missing) do
    shown[i] = missing[i]
  end
  io.stderr:write(
    string.format(
      "Warning: %d reachable types not found in SDL: %s...\n",
      #missing,
      table.concat(shown, ", ")
    )
  )
  for _, name in ipairs(missing) do
    reachable[name] = nil
  end
end

-- Count reachable types
local count = 0
for _ in pairs(reachable) do
  count = count + 1
end

-- Merge directives: built-in spec directives as fallback, SDL directives take precedence
local all_directives = {}
for name, dd in pairs(BUILTIN_DIRECTIVES) do
  all_directives[name] = dd
end
for name, dd in pairs(sdl_directives) do
  all_directives[name] = dd
end

-- Emit
local output = emit_lua(types, reachable, all_directives)
local f = assert(io.open(out_path, "w"))
f:write(output)
f:close()

io.stderr:write(string.format("Wrote %d types to %s\n", count, out_path))
