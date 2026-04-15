# GraphQL API — executor is always active; all backends use graphql_handler.
# Resolvers are not yet registered for any backend, so fields that require a
# REST call return null. The meta-field __typename is handled directly by the
# executor without any resolver and works for all backends.

# POST /graphql — __typename on the Query root is always resolved
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ __typename }"}

HTTP 200
[Asserts]
jsonpath "$.data.__typename" == "Query"

# POST /graphql — parse error returns {"data":null,"errors":[...]}
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ unclosed_brace"}

HTTP 200
[Asserts]
jsonpath "$.data" == null
jsonpath "$.errors" isCollection
