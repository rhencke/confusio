# 02 — GraphQL Lexer and Parser for Lua on Redbean

## What this document covers

Confusio must parse the GraphQL query document supplied in every `POST /graphql` request
before it can validate, execute, or translate it.  No GraphQL parser library exists for
Lua 5.4, and Redbean ships no external dependencies.  This document specifies a hand-written
lexer and recursive-descent parser that lives in `internal/graphql_parser.lua`.

## Goals and constraints

- **No dependencies.** Must compile and run inside Redbean's embedded Lua 5.4 interpreter
  using only the standard library.
- **Complete.** Parses every construct in the GraphQL October 2021 specification that falls
  within the scope defined in [01-api-surface.md](01-api-surface.md): query and mutation
  operation documents, fragments, variables, directives, all value kinds.  SDL (schema
  definition language) parsing is out of scope — the schema is loaded separately.
- **Fail-fast with a useful error.** A malformed document returns an error string with a
  line:column location; confusio maps this to a GraphQL error envelope (see
  [09-errors.md](09-errors.md)).
- **No recovery.** The parser stops at the first syntax error.  Recovery heuristics add
  complexity without benefiting confusio's use-case (a proxy, not an IDE).
- **Reasonable performance.** Real-world GraphQL queries are small (under 50 KB).  A simple
  recursive-descent parser in Lua is fast enough; no performance optimisation is needed
  beyond avoiding gratuitous string copying.

## Module interface

```
internal/graphql_parser.lua
```

Exported globals (set on `_G` at load time, like all `internal/` modules):

```lua
-- Parse a GraphQL document string.
-- Returns: doc (table), nil         on success
-- Returns: nil, "line:col: message" on syntax error
-- doc is a DocumentNode (see AST section below).
graphql_parse(source)

-- Tokenise a GraphQL document string.
-- Returns a flat array of token tables { kind, value, line, col }.
-- Intended for unit tests only.  The parser does not use this function
-- directly — it lexes lazily inside the parse loop.
graphql_tokenize(source)
```

The module must not use global state between calls.  Both functions must be safe to call
concurrently in unit tests (even though Redbean is single-threaded at runtime).

## Lexer design

### Character classes

The GraphQL spec defines the following token classes, which the lexer must recognise in
this priority order:

| Token kind | Pattern |
|------------|---------|
| `IGNORED` | `WhiteSpace` (U+0009, U+0020), `LineTerminator` (U+000A, U+000D, U+000D U+000A), `Comment` (`#` to end of line), `Comma` (`,`) — silently skipped |
| `PUNCT` | `!`, `$`, `&`, `(`, `)`, `:`, `=`, `@`, `[`, `]`, `{`, `}`, `|`, `...` |
| `NAME` | `[_A-Za-z][_0-9A-Za-z]*` |
| `INT_VALUE` | `[-]?[0-9]+` (no decimal point or exponent) |
| `FLOAT_VALUE` | `[-]?[0-9]+` followed by fractional part and/or exponent part |
| `STRING_VALUE` | `"..."` (single-line) or `"""..."""` (block) |
| `EOF` | end of input |

Commas are insignificant in GraphQL; the lexer discards them alongside whitespace.

### Lexer state

The lexer is a Lua table (an object) created once per `graphql_parse` call:

```lua
local lex = {
  src   = source,   -- original string, never mutated
  pos   = 1,        -- 1-based byte position of next unread character
  line  = 1,        -- current line number (for error messages)
  col   = 1,        -- current column number (1-based)
}
```

It exposes two operations:
- `lex:peek()` — return the next token without consuming it
- `lex:next()` — return and consume the next token

A token is a table `{ kind, value, line, col }` where `value` is the raw matched text
(for `NAME`, `INT_VALUE`, `FLOAT_VALUE`) or the decoded string content (for
`STRING_VALUE`), or the punctuation character(s) for `PUNCT`.

### Advancing position

After consuming a character `c` at position `pos`:

```lua
if c == "\n" or (c == "\r" and src:sub(pos+1,pos+1) ~= "\n") then
  lex.line = lex.line + 1
  lex.col  = 1
elseif c == "\r" then
  -- \r\n: the \n will advance line on the next iteration
else
  lex.col = lex.col + 1
end
lex.pos = lex.pos + 1
```

### NAME tokens

```lua
local s = lex.pos
while true do
  local b = src:byte(lex.pos)
  if b and (b == 95                      -- _
         or (b >= 65 and b <= 90)        -- A-Z
         or (b >= 97 and b <= 122)       -- a-z
         or (b >= 48 and b <= 57 and lex.pos > s)) -- 0-9 (not first)
  then
    lex.pos = lex.pos + 1
  else
    break
  end
end
local value = src:sub(s, lex.pos - 1)
```

`NAME` tokens for GraphQL keywords (`query`, `mutation`, `subscription`, `fragment`,
`on`, `true`, `false`, `null`) are distinguished by the parser, not the lexer.  The lexer
emits all of them as `NAME` tokens.

### Number tokens

A leading `-` followed by digits.  If a `.` follows, read fractional digits; if `e`/`E`
follows (with optional `+`/`-`), read exponent digits.  Produce `INT_VALUE` or
`FLOAT_VALUE` based on whether fractional/exponent parts were present.

### String tokens

**Single-line string** (`"..."`)

Read bytes until a closing `"`.  Process escape sequences:
`\"`, `\\`, `\/`, `\b`, `\f`, `\n`, `\r`, `\t`, `\uXXXX`.  A line terminator inside
a single-line string is a lexer error.

**Block string** (`"""..."""`)

Read bytes until the first `"""` that is not escaped (`\"""`).  Block string
raw-value processing (as specified in the GraphQL spec):
1. Split on line terminators.
2. Remove leading whitespace from every line equal to the common indent of all
   non-empty lines after the first.
3. Remove the first line if it consists only of whitespace.
4. Remove the last line if it consists only of whitespace.
5. Join with `\n`.

Block strings appear frequently in introspection queries as description comments; they
must be handled correctly.

### The `...` punctuation

`...` is a single three-character token.  When the lexer sees `.` it must check whether
the next two characters are also `.`.  Seeing only one or two dots is a lexer error.

### Error reporting

A lexer error halts the entire parse by returning `nil, "line:col: message"` from
`graphql_parse`.  The lexer stores the last-seen position so the parser can propagate
the location without re-threading it through every caller.

## Parser design

The parser is a recursive-descent parser following the [GraphQL October 2021
specification](https://spec.graphql.org/October2021/).  Each non-terminal in the grammar
corresponds to a local `parse_*` function.

### Entry point

```lua
function graphql_parse(source)
  local lex = make_lexer(source)
  local ok, result = pcall(parse_document, lex)
  if ok then
    return result, nil
  else
    return nil, result  -- result is the error string thrown by lex:error()
  end
end
```

The lexer's `error()` method throws a Lua error string; `pcall` catches it and the
outer function returns `nil, errmsg`.

### Grammar productions

Each function below consumes tokens from `lex` and returns an AST node (see next section).
A `?` suffix means zero-or-one; a `*` suffix means zero-or-more; a `+` suffix means
one-or-more.

```
Document           → Definition+
Definition         → OperationDefinition | FragmentDefinition
OperationDefinition→ OperationType Name? VariableDefinitions? Directives? SelectionSet
                   | SelectionSet          (shorthand: anonymous query with no variables)
OperationType      → "query" | "mutation" | "subscription"
VariableDefinitions→ "(" VariableDefinition+ ")"
VariableDefinition → Variable ":" Type DefaultValue? Directives?
DefaultValue       → "=" Value
Variable           → "$" Name
SelectionSet       → "{" Selection+ "}"
Selection          → Field | FragmentSpread | InlineFragment
Field              → Alias? Name Arguments? Directives? SelectionSet?
Alias              → Name ":"
Arguments          → "(" Argument+ ")"
Argument           → Name ":" Value
FragmentSpread     → "..." FragmentName Directives?
InlineFragment     → "..." TypeCondition? Directives? SelectionSet
FragmentDefinition → "fragment" FragmentName TypeCondition Directives? SelectionSet
FragmentName       → Name but not "on"
TypeCondition      → "on" NamedType
Directives         → Directive+
Directive          → "@" Name Arguments?
Type               → NamedType | ListType | NonNullType
NamedType          → Name
ListType           → "[" Type "]"
NonNullType        → (NamedType | ListType) "!"
Value              → Variable | IntValue | FloatValue | StringValue
                   | BooleanValue | NullValue | EnumValue | ListValue | ObjectValue
BooleanValue       → "true" | "false"
NullValue          → "null"
EnumValue          → Name but not "true" | "false" | "null"
ListValue          → "[" Value* "]"
ObjectValue        → "{" ObjectField* "}"
ObjectField        → Name ":" Value
```

### Distinguishing `Field` from `FragmentSpread` / `InlineFragment`

All three alternatives in `Selection` can begin with a `NAME` or `...`.

- If the next token is `...`: look ahead one more token.
  - If it is a `NAME` that is not `on`: `FragmentSpread`.
  - Otherwise (it is `on` or `{` or `@`): `InlineFragment`.
- Otherwise: `Field`.

A `Field` begins with a `NAME`.  After consuming the name, peek at the next token:
- If it is `:`: the name was an alias; consume `:` and read the field name proper.
- Otherwise: no alias.

### Helper: `expect(lex, kind, value?)`

```lua
local function expect(lex, kind, value)
  local tok = lex:next()
  if tok.kind ~= kind or (value and tok.value ~= value) then
    lex:error("expected " .. (value or kind) .. ", got " .. tok.value)
  end
  return tok
end
```

Used throughout the parser for required punctuation and keywords.

### Helper: `peek_is(lex, kind, value?)`

Returns `true` if the next token matches without consuming it.  Used for optional
productions and the alternation checks in `Selection`.

## AST node reference

All nodes are plain Lua tables.  The `kind` field is a string constant identifying the
node type.  Fields that are optional in the grammar are `nil` when absent (not a missing
key — callers can test for `node.field` directly).  Array fields (selections, arguments,
directives, …) are always present as tables, possibly empty `{}`.

### DocumentNode

```lua
{
  kind        = "Document",
  definitions = { OperationDefinitionNode | FragmentDefinitionNode, ... },  -- 1+
}
```

### OperationDefinitionNode

```lua
{
  kind                 = "OperationDefinition",
  operation            = "query" | "mutation" | "subscription",
  name                 = NameNode | nil,
  variable_definitions = { VariableDefinitionNode, ... },
  directives           = { DirectiveNode, ... },
  selection_set        = SelectionSetNode,
}
```

Shorthand anonymous queries (`{ field }`) produce `operation = "query"`, `name = nil`,
`variable_definitions = {}`, `directives = {}`.

### FragmentDefinitionNode

```lua
{
  kind           = "FragmentDefinition",
  name           = NameNode,              -- never "on"
  type_condition = NamedTypeNode,
  directives     = { DirectiveNode, ... },
  selection_set  = SelectionSetNode,
}
```

### SelectionSetNode

```lua
{
  kind       = "SelectionSet",
  selections = { FieldNode | FragmentSpreadNode | InlineFragmentNode, ... },  -- 1+
}
```

### FieldNode

```lua
{
  kind          = "Field",
  alias         = NameNode | nil,
  name          = NameNode,
  arguments     = { ArgumentNode, ... },
  directives    = { DirectiveNode, ... },
  selection_set = SelectionSetNode | nil,
}
```

### ArgumentNode

```lua
{ kind = "Argument", name = NameNode, value = ValueNode }
```

### FragmentSpreadNode

```lua
{
  kind       = "FragmentSpread",
  name       = NameNode,
  directives = { DirectiveNode, ... },
}
```

### InlineFragmentNode

```lua
{
  kind           = "InlineFragment",
  type_condition = NamedTypeNode | nil,
  directives     = { DirectiveNode, ... },
  selection_set  = SelectionSetNode,
}
```

### DirectiveNode

```lua
{
  kind      = "Directive",
  name      = NameNode,
  arguments = { ArgumentNode, ... },
}
```

### VariableDefinitionNode

```lua
{
  kind          = "VariableDefinition",
  variable      = VariableNode,
  type          = TypeNode,
  default_value = ValueNode | nil,
  directives    = { DirectiveNode, ... },
}
```

### NameNode

```lua
{ kind = "Name", value = "identifierString" }
```

### VariableNode

```lua
{ kind = "Variable", name = NameNode }
```

### Type nodes

```lua
-- NamedTypeNode
{ kind = "NamedType", name = NameNode }

-- ListTypeNode
{ kind = "ListType", type = TypeNode }

-- NonNullTypeNode
{ kind = "NonNullType", type = NamedTypeNode | ListTypeNode }
```

### Value nodes

```lua
{ kind = "IntValue",     value = "42" }             -- raw string, not a number
{ kind = "FloatValue",   value = "3.14" }            -- raw string
{ kind = "StringValue",  value = "decoded content" } -- escape sequences applied
{ kind = "BooleanValue", value = true | false }      -- Lua boolean
{ kind = "NullValue" }
{ kind = "EnumValue",    value = "SOME_ENUM" }
{ kind = "ListValue",    values = { ValueNode, ... } }
{ kind = "ObjectValue",  fields = { ObjectFieldNode, ... } }
```

`IntValue` and `FloatValue` store the matched text as a string, not a number.  The
executor converts them when binding arguments to resolver parameters, where the target
type is known from the schema.

### ObjectFieldNode

```lua
{ kind = "ObjectField", name = NameNode, value = ValueNode }
```

## Module layout

```lua
-- internal/graphql_parser.lua
-- GraphQL document parser.
--
-- Exports: graphql_parse(source), graphql_tokenize(source)

local function make_lexer(source)    ... end
local function parse_document(lex)  ... end
-- ... (one local function per grammar production)

function graphql_parse(source)       ... end
function graphql_tokenize(source)    ... end
```

The module follows the same pattern as all other `internal/` modules: it runs in global
scope via `dofile`, exports globals, and does not use `require` or `return`.

## Load order

`graphql_parser.lua` must be loaded before `graphql_schema.lua` (which uses the parser to
load SDL) and before `graphql_executor.lua` (which parses incoming request documents).
Insert it immediately after `translators.lua` in `.init.lua`:

```lua
dofile("/zip/internal/translators.lua")
dofile("/zip/internal/graphql_parser.lua")   -- new
dofile("/zip/internal/families.lua")
```

## Unit test strategy

The parser is pure-function logic with no Redbean API calls; it can be tested entirely
in `redbean.com -i` mode without starting an HTTP server.  A `test/graphql-parser.lua`
unit test file should cover:

- **Shorthand query**: `{ viewer { login } }` — minimal document, anonymous operation.
- **Named query with variables**: `query GetRepo($owner: String!, $name: String!) { … }`.
- **Fragment spread and inline fragment**: both forms in one document.
- **All value kinds**: a query with arguments covering `Int`, `Float`, `String`, `Boolean`,
  `null`, `Enum`, `List`, and `Object` values.
- **Block string**: a query containing a block-string argument value.
- **Aliases**: `aliasName: fieldName`.
- **`@skip` and `@include`** directives.
- **Multiple operations in one document** (legal; the executor selects by `operationName`).
- **Error cases**: unclosed brace, bad escape in string, `...` with only two dots,
  integer followed immediately by identifier (lexer error), `fragment on Type { }` (missing
  fragment name).

Each test asserts the returned AST shape (specific `kind` fields and structural properties)
or that `graphql_parse` returns `nil` plus an error string containing `"line:col"`.

## What this document does not cover

- **SDL parsing** (schema definition language): a separate concern addressed in
  [03-schema.md](03-schema.md).  The schema SDL is loaded once at startup, not on every
  request; it may use a different (simpler) approach.
- **Validation** of the parsed document against the schema: covered in
  [04-executor.md](04-executor.md).
- **Variable coercion** (converting raw `IntValue`/`FloatValue` strings to Lua numbers for
  resolver calls): covered in [04-executor.md](04-executor.md).
