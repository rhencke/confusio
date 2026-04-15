# GraphQL smoke tests for the live Gitea integration suite.
# All queries here must work without authentication and without
# depending on specific repository data existing on gitea.com.

# POST /graphql — __typename always resolves
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ __typename }"}

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.data.__typename" == "Query"
jsonpath "$.errors" not exists

# POST /graphql �� rateLimit is synthesized by confusio (no upstream call)
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ rateLimit { limit remaining cost resetAt } }"}

HTTP 200
[Asserts]
jsonpath "$.data.rateLimit.limit" isInteger
jsonpath "$.data.rateLimit.remaining" isInteger
jsonpath "$.data.rateLimit.cost" isInteger
jsonpath "$.data.rateLimit.resetAt" isString
jsonpath "$.errors" not exists

# POST /graphql — introspection answered from vendored schema
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ __schema { queryType { name } mutationType { name } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.__schema.queryType.name" == "Query"
jsonpath "$.data.__schema.mutationType.name" == "Mutation"
jsonpath "$.errors" not exists

# POST /graphql �� parse error returns PARSE_ERROR
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ broken!!!"}

HTTP 200
[Asserts]
jsonpath "$.data" == null
jsonpath "$.errors[0].extensions.code" == "PARSE_ERROR"

# POST /graphql — validation error returns VALIDATION_ERROR
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ fieldThatDoesNotExistAnywhere }"}

HTTP 200
[Asserts]
jsonpath "$.data" == null
jsonpath "$.errors[0].extensions.code" == "VALIDATION_ERROR"

# POST /graphql — batch rejection
POST http://{{host}}/graphql
Content-Type: application/json
[{"query": "{ __typename }"}]

HTTP 400
[Asserts]
jsonpath "$.errors[0].message" contains "batching is not supported"
