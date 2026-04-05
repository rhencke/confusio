GET http://{{host}}/api/v1/version

HTTP 200
[Asserts]
header "Content-Type" contains "application/json"
jsonpath "$.version" isString
