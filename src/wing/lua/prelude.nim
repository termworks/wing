## The `wing` module every config sees, written in Lua and compiled in.
##
## The whole namespace lives here rather than being grown one registrar at a time from Nim, so the
## shape of `wing.*` is readable in one place. Settings are assigned onto the table, behaviour is
## registered by calling it, and a config file returns nothing -- the host reads these tables back
## after every chunk has run.

const WingPrelude* = """
local wing = {}

-- Templates are registered by name into a table the host reads once every config has run. Keyed
-- rather than appended, so registering a name twice replaces it: that is what lets a user config
-- override a bundled template instead of ending up with two of them.
wing.templates = {}

function wing.template(name, spec)
  if type(name) ~= "string" or name == "" then
    error("wing.template requires a template name", 2)
  end
  if type(spec) ~= "table" then
    error("wing.template('" .. tostring(name) .. "') requires a table", 2)
  end
  spec.name = name
  wing.templates[name] = spec
end

-- Placeholder tokens, keyed by the token they replace. The value is a string, or a function of the
-- apply context returning one. Keyed for the same reason templates are: a config can replace what
-- a bundled manifest set up.
wing.placeholders = {}

-- Behaviour, registered rather than assigned into a single hook field, so a config is as many
-- small named functions as it wants and one that raises does not cost the rest.
wing.on = {}

wing.on._apply = {}
function wing.on.apply(handler)
  if type(handler) ~= "function" then
    error("wing.on.apply requires a function", 2)
  end
  wing.on._apply[#wing.on._apply + 1] = handler
end

-- Reserved, and deliberately named now rather than later: the namespace is settled so that adding
-- machines or sync does not have to reshape what templates already occupy.
--   wing.machine(name, spec)
--   wing.sync(name, spec)
--   wing.tui.keys[key] = handler

_G.wing = wing
package.loaded["wing"] = wing
return wing
"""
