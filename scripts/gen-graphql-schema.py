#!/usr/bin/env python3
"""Parse the vendored GitHub GraphQL SDL and emit internal/graphql_schema_data.lua.

Usage:
  python3 scripts/gen-graphql-schema.py [sdl] [output]

  sdl     path to SDL file  (default: vendor/github-graphql-schema/schema.docs.graphql)
  output  path to write Lua (default: internal/graphql_schema_data.lua)

The output is a Lua table literal assigning a global `graphql_schema_data`.
Only types reachable from the Query and Mutation root types are included,
plus built-in scalars and introspection meta-types.
"""

import re
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# SDL tokeniser — just enough to handle the GitHub schema
# ---------------------------------------------------------------------------

# Token types: NAME, STRING (block or single-line), PUNCT, DIRECTIVE
# We skip comments (#...) and whitespace.

_TOKEN_RE = re.compile(
    r"""
    (?P<BLOCK_STRING>\"\"\"[\s\S]*?\"\"\")     |
    (?P<STRING>\"(?:[^\"\\]|\\.)*\")           |
    (?P<NUMBER>-?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?) |
    (?P<NAME>[_A-Za-z][_0-9A-Za-z]*)          |
    (?P<PUNCT>[{}()\[\]!:=|&@])                |
    (?P<COMMENT>\#[^\n]*)                      |
    (?P<WS>\s+)
    """,
    re.VERBOSE,
)


def tokenize(text):
    """Yield (kind, value) pairs from SDL text."""
    for m in _TOKEN_RE.finditer(text):
        kind = m.lastgroup
        if kind in ("COMMENT", "WS"):
            continue
        val = m.group()
        if kind == "BLOCK_STRING":
            # Strip the triple-quote delimiters and dedent
            val = _dedent_block_string(val[3:-3])
            kind = "STRING"
        elif kind == "STRING":
            val = val[1:-1].replace('\\"', '"').replace("\\\\", "\\")
            kind = "STRING"
        yield kind, val


def _dedent_block_string(raw):
    """Dedent a GraphQL block string (triple-quoted) per the spec algorithm."""
    lines = raw.split("\n")
    # Find common indent of non-empty lines after the first
    common_indent = None
    for line in lines[1:]:
        stripped = line.lstrip(" \t")
        if stripped:
            indent = len(line) - len(stripped)
            if common_indent is None or indent < common_indent:
                common_indent = indent
    if common_indent and common_indent > 0:
        lines = [lines[0]] + [
            line[common_indent:] if len(line) >= common_indent else line
            for line in lines[1:]
        ]
    # Strip leading/trailing blank lines
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# SDL parser — builds a dict of type definitions
# ---------------------------------------------------------------------------


class Parser:
    """Minimal SDL parser for the GitHub schema."""

    def __init__(self, text):
        self.tokens = list(tokenize(text))
        self.pos = 0

    def peek(self, offset=0):
        i = self.pos + offset
        if i < len(self.tokens):
            return self.tokens[i]
        return ("EOF", "")

    def advance(self):
        tok = self.tokens[self.pos]
        self.pos += 1
        return tok

    def expect(self, kind, value=None):
        tok = self.advance()
        if tok[0] != kind or (value is not None and tok[1] != value):
            raise SyntaxError(f"Expected ({kind}, {value!r}), got {tok!r} at pos {self.pos}")
        return tok

    def expect_punct(self, ch):
        return self.expect("PUNCT", ch)

    def at_end(self):
        return self.pos >= len(self.tokens)

    def parse(self):
        """Parse the full SDL, returning {name: type_def} dict."""
        types = {}
        while not self.at_end():
            desc = self._maybe_description()
            if self.at_end():
                break
            kind, val = self.peek()
            if kind == "NAME":
                if val == "type":
                    td = self._parse_object_type(desc)
                    types[td["name"]] = td
                elif val == "interface":
                    td = self._parse_interface_type(desc)
                    types[td["name"]] = td
                elif val == "union":
                    td = self._parse_union_type(desc)
                    types[td["name"]] = td
                elif val == "enum":
                    td = self._parse_enum_type(desc)
                    types[td["name"]] = td
                elif val == "input":
                    td = self._parse_input_object_type(desc)
                    types[td["name"]] = td
                elif val == "scalar":
                    td = self._parse_scalar_type(desc)
                    types[td["name"]] = td
                elif val == "directive":
                    self._skip_directive_def()
                elif val == "schema":
                    self._skip_schema_def()
                elif val == "extend":
                    self._skip_extend_def()
                else:
                    self.advance()  # skip unknown
            else:
                self.advance()
        return types

    def _maybe_description(self):
        if not self.at_end() and self.peek()[0] == "STRING":
            return self.advance()[1]
        return None

    def _parse_object_type(self, desc):
        self.expect("NAME", "type")
        name = self.expect("NAME")[1]
        interfaces = self._parse_implements()
        self._skip_directives()
        fields = self._parse_field_defs()
        return {
            "kind": "OBJECT",
            "name": name,
            "description": desc,
            "interfaces": interfaces,
            "fields": fields,
        }

    def _parse_interface_type(self, desc):
        self.expect("NAME", "interface")
        name = self.expect("NAME")[1]
        interfaces = self._parse_implements()
        self._skip_directives()
        fields = self._parse_field_defs()
        return {
            "kind": "INTERFACE",
            "name": name,
            "description": desc,
            "interfaces": interfaces,
            "fields": fields,
        }

    def _parse_union_type(self, desc):
        self.expect("NAME", "union")
        name = self.expect("NAME")[1]
        self._skip_directives()
        self.expect_punct("=")
        # Optional leading |
        if not self.at_end() and self.peek() == ("PUNCT", "|"):
            self.advance()
        members = [self.expect("NAME")[1]]
        while not self.at_end() and self.peek() == ("PUNCT", "|"):
            self.advance()
            members.append(self.expect("NAME")[1])
        return {
            "kind": "UNION",
            "name": name,
            "description": desc,
            "possible_types": members,
        }

    def _parse_enum_type(self, desc):
        self.expect("NAME", "enum")
        name = self.expect("NAME")[1]
        self._skip_directives()
        self.expect_punct("{")
        values = []
        while not self.at_end() and self.peek() != ("PUNCT", "}"):
            vdesc = self._maybe_description()
            vname = self.expect("NAME")[1]
            deprecated = self._has_deprecated_directive()
            self._skip_directives()
            values.append({"name": vname, "description": vdesc, "is_deprecated": deprecated})
        self.expect_punct("}")
        return {
            "kind": "ENUM",
            "name": name,
            "description": desc,
            "values": values,
        }

    def _parse_input_object_type(self, desc):
        self.expect("NAME", "input")
        name = self.expect("NAME")[1]
        self._skip_directives()
        self.expect_punct("{")
        fields = []
        while not self.at_end() and self.peek() != ("PUNCT", "}"):
            fields.append(self._parse_input_value_def())
        self.expect_punct("}")
        return {
            "kind": "INPUT_OBJECT",
            "name": name,
            "description": desc,
            "input_fields": fields,
        }

    def _parse_scalar_type(self, desc):
        self.expect("NAME", "scalar")
        name = self.expect("NAME")[1]
        self._skip_directives()
        return {
            "kind": "SCALAR",
            "name": name,
            "description": desc,
        }

    def _parse_implements(self):
        interfaces = []
        if not self.at_end() and self.peek() == ("NAME", "implements"):
            self.advance()
            # Optional leading &
            if not self.at_end() and self.peek() == ("PUNCT", "&"):
                self.advance()
            interfaces.append(self.expect("NAME")[1])
            while not self.at_end() and self.peek() == ("PUNCT", "&"):
                self.advance()
                interfaces.append(self.expect("NAME")[1])
        return interfaces

    def _parse_field_defs(self):
        self.expect_punct("{")
        fields = []
        while not self.at_end() and self.peek() != ("PUNCT", "}"):
            fields.append(self._parse_field_def())
        self.expect_punct("}")
        return fields

    def _parse_field_def(self):
        desc = self._maybe_description()
        name = self.expect("NAME")[1]
        args = self._parse_arguments_def()
        self.expect_punct(":")
        type_ref = self._parse_type_ref()
        self._skip_directives()
        return {"name": name, "type": type_ref, "description": desc, "args": args}

    def _parse_arguments_def(self):
        if self.at_end() or self.peek() != ("PUNCT", "("):
            return []
        self.advance()  # (
        args = []
        while not self.at_end() and self.peek() != ("PUNCT", ")"):
            args.append(self._parse_input_value_def())
        self.expect_punct(")")
        return args

    def _parse_input_value_def(self):
        desc = self._maybe_description()
        name = self.expect("NAME")[1]
        self.expect_punct(":")
        type_ref = self._parse_type_ref()
        default = self._parse_default_value()
        self._skip_directives()
        return {
            "name": name,
            "type": type_ref,
            "description": desc,
            "default_value": default,
        }

    def _parse_type_ref(self):
        """Parse a type reference and return the SDL-notation string."""
        if not self.at_end() and self.peek() == ("PUNCT", "["):
            self.advance()
            inner = self._parse_type_ref()
            self.expect_punct("]")
            s = f"[{inner}]"
        else:
            s = self.expect("NAME")[1]
        if not self.at_end() and self.peek() == ("PUNCT", "!"):
            self.advance()
            s += "!"
        return s

    def _parse_default_value(self):
        """Parse an optional = defaultValue. Returns the string representation or None."""
        if self.at_end() or self.peek() != ("PUNCT", "="):
            return None
        self.advance()  # =
        return self._parse_value_literal()

    def _parse_value_literal(self):
        """Parse a value literal and return its string representation."""
        kind, val = self.peek()
        if kind == "STRING":
            self.advance()
            return f'"{val}"'
        if kind == "NAME":
            self.advance()
            # true, false, null, or enum value
            return val
        if kind == "NUMBER":
            self.advance()
            return val
        if kind == "PUNCT" and val == "[":
            return self._parse_list_value()
        if kind == "PUNCT" and val == "{":
            return self._parse_object_value()
        self.advance()
        return val

    def _parse_list_value(self):
        self.advance()  # [
        items = []
        while not self.at_end() and self.peek() != ("PUNCT", "]"):
            items.append(self._parse_value_literal())
        self.expect_punct("]")
        return "[" + ", ".join(items) + "]"

    def _parse_object_value(self):
        self.advance()  # {
        pairs = []
        while not self.at_end() and self.peek() != ("PUNCT", "}"):
            k = self.expect("NAME")[1]
            self.expect_punct(":")
            v = self._parse_value_literal()
            pairs.append(f"{k}: {v}")
        self.expect_punct("}")
        return "{" + ", ".join(pairs) + "}"

    def _has_deprecated_directive(self):
        """Check if the next tokens are @deprecated; consume them if so and return True."""
        if (
            not self.at_end()
            and self.peek() == ("PUNCT", "@")
            and self.pos + 1 < len(self.tokens)
            and self.tokens[self.pos + 1] == ("NAME", "deprecated")
        ):
            # Don't consume — _skip_directives will handle it
            return True
        return False

    def _skip_directives(self):
        """Skip zero or more directives (@name or @name(...))."""
        while not self.at_end() and self.peek() == ("PUNCT", "@"):
            self.advance()  # @
            self.expect("NAME")  # directive name
            if not self.at_end() and self.peek() == ("PUNCT", "("):
                self._skip_balanced("(", ")")

    def _skip_balanced(self, open_ch, close_ch):
        self.expect_punct(open_ch)
        depth = 1
        while depth > 0 and not self.at_end():
            kind, val = self.advance()
            if kind == "PUNCT" and val == open_ch:
                depth += 1
            elif kind == "PUNCT" and val == close_ch:
                depth -= 1

    def _skip_directive_def(self):
        """Skip a directive definition."""
        self.expect("NAME", "directive")
        self.expect_punct("@")
        self.expect("NAME")
        if not self.at_end() and self.peek() == ("PUNCT", "("):
            self._skip_balanced("(", ")")
        # skip optional 'repeatable'
        if not self.at_end() and self.peek() == ("NAME", "repeatable"):
            self.advance()
        self.expect("NAME", "on")
        # skip location list: NAME | NAME | ...
        self.expect("NAME")
        while not self.at_end() and self.peek() == ("PUNCT", "|"):
            self.advance()
            self.expect("NAME")

    def _skip_schema_def(self):
        """Skip a schema { ... } definition."""
        self.expect("NAME", "schema")
        self._skip_directives()
        if not self.at_end() and self.peek() == ("PUNCT", "{"):
            self._skip_balanced("{", "}")

    def _skip_extend_def(self):
        """Skip an extend type/schema/etc definition."""
        self.expect("NAME", "extend")
        # Skip until we've consumed the body
        kind, val = self.peek()
        if kind == "NAME" and val == "schema":
            self._skip_schema_def()
        elif kind == "NAME" and val in ("type", "interface", "input"):
            self.advance()  # type/interface/input
            self.expect("NAME")  # name
            self._parse_implements()
            self._skip_directives()
            if not self.at_end() and self.peek() == ("PUNCT", "{"):
                self._skip_balanced("{", "}")
        elif kind == "NAME" and val == "union":
            self.advance()
            self.expect("NAME")
            self._skip_directives()
            if not self.at_end() and self.peek() == ("PUNCT", "="):
                self.advance()
                self.expect("NAME")
                while not self.at_end() and self.peek() == ("PUNCT", "|"):
                    self.advance()
                    self.expect("NAME")
        elif kind == "NAME" and val == "enum":
            self.advance()
            self.expect("NAME")
            self._skip_directives()
            if not self.at_end() and self.peek() == ("PUNCT", "{"):
                self._skip_balanced("{", "}")
        elif kind == "NAME" and val == "scalar":
            self.advance()
            self.expect("NAME")
            self._skip_directives()


# ---------------------------------------------------------------------------
# Reachability analysis
# ---------------------------------------------------------------------------

_BASE_TYPE_RE = re.compile(r"[_A-Za-z][_0-9A-Za-z]*")


def base_type(type_ref):
    """Extract the named type from a type reference string."""
    m = _BASE_TYPE_RE.search(type_ref)
    return m.group() if m else None


def compute_reachable(types, roots):
    """Return the set of type names reachable from roots via field/arg/member references."""
    visited = set()
    stack = list(roots)
    while stack:
        name = stack.pop()
        if name in visited:
            continue
        visited.add(name)
        td = types.get(name)
        if td is None:
            continue
        kind = td["kind"]
        if kind in ("OBJECT", "INTERFACE"):
            for iface in td.get("interfaces", []):
                stack.append(iface)
            for field in td.get("fields", []):
                bt = base_type(field["type"])
                if bt:
                    stack.append(bt)
                for arg in field.get("args", []):
                    bt = base_type(arg["type"])
                    if bt:
                        stack.append(bt)
        elif kind == "UNION":
            for member in td.get("possible_types", []):
                stack.append(member)
        elif kind == "INPUT_OBJECT":
            for f in td.get("input_fields", []):
                bt = base_type(f["type"])
                if bt:
                    stack.append(bt)
        # ENUM and SCALAR have no outgoing references
    return visited


# ---------------------------------------------------------------------------
# Populate interface/union possible_types (reverse mapping)
# ---------------------------------------------------------------------------


def populate_possible_types(types, reachable):
    """For INTERFACE and UNION types, populate possible_types from reachable OBJECTs."""
    # Build reverse map: interface name -> list of implementing object names
    iface_impls = {}
    for name in reachable:
        td = types.get(name)
        if td and td["kind"] == "OBJECT":
            for iface in td.get("interfaces", []):
                if iface in reachable:
                    iface_impls.setdefault(iface, []).append(name)

    for name in reachable:
        td = types.get(name)
        if td and td["kind"] == "INTERFACE":
            td["possible_types"] = sorted(iface_impls.get(name, []))
    # UNION possible_types are already set from the SDL


# ---------------------------------------------------------------------------
# Built-in scalars and introspection meta-types
# ---------------------------------------------------------------------------

BUILTIN_SCALARS = {
    "String": {"kind": "SCALAR", "name": "String", "description": "The `String` scalar type represents textual data, represented as UTF-8 character sequences."},
    "Int": {"kind": "SCALAR", "name": "Int", "description": "The `Int` scalar type represents non-fractional signed whole numeric values."},
    "Float": {"kind": "SCALAR", "name": "Float", "description": "The `Float` scalar type represents signed double-precision fractional values."},
    "Boolean": {"kind": "SCALAR", "name": "Boolean", "description": "The `Boolean` scalar type represents `true` or `false`."},
    "ID": {"kind": "SCALAR", "name": "ID", "description": "The `ID` scalar type represents a unique identifier."},
}

INTROSPECTION_TYPES = {
    "__Schema": {
        "kind": "OBJECT",
        "name": "__Schema",
        "description": "A GraphQL Schema defines the capabilities of a GraphQL server.",
        "interfaces": [],
        "fields": [
            {"name": "description", "type": "String", "description": None, "args": []},
            {"name": "types", "type": "[__Type!]!", "description": "A list of all types supported by this server.", "args": []},
            {"name": "queryType", "type": "__Type!", "description": "The type that query operations will be rooted at.", "args": []},
            {"name": "mutationType", "type": "__Type", "description": "If this server supports mutation, the type that mutation operations will be rooted at.", "args": []},
            {"name": "subscriptionType", "type": "__Type", "description": "If this server support subscription, the type that subscription operations will be rooted at.", "args": []},
            {"name": "directives", "type": "[__Directive!]!", "description": "A list of all directives supported by this server.", "args": []},
        ],
    },
    "__Type": {
        "kind": "OBJECT",
        "name": "__Type",
        "description": "The fundamental unit of any GraphQL Schema is the type.",
        "interfaces": [],
        "fields": [
            {"name": "kind", "type": "__TypeKind!", "description": None, "args": []},
            {"name": "name", "type": "String", "description": None, "args": []},
            {"name": "description", "type": "String", "description": None, "args": []},
            {"name": "fields", "type": "[__Field!]", "description": None, "args": [
                {"name": "includeDeprecated", "type": "Boolean", "description": None, "default_value": "false"},
            ]},
            {"name": "interfaces", "type": "[__Type!]", "description": None, "args": []},
            {"name": "possibleTypes", "type": "[__Type!]", "description": None, "args": []},
            {"name": "enumValues", "type": "[__EnumValue!]", "description": None, "args": [
                {"name": "includeDeprecated", "type": "Boolean", "description": None, "default_value": "false"},
            ]},
            {"name": "inputFields", "type": "[__InputValue!]", "description": None, "args": [
                {"name": "includeDeprecated", "type": "Boolean", "description": None, "default_value": "false"},
            ]},
            {"name": "ofType", "type": "__Type", "description": None, "args": []},
            {"name": "specifiedByURL", "type": "String", "description": None, "args": []},
        ],
    },
    "__Field": {
        "kind": "OBJECT",
        "name": "__Field",
        "description": "Object and Interface types are described by a list of Fields.",
        "interfaces": [],
        "fields": [
            {"name": "name", "type": "String!", "description": None, "args": []},
            {"name": "description", "type": "String", "description": None, "args": []},
            {"name": "args", "type": "[__InputValue!]!", "description": None, "args": [
                {"name": "includeDeprecated", "type": "Boolean", "description": None, "default_value": "false"},
            ]},
            {"name": "type", "type": "__Type!", "description": None, "args": []},
            {"name": "isDeprecated", "type": "Boolean!", "description": None, "args": []},
            {"name": "deprecationReason", "type": "String", "description": None, "args": []},
        ],
    },
    "__InputValue": {
        "kind": "OBJECT",
        "name": "__InputValue",
        "description": "Arguments provided to Fields or Directives and the input fields of an InputObject.",
        "interfaces": [],
        "fields": [
            {"name": "name", "type": "String!", "description": None, "args": []},
            {"name": "description", "type": "String", "description": None, "args": []},
            {"name": "type", "type": "__Type!", "description": None, "args": []},
            {"name": "defaultValue", "type": "String", "description": "A GraphQL-formatted string representing the default value for this input value.", "args": []},
            {"name": "isDeprecated", "type": "Boolean!", "description": None, "args": []},
            {"name": "deprecationReason", "type": "String", "description": None, "args": []},
        ],
    },
    "__EnumValue": {
        "kind": "OBJECT",
        "name": "__EnumValue",
        "description": "One possible value for a given Enum.",
        "interfaces": [],
        "fields": [
            {"name": "name", "type": "String!", "description": None, "args": []},
            {"name": "description", "type": "String", "description": None, "args": []},
            {"name": "isDeprecated", "type": "Boolean!", "description": None, "args": []},
            {"name": "deprecationReason", "type": "String", "description": None, "args": []},
        ],
    },
    "__Directive": {
        "kind": "OBJECT",
        "name": "__Directive",
        "description": "A Directive provides a way to describe alternate runtime execution and type validation behavior.",
        "interfaces": [],
        "fields": [
            {"name": "name", "type": "String!", "description": None, "args": []},
            {"name": "description", "type": "String", "description": None, "args": []},
            {"name": "isRepeatable", "type": "Boolean!", "description": None, "args": []},
            {"name": "locations", "type": "[__DirectiveLocation!]!", "description": None, "args": []},
            {"name": "args", "type": "[__InputValue!]!", "description": None, "args": [
                {"name": "includeDeprecated", "type": "Boolean", "description": None, "default_value": "false"},
            ]},
        ],
    },
    "__TypeKind": {
        "kind": "ENUM",
        "name": "__TypeKind",
        "description": "An enum describing what kind of type a given `__Type` is.",
        "values": [
            {"name": "SCALAR", "description": "Indicates this type is a scalar.", "is_deprecated": False},
            {"name": "OBJECT", "description": "Indicates this type is an object.", "is_deprecated": False},
            {"name": "INTERFACE", "description": "Indicates this type is an interface.", "is_deprecated": False},
            {"name": "UNION", "description": "Indicates this type is a union.", "is_deprecated": False},
            {"name": "ENUM", "description": "Indicates this type is an enum.", "is_deprecated": False},
            {"name": "INPUT_OBJECT", "description": "Indicates this type is an input object.", "is_deprecated": False},
            {"name": "LIST", "description": "Indicates this type is a list.", "is_deprecated": False},
            {"name": "NON_NULL", "description": "Indicates this type is a non-null.", "is_deprecated": False},
        ],
    },
    "__DirectiveLocation": {
        "kind": "ENUM",
        "name": "__DirectiveLocation",
        "description": "A Directive can be adjacent to many parts of the GraphQL language.",
        "values": [
            {"name": "QUERY", "description": "Location adjacent to a query operation.", "is_deprecated": False},
            {"name": "MUTATION", "description": "Location adjacent to a mutation operation.", "is_deprecated": False},
            {"name": "SUBSCRIPTION", "description": "Location adjacent to a subscription operation.", "is_deprecated": False},
            {"name": "FIELD", "description": "Location adjacent to a field.", "is_deprecated": False},
            {"name": "FRAGMENT_DEFINITION", "description": "Location adjacent to a fragment definition.", "is_deprecated": False},
            {"name": "FRAGMENT_SPREAD", "description": "Location adjacent to a fragment spread.", "is_deprecated": False},
            {"name": "INLINE_FRAGMENT", "description": "Location adjacent to an inline fragment.", "is_deprecated": False},
            {"name": "VARIABLE_DEFINITION", "description": "Location adjacent to a variable definition.", "is_deprecated": False},
            {"name": "SCHEMA", "description": "Location adjacent to a schema definition.", "is_deprecated": False},
            {"name": "SCALAR", "description": "Location adjacent to a scalar definition.", "is_deprecated": False},
            {"name": "OBJECT", "description": "Location adjacent to an object type definition.", "is_deprecated": False},
            {"name": "FIELD_DEFINITION", "description": "Location adjacent to a field definition.", "is_deprecated": False},
            {"name": "ARGUMENT_DEFINITION", "description": "Location adjacent to an argument definition.", "is_deprecated": False},
            {"name": "INTERFACE", "description": "Location adjacent to an interface definition.", "is_deprecated": False},
            {"name": "UNION", "description": "Location adjacent to a union definition.", "is_deprecated": False},
            {"name": "ENUM", "description": "Location adjacent to an enum definition.", "is_deprecated": False},
            {"name": "ENUM_VALUE", "description": "Location adjacent to an enum value definition.", "is_deprecated": False},
            {"name": "INPUT_OBJECT", "description": "Location adjacent to an input object type definition.", "is_deprecated": False},
            {"name": "INPUT_FIELD_DEFINITION", "description": "Location adjacent to an input object field definition.", "is_deprecated": False},
        ],
    },
}


# ---------------------------------------------------------------------------
# Lua emitter
# ---------------------------------------------------------------------------


def lua_escape(s):
    """Escape a string for a Lua double-quoted literal."""
    if s is None:
        return "nil"
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def lua_bool(b):
    return "true" if b else "false"


def emit_lua(types, reachable, out):
    """Write the graphql_schema_data Lua table to out."""
    out.write("-- AUTO-GENERATED by scripts/gen-graphql-schema.py — do not edit.\n")
    out.write("-- Source: vendor/github-graphql-schema/schema.docs.graphql\n")
    out.write("\n")
    out.write("graphql_schema_data = {\n")
    out.write('  query_type        = "Query",\n')
    out.write('  mutation_type     = "Mutation",\n')
    out.write("  subscription_type = nil,\n")
    out.write("\n")
    out.write("  types = {\n")

    # Emit types in sorted order for stable diffs
    for name in sorted(reachable):
        td = types[name]
        _emit_type(td, out)

    out.write("  },\n")
    out.write("}\n")


def _emit_type(td, out):
    kind = td["kind"]
    name = td["name"]
    out.write(f"    [{lua_escape(name)}] = {{\n")
    out.write(f"      kind        = {lua_escape(kind)},\n")
    out.write(f"      name        = {lua_escape(name)},\n")
    out.write(f"      description = {lua_escape(td.get('description'))},\n")

    if kind in ("OBJECT", "INTERFACE"):
        ifaces = td.get("interfaces", [])
        out.write(f"      interfaces  = {_lua_string_list(ifaces)},\n")
        if kind == "INTERFACE":
            ptypes = td.get("possible_types", [])
            out.write(f"      possible_types = {_lua_string_list(ptypes)},\n")
        out.write("      fields      = {\n")
        for field in td.get("fields", []):
            _emit_field(field, out, indent=8)
        out.write("      },\n")
    elif kind == "UNION":
        ptypes = td.get("possible_types", [])
        out.write(f"      possible_types = {_lua_string_list(ptypes)},\n")
    elif kind == "ENUM":
        out.write("      values      = {\n")
        for val in td.get("values", []):
            out.write(f"        {{ name = {lua_escape(val['name'])}, description = {lua_escape(val.get('description'))}, is_deprecated = {lua_bool(val.get('is_deprecated', False))} }},\n")
        out.write("      },\n")
    elif kind == "INPUT_OBJECT":
        out.write("      input_fields = {\n")
        for f in td.get("input_fields", []):
            _emit_input_value(f, out, indent=8)
        out.write("      },\n")
    # SCALAR has no additional fields

    out.write("    },\n")


def _emit_field(field, out, indent=8):
    pad = " " * indent
    args = field.get("args", [])
    if args:
        out.write(f"{pad}{{ name = {lua_escape(field['name'])}, type = {lua_escape(field['type'])}, description = {lua_escape(field.get('description'))}, args = {{\n")
        for arg in args:
            _emit_input_value(arg, out, indent=indent + 2)
        out.write(f"{pad}}} }},\n")
    else:
        out.write(f"{pad}{{ name = {lua_escape(field['name'])}, type = {lua_escape(field['type'])}, description = {lua_escape(field.get('description'))}, args = {{}} }},\n")


def _emit_input_value(iv, out, indent=10):
    pad = " " * indent
    dv = iv.get("default_value")
    if dv is None:
        dv_lua = "nil"
    else:
        dv_lua = lua_escape(dv)
    out.write(f"{pad}{{ name = {lua_escape(iv['name'])}, type = {lua_escape(iv['type'])}, description = {lua_escape(iv.get('description'))}, default_value = {dv_lua} }},\n")


def _lua_string_list(items):
    if not items:
        return "{}"
    return "{ " + ", ".join(lua_escape(s) for s in items) + " }"


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main():
    sdl_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("vendor/github-graphql-schema/schema.docs.graphql")
    out_path = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("internal/graphql_schema_data.lua")

    sdl_text = sdl_path.read_text()
    parser = Parser(sdl_text)
    types = parser.parse()

    # Add built-in scalars (SDL usually omits them)
    for name, td in BUILTIN_SCALARS.items():
        types.setdefault(name, td)

    # Add introspection meta-types
    for name, td in INTROSPECTION_TYPES.items():
        types[name] = td

    # Compute reachability from Query and Mutation roots
    roots = ["Query", "Mutation"]
    reachable = compute_reachable(types, roots)

    # Always include introspection types and built-in scalars
    for name in INTROSPECTION_TYPES:
        reachable.add(name)
    for name in BUILTIN_SCALARS:
        reachable.add(name)

    # Populate possible_types for interfaces
    populate_possible_types(types, reachable)

    # Verify all reachable types exist
    missing = reachable - set(types.keys())
    if missing:
        print(f"Warning: {len(missing)} reachable types not found in SDL: {sorted(missing)[:10]}...", file=sys.stderr)
        reachable -= missing

    # Emit
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w") as f:
        emit_lua(types, reachable, f)

    print(f"Wrote {len(reachable)} types to {out_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
