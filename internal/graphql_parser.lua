-- internal/graphql_parser.lua
-- GraphQL document parser (GraphQL October 2021 specification).
--
-- Exports: graphql_parse(source), graphql_tokenize(source)

-- ============================================================
-- Block string value processing (GraphQL spec §2.1.9)
-- ============================================================

-- Split raw on line terminators; return an array of lines.
local function split_lines(raw)
  local lines = {}
  local i = 1
  local s = 1
  while i <= #raw do
    local b = raw:byte(i)
    if b == 13 then -- \r or \r\n
      lines[#lines + 1] = raw:sub(s, i - 1)
      if raw:byte(i + 1) == 10 then
        i = i + 1
      end
      i = i + 1
      s = i
    elseif b == 10 then -- \n
      lines[#lines + 1] = raw:sub(s, i - 1)
      i = i + 1
      s = i
    else
      i = i + 1
    end
  end
  lines[#lines + 1] = raw:sub(s)
  return lines
end

local function block_string_value(raw)
  local lines = split_lines(raw)

  -- Common indent = min leading-space count of non-empty lines after line 1.
  local common = math.maxinteger
  for j = 2, #lines do
    local ln = lines[j]
    if ln:match("%S") then
      local indent = 0
      for k = 1, #ln do
        local b = ln:byte(k)
        if b == 32 or b == 9 then
          indent = indent + 1
        else
          break
        end
      end
      if indent < common then
        common = indent
      end
    end
  end
  if common == math.maxinteger then
    common = 0
  end

  -- Remove common indent from every line after the first.
  for j = 2, #lines do
    lines[j] = lines[j]:sub(common + 1)
  end

  -- Strip leading whitespace-only lines.
  while #lines > 0 and not lines[1]:match("%S") do
    table.remove(lines, 1)
  end

  -- Strip trailing whitespace-only lines.
  while #lines > 0 and not lines[#lines]:match("%S") do
    table.remove(lines)
  end

  return table.concat(lines, "\n")
end

-- ============================================================
-- Lexer
-- ============================================================

local function make_lexer(source)
  local lex = { src = source, pos = 1, line = 1, col = 1, _peeked = nil }

  function lex:error(msg)
    error(self.line .. ":" .. self.col .. ": " .. msg, 0)
  end

  -- Read and return the next meaningful token, advancing position.
  local function read_token(l)
    local src = l.src

    -- Skip ignored tokens: whitespace, line terminators, commas, comments.
    while l.pos <= #src do
      local b = src:byte(l.pos)
      if b == 9 or b == 32 or b == 44 then -- tab, space, comma
        l.col = l.col + 1
        l.pos = l.pos + 1
      elseif b == 10 then -- \n
        l.line = l.line + 1
        l.col = 1
        l.pos = l.pos + 1
      elseif b == 13 then -- \r or \r\n
        l.line = l.line + 1
        l.col = 1
        l.pos = l.pos + 1
        if src:byte(l.pos) == 10 then
          l.pos = l.pos + 1
        end
      elseif b == 35 then -- # comment: skip to end of line
        l.pos = l.pos + 1
        l.col = l.col + 1
        while l.pos <= #src do
          local cb = src:byte(l.pos)
          if cb == 10 or cb == 13 then
            break
          end
          l.pos = l.pos + 1
          l.col = l.col + 1
        end
      else
        break
      end
    end

    local tline = l.line
    local tcol = l.col

    if l.pos > #src then
      return { kind = "EOF", value = "", line = tline, col = tcol }
    end

    local b = src:byte(l.pos)

    -- Single-character punctuation.
    if
      b == 33
      or b == 36
      or b == 38
      or b == 40
      or b == 41
      or b == 58
      or b == 61
      or b == 64
      or b == 91
      or b == 93
      or b == 123
      or b == 124
      or b == 125
    then
      local ch = src:sub(l.pos, l.pos)
      l.pos = l.pos + 1
      l.col = l.col + 1
      return { kind = "PUNCT", value = ch, line = tline, col = tcol }
    end

    -- ... (three dots; one or two dots alone is a lexer error).
    if b == 46 then
      if src:sub(l.pos, l.pos + 2) == "..." then
        l.pos = l.pos + 3
        l.col = l.col + 3
        return { kind = "PUNCT", value = "...", line = tline, col = tcol }
      end
      l:error("unexpected character '.'")
    end

    -- NAME: [_A-Za-z][_0-9A-Za-z]*
    if b == 95 or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) then
      local s = l.pos
      l.pos = l.pos + 1
      while true do
        local nb = src:byte(l.pos)
        if
          nb
          and (
            nb == 95
            or (nb >= 65 and nb <= 90)
            or (nb >= 97 and nb <= 122)
            or (nb >= 48 and nb <= 57)
          )
        then
          l.pos = l.pos + 1
        else
          break
        end
      end
      local value = src:sub(s, l.pos - 1)
      l.col = tcol + #value
      return { kind = "NAME", value = value, line = tline, col = tcol }
    end

    -- Number: IntValue or FloatValue.
    if b == 45 or (b >= 48 and b <= 57) then -- - or digit
      local s = l.pos
      if b == 45 then -- optional leading minus
        l.pos = l.pos + 1
        local nb = src:byte(l.pos)
        if not nb or not (nb >= 48 and nb <= 57) then
          l:error("invalid number: expected digit after '-'")
        end
      end
      while true do -- integer part
        local nb = src:byte(l.pos)
        if nb and nb >= 48 and nb <= 57 then
          l.pos = l.pos + 1
        else
          break
        end
      end
      local is_float = false
      local nb = src:byte(l.pos)
      if nb == 46 then -- fractional part
        is_float = true
        l.pos = l.pos + 1
        local fb = src:byte(l.pos)
        if not fb or not (fb >= 48 and fb <= 57) then
          l:error("invalid float: expected digit after '.'")
        end
        while true do
          local db = src:byte(l.pos)
          if db and db >= 48 and db <= 57 then
            l.pos = l.pos + 1
          else
            break
          end
        end
        nb = src:byte(l.pos)
      end
      if nb == 69 or nb == 101 then -- exponent part (E or e)
        is_float = true
        l.pos = l.pos + 1
        local sb2 = src:byte(l.pos)
        if sb2 == 43 or sb2 == 45 then -- optional +/-
          l.pos = l.pos + 1
        end
        local eb = src:byte(l.pos)
        if not eb or not (eb >= 48 and eb <= 57) then
          l:error("invalid float: expected digit in exponent")
        end
        while true do
          local db = src:byte(l.pos)
          if db and db >= 48 and db <= 57 then
            l.pos = l.pos + 1
          else
            break
          end
        end
        nb = src:byte(l.pos)
      end
      -- Number must not be immediately followed by a name-start char.
      if
        nb
        and (
          nb == 95
          or (nb >= 65 and nb <= 90)
          or (nb >= 97 and nb <= 122)
          or (nb >= 48 and nb <= 57)
        )
      then
        l:error("invalid number literal: unexpected character after digits")
      end
      local value = src:sub(s, l.pos - 1)
      l.col = tcol + #value
      return {
        kind = is_float and "FLOAT_VALUE" or "INT_VALUE",
        value = value,
        line = tline,
        col = tcol,
      }
    end

    -- String (single-line) or block string (triple-quoted).
    if b == 34 then -- "
      if src:sub(l.pos, l.pos + 2) == '"""' then
        -- Block string.
        l.pos = l.pos + 3
        l.col = l.col + 3
        local parts = {}
        while true do
          if l.pos > #src then
            l:error("unterminated block string")
          end
          if src:sub(l.pos, l.pos + 2) == '"""' then
            l.pos = l.pos + 3
            l.col = l.col + 3
            break
          end
          if src:sub(l.pos, l.pos + 3) == '\\"""' then -- escaped triple-quote
            parts[#parts + 1] = '"""'
            l.pos = l.pos + 4
            l.col = l.col + 4
          else
            local ch = src:sub(l.pos, l.pos)
            parts[#parts + 1] = ch
            if ch == "\n" then
              l.line = l.line + 1
              l.col = 1
              l.pos = l.pos + 1
            elseif ch == "\r" then
              l.line = l.line + 1
              l.col = 1
              l.pos = l.pos + 1
              if src:sub(l.pos, l.pos) == "\n" then
                parts[#parts + 1] = "\n"
                l.pos = l.pos + 1
              end
            else
              l.col = l.col + 1
              l.pos = l.pos + 1
            end
          end
        end
        return {
          kind = "STRING_VALUE",
          value = block_string_value(table.concat(parts)),
          line = tline,
          col = tcol,
        }
      else
        -- Single-line string.
        l.pos = l.pos + 1
        l.col = l.col + 1
        local parts = {}
        while true do
          if l.pos > #src then
            l:error("unterminated string")
          end
          local cb = src:byte(l.pos)
          if cb == 10 or cb == 13 then
            l:error("line terminator inside string")
          elseif cb == 34 then -- closing "
            l.pos = l.pos + 1
            l.col = l.col + 1
            break
          elseif cb == 92 then -- backslash escape
            l.pos = l.pos + 1
            local eb = src:byte(l.pos)
            if eb == 34 then
              parts[#parts + 1] = '"'
              l.pos = l.pos + 1
              l.col = l.col + 2
            elseif eb == 92 then
              parts[#parts + 1] = "\\"
              l.pos = l.pos + 1
              l.col = l.col + 2
            elseif eb == 47 then
              parts[#parts + 1] = "/"
              l.pos = l.pos + 1
              l.col = l.col + 2
            elseif eb == 98 then
              parts[#parts + 1] = "\b"
              l.pos = l.pos + 1
              l.col = l.col + 2
            elseif eb == 102 then
              parts[#parts + 1] = "\f"
              l.pos = l.pos + 1
              l.col = l.col + 2
            elseif eb == 110 then
              parts[#parts + 1] = "\n"
              l.pos = l.pos + 1
              l.col = l.col + 2
            elseif eb == 114 then
              parts[#parts + 1] = "\r"
              l.pos = l.pos + 1
              l.col = l.col + 2
            elseif eb == 116 then
              parts[#parts + 1] = "\t"
              l.pos = l.pos + 1
              l.col = l.col + 2
            elseif eb == 117 then -- \uXXXX
              l.pos = l.pos + 1
              local hex = src:sub(l.pos, l.pos + 3)
              if #hex < 4 or not hex:match("^[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$") then
                l:error("invalid unicode escape \\u" .. hex)
              end
              parts[#parts + 1] = utf8.char(tonumber(hex, 16))
              l.pos = l.pos + 4
              l.col = l.col + 6 -- \uXXXX = 6 source chars
            else
              l:error("invalid escape sequence '\\" .. string.char(eb) .. "'")
            end
          else
            parts[#parts + 1] = src:sub(l.pos, l.pos)
            l.pos = l.pos + 1
            l.col = l.col + 1
          end
        end
        return { kind = "STRING_VALUE", value = table.concat(parts), line = tline, col = tcol }
      end
    end

    l:error("unexpected character '" .. src:sub(l.pos, l.pos) .. "'")
  end

  function lex:next()
    if self._peeked then
      local tok = self._peeked
      self._peeked = nil
      return tok
    end
    return read_token(self)
  end

  function lex:peek()
    if not self._peeked then
      self._peeked = read_token(self)
    end
    return self._peeked
  end

  return lex
end

-- ============================================================
-- Parser helpers
-- ============================================================

local function expect(lex, kind, value)
  local tok = lex:next()
  if tok.kind ~= kind or (value ~= nil and tok.value ~= value) then
    lex:error("expected " .. (value or kind) .. ", got '" .. tostring(tok.value) .. "'")
  end
  return tok
end

local function peek_is(lex, kind, value)
  local tok = lex:peek()
  if tok.kind ~= kind then
    return false
  end
  if value ~= nil and tok.value ~= value then
    return false
  end
  return true
end

-- ============================================================
-- Parser (recursive descent, one function per grammar production)
-- ============================================================

local parse_value -- forward declaration (used by parse_arguments before its definition)

local function parse_name(lex)
  local tok = expect(lex, "NAME")
  return { kind = "Name", value = tok.value }
end

local function parse_arguments(lex)
  local args = {}
  expect(lex, "PUNCT", "(")
  while not peek_is(lex, "PUNCT", ")") do
    local name = parse_name(lex)
    expect(lex, "PUNCT", ":")
    local value = parse_value(lex)
    args[#args + 1] = { kind = "Argument", name = name, value = value }
  end
  expect(lex, "PUNCT", ")")
  return args
end

local function parse_directives(lex)
  local dirs = {}
  while peek_is(lex, "PUNCT", "@") do
    lex:next() -- consume @
    local name = parse_name(lex)
    local arguments = {}
    if peek_is(lex, "PUNCT", "(") then
      arguments = parse_arguments(lex)
    end
    dirs[#dirs + 1] = { kind = "Directive", name = name, arguments = arguments }
  end
  return dirs
end

local function parse_type(lex)
  local t
  if peek_is(lex, "PUNCT", "[") then
    lex:next() -- consume [
    local inner = parse_type(lex)
    expect(lex, "PUNCT", "]")
    t = { kind = "ListType", type = inner }
  else
    local name = parse_name(lex)
    t = { kind = "NamedType", name = name }
  end
  if peek_is(lex, "PUNCT", "!") then
    lex:next() -- consume !
    return { kind = "NonNullType", type = t }
  end
  return t
end

-- parse_value: all value forms (Variable, scalars, Enum, List, Object).
-- Forward-declared above; defined here so parse_arguments can reference it.
parse_value = function(lex)
  local tok = lex:peek()

  if tok.kind == "PUNCT" and tok.value == "$" then
    lex:next()
    local name = parse_name(lex)
    return { kind = "Variable", name = name }
  end

  if tok.kind == "INT_VALUE" then
    lex:next()
    return { kind = "IntValue", value = tok.value }
  end

  if tok.kind == "FLOAT_VALUE" then
    lex:next()
    return { kind = "FloatValue", value = tok.value }
  end

  if tok.kind == "STRING_VALUE" then
    lex:next()
    return { kind = "StringValue", value = tok.value }
  end

  if tok.kind == "NAME" then
    if tok.value == "true" then
      lex:next()
      return { kind = "BooleanValue", value = true }
    elseif tok.value == "false" then
      lex:next()
      return { kind = "BooleanValue", value = false }
    elseif tok.value == "null" then
      lex:next()
      return { kind = "NullValue" }
    else
      lex:next()
      return { kind = "EnumValue", value = tok.value }
    end
  end

  if tok.kind == "PUNCT" and tok.value == "[" then
    lex:next()
    local values = {}
    while not peek_is(lex, "PUNCT", "]") do
      values[#values + 1] = parse_value(lex)
    end
    lex:next() -- consume ]
    return { kind = "ListValue", values = values }
  end

  if tok.kind == "PUNCT" and tok.value == "{" then
    lex:next()
    local fields = {}
    while not peek_is(lex, "PUNCT", "}") do
      local name = parse_name(lex)
      expect(lex, "PUNCT", ":")
      local value = parse_value(lex)
      fields[#fields + 1] = { kind = "ObjectField", name = name, value = value }
    end
    lex:next() -- consume }
    return { kind = "ObjectValue", fields = fields }
  end

  lex:error("expected a value, got '" .. tostring(tok.value) .. "'")
end

local function parse_selection_set(lex)
  expect(lex, "PUNCT", "{")
  local selections = {}
  while not peek_is(lex, "PUNCT", "}") do
    local tok = lex:peek()
    if tok.kind == "PUNCT" and tok.value == "..." then
      lex:next() -- consume ...
      local after = lex:peek()
      if after.kind == "NAME" and after.value ~= "on" then
        -- FragmentSpread: ... FragmentName Directives?
        local name = parse_name(lex)
        local directives = parse_directives(lex)
        selections[#selections + 1] =
          { kind = "FragmentSpread", name = name, directives = directives }
      else
        -- InlineFragment: ... TypeCondition? Directives? SelectionSet
        local type_condition = nil
        if peek_is(lex, "NAME", "on") then
          lex:next() -- consume "on"
          local type_name = parse_name(lex)
          type_condition = { kind = "NamedType", name = type_name }
        end
        local directives = parse_directives(lex)
        local selection_set = parse_selection_set(lex)
        selections[#selections + 1] = {
          kind = "InlineFragment",
          type_condition = type_condition,
          directives = directives,
          selection_set = selection_set,
        }
      end
    else
      -- Field: Alias? Name Arguments? Directives? SelectionSet?
      local name_tok = expect(lex, "NAME")
      local alias = nil
      local field_name
      if peek_is(lex, "PUNCT", ":") then
        lex:next() -- consume :
        alias = { kind = "Name", value = name_tok.value }
        field_name = parse_name(lex)
      else
        field_name = { kind = "Name", value = name_tok.value }
      end
      local arguments = {}
      if peek_is(lex, "PUNCT", "(") then
        arguments = parse_arguments(lex)
      end
      local directives = parse_directives(lex)
      local selection_set = nil
      if peek_is(lex, "PUNCT", "{") then
        selection_set = parse_selection_set(lex)
      end
      selections[#selections + 1] = {
        kind = "Field",
        alias = alias,
        name = field_name,
        arguments = arguments,
        directives = directives,
        selection_set = selection_set,
      }
    end
  end
  if #selections == 0 then
    lex:error("selection set must not be empty")
  end
  expect(lex, "PUNCT", "}")
  return { kind = "SelectionSet", selections = selections }
end

local function parse_variable_definitions(lex)
  local defs = {}
  expect(lex, "PUNCT", "(")
  while not peek_is(lex, "PUNCT", ")") do
    expect(lex, "PUNCT", "$")
    local name = parse_name(lex)
    expect(lex, "PUNCT", ":")
    local typ = parse_type(lex)
    local default_value = nil
    if peek_is(lex, "PUNCT", "=") then
      lex:next() -- consume =
      default_value = parse_value(lex)
    end
    local directives = parse_directives(lex)
    defs[#defs + 1] = {
      kind = "VariableDefinition",
      variable = { kind = "Variable", name = name },
      type = typ,
      default_value = default_value,
      directives = directives,
    }
  end
  expect(lex, "PUNCT", ")")
  return defs
end

local function parse_definition(lex)
  local tok = lex:peek()

  -- fragment FragmentName on TypeCondition Directives? SelectionSet
  if tok.kind == "NAME" and tok.value == "fragment" then
    lex:next() -- consume "fragment"
    local name_tok = lex:peek()
    if name_tok.kind ~= "NAME" or name_tok.value == "on" then
      lex:error("expected fragment name (not 'on'), got '" .. tostring(name_tok.value) .. "'")
    end
    local name = parse_name(lex)
    expect(lex, "NAME", "on")
    local type_name = parse_name(lex)
    local directives = parse_directives(lex)
    local selection_set = parse_selection_set(lex)
    return {
      kind = "FragmentDefinition",
      name = name,
      type_condition = { kind = "NamedType", name = type_name },
      directives = directives,
      selection_set = selection_set,
    }
  end

  -- OperationDefinition: OperationType Name? VariableDefinitions? Directives? SelectionSet
  --                    | SelectionSet  (shorthand anonymous query)
  local operation = "query"
  local op_name = nil

  if
    tok.kind == "NAME"
    and (tok.value == "query" or tok.value == "mutation" or tok.value == "subscription")
  then
    operation = tok.value
    lex:next() -- consume operation type keyword
    if peek_is(lex, "NAME") then
      op_name = parse_name(lex)
    end
  elseif not (tok.kind == "PUNCT" and tok.value == "{") then
    -- shorthand query starts with "{"; anything else is an error
    lex:error(
      "expected 'query', 'mutation', 'subscription', 'fragment', or '{', got '"
        .. tostring(tok.value)
        .. "'"
    )
  end

  local variable_definitions = {}
  if peek_is(lex, "PUNCT", "(") then
    variable_definitions = parse_variable_definitions(lex)
  end

  local directives = parse_directives(lex)
  local selection_set = parse_selection_set(lex)

  return {
    kind = "OperationDefinition",
    operation = operation,
    name = op_name,
    variable_definitions = variable_definitions,
    directives = directives,
    selection_set = selection_set,
  }
end

local function parse_document(lex)
  if peek_is(lex, "EOF") then
    lex:error("document must contain at least one definition")
  end
  local defs = {}
  repeat
    defs[#defs + 1] = parse_definition(lex)
  until peek_is(lex, "EOF")
  return { kind = "Document", definitions = defs }
end

-- ============================================================
-- Exported globals
-- ============================================================

-- Parse a GraphQL document string.
-- Returns: doc (DocumentNode), nil        on success
-- Returns: nil, "line:col: message"       on syntax error
function graphql_parse(source) -- luacheck: globals graphql_parse
  local ok, result = pcall(parse_document, make_lexer(source))
  if ok then
    return result, nil
  else
    return nil, result
  end
end

-- Tokenise a GraphQL document string.
-- Returns a flat array of token tables { kind, value, line, col }.
-- Intended for unit tests only; lexer errors propagate as Lua errors.
function graphql_tokenize(source) -- luacheck: globals graphql_tokenize
  local lex = make_lexer(source)
  local tokens = {}
  while true do
    local tok = lex:next()
    tokens[#tokens + 1] = tok
    if tok.kind == "EOF" then
      break
    end
  end
  return tokens
end
