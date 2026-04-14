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
-- Character class predicates
-- ============================================================

local function is_digit(b)
  return b ~= nil and b >= 48 and b <= 57
end

local function is_name_start(b)
  return b ~= nil and (b == 95 or (b >= 65 and b <= 90) or (b >= 97 and b <= 122))
end

local function is_name_char(b)
  return is_name_start(b) or is_digit(b)
end

-- ============================================================
-- Lexer tables
-- ============================================================

-- Single-character escape sequences (GraphQL spec §2.1.9).
local simple_escapes = {
  [34] = '"',
  [47] = "/",
  [92] = "\\",
  [98] = "\b",
  [102] = "\f",
  [110] = "\n",
  [114] = "\r",
  [116] = "\t",
}

-- Single-character punctuation (GraphQL spec §2.1.8): ! $ & ( ) : = @ [ ] { | }
local punct_bytes = {
  [33] = true,
  [36] = true,
  [38] = true,
  [40] = true,
  [41] = true,
  [58] = true,
  [61] = true,
  [64] = true,
  [91] = true,
  [93] = true,
  [123] = true,
  [124] = true,
  [125] = true,
}

-- ============================================================
-- Lexer
-- ============================================================

local function make_lexer(source)
  local src = source
  local lex = { src = source, pos = 1, line = 1, col = 1, _peeked = nil }

  -- ---- Error reporting ----

  function lex:error(msg)
    error(self.line .. ":" .. self.col .. ": " .. msg, 0)
  end

  -- ---- Character inspection ----

  function lex:at_end()
    return self.pos > #src
  end

  function lex:byte()
    return src:byte(self.pos)
  end

  function lex:char()
    return src:sub(self.pos, self.pos)
  end

  function lex:match(s)
    return src:sub(self.pos, self.pos + #s - 1) == s
  end

  -- ---- Position advancement ----

  function lex:advance()
    self.pos = self.pos + 1
    self.col = self.col + 1
  end

  function lex:advance_by(n)
    self.pos = self.pos + n
    self.col = self.col + n
  end

  function lex:newline()
    self.line = self.line + 1
    self.col = 1
    self.pos = self.pos + 1
  end

  -- ---- Skip helpers ----

  -- Consume \n, \r, or \r\n.  Return true if a line terminator was consumed.
  function lex:skip_line_terminator()
    local b = self:byte()
    if b == 10 then
      self:newline()
      return true
    elseif b == 13 then
      self:newline()
      if self:byte() == 10 then
        self.pos = self.pos + 1
      end
      return true
    end
    return false
  end

  -- Skip from # through end of line.
  function lex:skip_comment()
    self:advance()
    while not self:at_end() do
      local b = self:byte()
      if b == 10 or b == 13 then
        break
      end
      self:advance()
    end
  end

  -- Skip whitespace, commas, line terminators, and comments.
  function lex:skip_ignored()
    while not self:at_end() do
      local b = self:byte()
      if b == 9 or b == 32 or b == 44 then
        self:advance()
      elseif b == 35 then
        self:skip_comment()
      elseif not self:skip_line_terminator() then
        break
      end
    end
  end

  -- ---- Token readers ----

  function lex:read_name(tline, tcol)
    local s = self.pos
    self.pos = self.pos + 1
    while is_name_char(self:byte()) do
      self.pos = self.pos + 1
    end
    local value = src:sub(s, self.pos - 1)
    self.col = tcol + #value
    return { kind = "NAME", value = value, line = tline, col = tcol }
  end

  function lex:read_digits()
    while is_digit(self:byte()) do
      self.pos = self.pos + 1
    end
  end

  function lex:read_number(tline, tcol)
    local s = self.pos
    if self:byte() == 45 then -- optional leading minus
      self.pos = self.pos + 1
      if not is_digit(self:byte()) then
        self:error("invalid number: expected digit after '-'")
      end
    end
    self:read_digits()
    local is_float = false
    if self:byte() == 46 then -- fractional part
      is_float = true
      self.pos = self.pos + 1
      if not is_digit(self:byte()) then
        self:error("invalid float: expected digit after '.'")
      end
      self:read_digits()
    end
    local eb = self:byte()
    if eb == 69 or eb == 101 then -- exponent part (E or e)
      is_float = true
      self.pos = self.pos + 1
      local sb = self:byte()
      if sb == 43 or sb == 45 then -- optional +/-
        self.pos = self.pos + 1
      end
      if not is_digit(self:byte()) then
        self:error("invalid float: expected digit in exponent")
      end
      self:read_digits()
    end
    -- Number must not be immediately followed by a name/digit character.
    if is_name_char(self:byte()) then
      self:error("invalid number literal: unexpected character after digits")
    end
    local value = src:sub(s, self.pos - 1)
    self.col = tcol + #value
    return {
      kind = is_float and "FLOAT_VALUE" or "INT_VALUE",
      value = value,
      line = tline,
      col = tcol,
    }
  end

  function lex:read_escape()
    self.pos = self.pos + 1 -- skip backslash
    local eb = self:byte()
    local ch = simple_escapes[eb]
    if ch then
      self.pos = self.pos + 1
      self.col = self.col + 2
      return ch
    end
    if eb == 117 then -- \uXXXX
      self.pos = self.pos + 1
      local hex = src:sub(self.pos, self.pos + 3)
      if #hex < 4 or not hex:match("^%x%x%x%x$") then
        self:error("invalid unicode escape \\u" .. hex)
      end
      local codepoint = tonumber(hex, 16)
      self.pos = self.pos + 4
      self.col = self.col + 6
      return utf8.char(codepoint)
    end
    self:error("invalid escape sequence '\\" .. string.char(eb) .. "'")
  end

  function lex:read_string(tline, tcol)
    self:advance() -- skip opening "
    local parts = {}
    while true do
      if self:at_end() then
        self:error("unterminated string")
      end
      local b = self:byte()
      if b == 10 or b == 13 then
        self:error("line terminator inside string")
      elseif b == 34 then -- closing "
        self:advance()
        break
      elseif b == 92 then -- backslash escape
        parts[#parts + 1] = self:read_escape()
      else
        parts[#parts + 1] = self:char()
        self:advance()
      end
    end
    return { kind = "STRING_VALUE", value = table.concat(parts), line = tline, col = tcol }
  end

  function lex:read_block_string(tline, tcol)
    self:advance_by(3) -- skip opening """
    local parts = {}
    while true do
      if self:at_end() then
        self:error("unterminated block string")
      end
      if self:match('"""') then
        self:advance_by(3)
        break
      end
      if self:match('\\"""') then -- escaped triple-quote
        parts[#parts + 1] = '"""'
        self:advance_by(4)
      else
        local ch = self:char()
        parts[#parts + 1] = ch
        if ch == "\n" then
          self:newline()
        elseif ch == "\r" then
          -- Cannot delegate to skip_line_terminator here because we must
          -- also append the \n to parts when consuming a \r\n pair.
          self:newline()
          if self:byte() == 10 then
            parts[#parts + 1] = "\n"
            self.pos = self.pos + 1
          end
        else
          self:advance()
        end
      end
    end
    return {
      kind = "STRING_VALUE",
      value = block_string_value(table.concat(parts)),
      line = tline,
      col = tcol,
    }
  end

  function lex:read_punct(tline, tcol)
    local ch = self:char()
    self:advance()
    return { kind = "PUNCT", value = ch, line = tline, col = tcol }
  end

  function lex:read_spread(tline, tcol)
    if not self:match("...") then
      self:error("unexpected character '.'")
    end
    self:advance_by(3)
    return { kind = "PUNCT", value = "...", line = tline, col = tcol }
  end

  -- ---- Main tokenizer ----

  function lex:read_token()
    self:skip_ignored()
    local tline = self.line
    local tcol = self.col
    if self:at_end() then
      return { kind = "EOF", value = "", line = tline, col = tcol }
    end
    local b = self:byte()
    if punct_bytes[b] then
      return self:read_punct(tline, tcol)
    end
    if b == 46 then
      return self:read_spread(tline, tcol)
    end
    if is_name_start(b) then
      return self:read_name(tline, tcol)
    end
    if b == 45 or is_digit(b) then
      return self:read_number(tline, tcol)
    end
    if b == 34 then
      if self:match('"""') then
        return self:read_block_string(tline, tcol)
      end
      return self:read_string(tline, tcol)
    end
    self:error("unexpected character '" .. self:char() .. "'")
  end

  -- ---- Public interface ----

  function lex:next()
    if self._peeked then
      local tok = self._peeked
      self._peeked = nil
      return tok
    end
    return self:read_token()
  end

  function lex:peek()
    if not self._peeked then
      self._peeked = self:read_token()
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
