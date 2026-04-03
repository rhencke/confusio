function OnHttpRequest()
  if (GetMethod() == "GET" or GetMethod() == "HEAD") and GetPath() == "/" then
    local host = GetHeader("Host")
    local base = GetScheme() .. "://" .. host
    SetStatus(200, "OK")
    SetHeader("Content-Type", "application/json; charset=utf-8")
    Write(EncodeJson({}))
  else
    Route()
  end
end
