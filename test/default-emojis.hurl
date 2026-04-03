GET http://{{host}}/emojis

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "{}"
