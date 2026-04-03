# vendor: github/rest-api-description

Source: https://github.com/github/rest-api-description  
License: MIT (see LICENSE.md)

## Contents

- `api.github.com.yaml` — bundled OpenAPI 3.0 spec for the github.com REST API
- `LICENSE.md` — upstream MIT license

## Updating

```bash
curl -fsSL https://raw.githubusercontent.com/github/rest-api-description/main/descriptions/api.github.com/api.github.com.yaml \
  -o vendor/github-rest-api-description/api.github.com.yaml
curl -fsSL https://raw.githubusercontent.com/github/rest-api-description/main/LICENSE.md \
  -o vendor/github-rest-api-description/LICENSE.md
```

The spec version is embedded in the file's `info.version` field.
