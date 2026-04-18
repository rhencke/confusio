-- HTTP request dispatcher.
--
-- Exports make_dispatcher(a), a factory that returns the OnHttpRequest closure
-- bound over the app context a.  The closure reads auth policy, backend handlers,
-- and router lookups exclusively from a — no ambient globals at dispatch time.
-- Requires all internal modules to be loaded first (http, proxy, router, catalog).

function make_dispatcher(a) -- luacheck: globals make_dispatcher
  return function()
    if not a.allow_anonymous and not GetHeader("Authorization") then
      respond_json(401, { message = "This instance requires authentication." })
      return
    end
    local ep, caps, default_fn = a.route_match(GetMethod(), GetPath())
    if ep then
      local fn = a.backend.rest[ep] or default_fn
      if fn then
        fn(table.unpack(caps))
      else
        respond_json(404, { message = "Not Found" })
      end
    elseif a.path_known(GetPath()) then
      respond_json(405, { message = "Method Not Allowed" })
    else
      respond_json(404, { message = "Not Found" })
    end
  end
end
