function OnHttpRequest()
  if GetPath() == "/api/v1/version" then
    SetStatus(200, "OK")
    SetHeader("Content-Type", "application/json")
    Write('{"version":"1.20.0"}')
  else
    SetStatus(404, "Not Found")
  end
end
