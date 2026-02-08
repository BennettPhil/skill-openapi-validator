---
name: openapi-validator
description: >
  An OpenAPI schema validator that checks API specification files for completeness
  and consistency. Reports missing descriptions, inconsistent naming conventions,
  and unused schema definitions. Supports OpenAPI 3.0 and 3.1 in JSON format.
version: 0.1.0
license: Apache-2.0
---

# openapi-validator

Validates OpenAPI specification files (JSON format) for completeness and consistency.

## Features

- Supports OpenAPI 3.0 and 3.1 specifications
- Detects errors: missing required fields, invalid HTTP methods
- Detects warnings: missing descriptions, inconsistent naming, unused schemas
- Structured output in text or JSON format
- Strict mode to treat warnings as errors

## Usage

```bash
# Basic validation
./scripts/run.sh path/to/openapi.json

# JSON output
./scripts/run.sh path/to/openapi.json --format=json

# Strict mode (warnings become errors)
./scripts/run.sh path/to/openapi.json --strict
```

## Exit Codes

- `0` - No errors found (warnings may be present)
- `1` - Errors found (or warnings in strict mode)
- `2` - File error (not found, invalid JSON)
