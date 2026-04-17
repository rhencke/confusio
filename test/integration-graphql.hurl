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

# POST /graphql — single-element array batch executes (Phase 2b: doc 12)
POST http://{{host}}/graphql
Content-Type: application/json
[{"query": "{ __typename }"}]

HTTP 200
[Asserts]
jsonpath "$[0].data.__typename" == "Query"
jsonpath "$[0].errors" not exists

# POST /graphql — multi-element batch: two independent queries execute and return
# results at their respective array indices (Phase 2b: GQL-23)
POST http://{{host}}/graphql
Content-Type: application/json
[{"query": "{ __typename }"},{"query": "{ rateLimit { limit remaining } }"}]

HTTP 200
[Asserts]
jsonpath "$[0].data.__typename" == "Query"
jsonpath "$[0].errors" not exists
jsonpath "$[1].data.rateLimit.limit" isInteger
jsonpath "$[1].data.rateLimit.remaining" isInteger
jsonpath "$[1].errors" not exists

# POST /graphql — batch error isolation: a parse error in one operation does not
# prevent other operations from succeeding (Phase 2b: GQL-23)
POST http://{{host}}/graphql
Content-Type: application/json
[{"query": "{ __typename }"},{"query": "{ broken!!!"},{"query": "{ __schema { queryType { name } } }"}]

HTTP 200
[Asserts]
jsonpath "$[0].data.__typename" == "Query"
jsonpath "$[0].errors" not exists
jsonpath "$[1].data" == null
jsonpath "$[1].errors[0].extensions.code" == "PARSE_ERROR"
jsonpath "$[2].data.__schema.queryType.name" == "Query"
jsonpath "$[2].errors" not exists
