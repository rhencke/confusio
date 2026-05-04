-- Table-driven translator helpers (global: backends/<name>.lua uses them).
--
-- make_translator returns a callable table.  Calling it applies a declarative
-- output spec to an input table while preserving existing callsites:
--   local translate_label = make_translator({ id = "id", node_id = const("") })
--   translate_label(label)

local TRANSLATOR_SPEC_MT = {}

local function make_spec(kind, opts)
  opts.kind = kind
  return opts
end

function field(key, opts)
  opts = opts or {}
  opts.key = key
  return make_spec("field", opts)
end

function const(value)
  return make_spec("const", { value = value })
end

function nested(translator, key)
  return make_spec("nested", { translator = translator, key = key })
end

function each(translator, key)
  return make_spec("each", { translator = translator, key = key })
end

function translate_list_fn(translator)
  return function(items)
    return translate_list(translator, items)
  end
end

function computed(fn)
  return make_spec("computed", { fn = fn })
end

local function apply_transform(transform, value)
  if transform then
    return transform(value)
  end
  return value
end

local function resolve_field(spec, input, output_key)
  local source_key = spec.key or output_key
  local value = input[source_key]
  if value == nil and spec.default ~= nil then
    value = spec.default
  end
  return apply_transform(spec.transform, value)
end

local function resolve_value(spec, input, output_key, ...)
  if type(spec) == "string" then
    return input[spec]
  end
  if type(spec) ~= "table" or spec.kind == nil then
    return spec
  end
  if spec.kind == "const" then
    return spec.value
  end
  if spec.kind == "field" then
    return resolve_field(spec, input, output_key)
  end
  if spec.kind == "nested" then
    local value = input[spec.key or output_key]
    return spec.translator(value)
  end
  if spec.kind == "each" then
    local value = input[spec.key or output_key]
    return translate_list(spec.translator, value)
  end
  if spec.kind == "computed" then
    return spec.fn(input, ...)
  end
  error(
    "unknown translator spec kind for field " .. tostring(output_key) .. ": " .. tostring(spec.kind)
  )
end

local function translator_apply(translator, input, ...)
  if input == nil then
    if translator.nil_returns_nil then
      return nil
    end
    return {}
  end
  local output = {}
  if translator.passthrough then
    for key, value in pairs(input) do
      output[key] = value
    end
  end
  for output_key, spec in pairs(translator.spec) do
    local ok, value = pcall(resolve_value, spec, input, output_key, ...)
    if not ok then
      error("translator field " .. tostring(output_key) .. ": " .. tostring(value))
    end
    output[output_key] = value
  end
  return output
end

TRANSLATOR_SPEC_MT.__call = translator_apply

function make_translator(spec, opts)
  opts = opts or {}
  return setmetatable({
    spec = spec,
    nil_returns_nil = opts.nil_returns_nil == true,
    passthrough = opts.passthrough == true,
  }, TRANSLATOR_SPEC_MT)
end
