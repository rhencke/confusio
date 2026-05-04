-- Export the webhook event coverage catalog as JSON.
-- Run from the project root: ./redbean.com -i scripts/dump-webhook-catalog.lua

dofile("internal/webhook_catalog.lua")

io.write(EncodeJson(webhook_event_catalog) .. "\n") -- luacheck: globals webhook_event_catalog
