# vendor: GitHub GraphQL Schema

Source: https://docs.github.com/public/fpt/schema.docs.graphql
License: CC-BY-4.0 (see LICENSE)

## Contents

- `schema.docs.graphql` — GitHub's published GraphQL SDL snapshot
- `LICENSE` — upstream CC-BY-4.0 license (from github/docs)

## Updating

```bash
curl -fsSL https://docs.github.com/public/fpt/schema.docs.graphql \
  -o vendor/github-graphql-schema/schema.docs.graphql
```

After updating, regenerate the schema data:

```bash
make generate-schema
```

Then run `make test` to confirm `validate-schema` passes.
