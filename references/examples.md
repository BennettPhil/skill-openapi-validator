# openapi-validator Usage Examples

## Basic Validation

Validate a JSON OpenAPI spec file:

```bash
./scripts/run.sh my-api.json
```

Example output:
```
[WARNING] info.description: Missing 'info.description'
[WARNING] paths./users.get: Operation is missing both 'summary' and 'description'

Summary: 0 error(s), 2 warning(s)
```

## JSON Output

Get structured JSON output for programmatic use:

```bash
./scripts/run.sh my-api.json --format=json
```

Example output:
```json
{
  "findings": [
    {
      "severity": "warning",
      "path": "info.description",
      "message": "Missing 'info.description'"
    }
  ],
  "summary": {
    "errors": 0,
    "warnings": 1
  }
}
```

## Strict Mode

Treat all warnings as errors (useful for CI/CD pipelines):

```bash
./scripts/run.sh my-api.json --strict
```

In strict mode, any warning becomes an error and the tool exits with code 1.

## Combining Options

```bash
./scripts/run.sh my-api.json --format=json --strict
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0    | No errors (warnings may be present unless `--strict`) |
| 1    | Validation errors found |
| 2    | File error (not found, invalid JSON) |

## What Gets Checked

### Errors
- Missing `openapi` version field
- Missing `info.title`
- Missing `paths` object
- Invalid HTTP methods in path items

### Warnings
- Missing `info.description`
- Operations without `summary` or `description`
- Response objects missing `description`
- Inconsistent path naming (mixing camelCase and snake_case)
- Schema definitions in `components.schemas` that are never referenced via `$ref`

## Supported Formats

Only JSON format specs are supported. YAML specs must be converted to JSON first:

```bash
# Example: convert YAML to JSON with Python
python3 -c "import yaml,json,sys; json.dump(yaml.safe_load(open(sys.argv[1])),sys.stdout,indent=2)" spec.yaml > spec.json
./scripts/run.sh spec.json
```
