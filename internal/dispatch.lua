-- HTTP request dispatcher.
--
-- Defines OnHttpRequest, the Redbean entry point for every incoming request.
-- Requires all internal modules to be loaded first (http, proxy, router, catalog).
-- Reads auth policy and backend handlers from the app context (see internal/context.lua).

function OnHttpRequest()
  if not app.allow_anonymous and not GetHeader("Authorization") then
    respond_json(401, { message = "This instance requires authentication." })
    return
  end
  local ep, caps, default_fn = route_match(GetMethod(), GetPath())
  if ep then
    local fn = app.backend_impl[ep] or default_fn
    if fn then
      fn(table.unpack(caps))
    else
      respond_json(404, { message = "Not Found" })
    end
  elseif path_known(GetPath()) then
    respond_json(405, { message = "Method Not Allowed" })
  else
    respond_json(404, { message = "Not Found" })
  end
end
