# GraphQL API — executor is always active; all backends use graphql_handler.
# These tests cover request-level and schema-level errors that are backend-agnostic:
# they do not depend on any resolver and run for every backend.

# POST /graphql — __typename on the Query root is always resolved
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ __typename }"}

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.data.__typename" == "Query"

# POST /graphql — batch request rejected with HTTP 400
POST http://{{host}}/graphql
Content-Type: application/json
[{"query": "{ __typename }"}]

HTTP 400
[Asserts]
jsonpath "$.errors[0].message" isString

# POST /graphql — invalid body (not JSON) → BAD_USER_INPUT
POST http://{{host}}/graphql
Content-Type: application/json
`not json`

HTTP 200
[Asserts]
jsonpath "$.data" == null
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — parse error returns PARSE_ERROR extension code
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ unclosed_brace"}

HTTP 200
[Asserts]
jsonpath "$.data" == null
jsonpath "$.errors[0].extensions.code" == "PARSE_ERROR"

# POST /graphql — unknown field returns VALIDATION_ERROR extension code
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ fieldThatDoesNotExistAnywhere }"}

HTTP 200
[Asserts]
jsonpath "$.data" == null
jsonpath "$.errors[0].extensions.code" == "VALIDATION_ERROR"
