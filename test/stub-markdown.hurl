# Markdown API assertions — stub defaults (no native support on any backend).

# POST /markdown — not supported
POST http://{{host}}/markdown
Authorization: token testtoken
Content-Type: application/json
{"text": "Hello **world**"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /markdown/raw — not supported
POST http://{{host}}/markdown/raw
Authorization: token testtoken
Content-Type: text/plain
Hello **world**

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString
