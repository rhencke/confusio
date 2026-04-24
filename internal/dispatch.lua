-- HTTP request dispatcher.
--
-- Exports make_dispatcher(a), a factory that returns the OnHttpRequest closure
-- bound over the app context a.  The closure reads auth policy, backend handlers,
-- and router lookups exclusively from a — no ambient globals at dispatch time.
-- Requires all internal modules to be loaded first (http, proxy, router, catalog).
--
-- Auth bypass for /webhooks/*: forge webhook deliveries carry their own
-- authentication (signature headers or tokens) and must not be gated by the
-- REST API auth check.  Requests whose path starts with /webhooks/ are routed
-- to a.webhook_receiver (installed by .init.lua) before the auth check runs.

function make_dispatcher(a) -- luacheck: globals make_dispatcher
  return function()
    -- Webhook paths bypass the auth gate entirely.  /webhooks/targets* routes
    -- to the target admin API (which enforces its own auth); all other
    -- /webhooks/* paths route to the webhook receiver which verifies
    -- forge-supplied signatures independently.
    if GetPath():match("^/webhooks/") then
      if GetPath():match("^/webhooks/targets") and a.targets_api then
        -- /webhooks/targets/{id}/deliveries is handled by the deliveries API.
        if GetPath():match("^/webhooks/targets/[^/]+/deliveries") and a.deliveries_api then
          a.deliveries_api()
        else
          a.targets_api()
        end
      elseif GetPath():match("^/webhooks/deliveries") and a.deliveries_api then
        a.deliveries_api()
      elseif GetPath():match("^/webhooks/events/[^/]+/deliveries") and a.deliveries_api then
        a.deliveries_api()
      elseif a.webhook_receiver then
        a.webhook_receiver()
      else
        respond_json(404, { message = "Not Found" })
      end
      return
    end

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
