#!/usr/bin/env python3
"""OpenAPI specification validator for JSON format specs (3.0 and 3.1)."""

import json
import re
import sys


class Finding:
    """A single validation finding (error or warning)."""

    def __init__(self, severity, path, message):
        self.severity = severity  # "error" or "warning"
        self.path = path
        self.message = message

    def to_dict(self):
        return {
            "severity": self.severity,
            "path": self.path,
            "message": self.message,
        }

    def to_text(self):
        tag = "ERROR" if self.severity == "error" else "WARNING"
        return f"[{tag}] {self.path}: {self.message}"


VALID_HTTP_METHODS = {"get", "put", "post", "delete", "options", "head", "patch", "trace"}


def is_camel_case(segment):
    """Check if a path segment uses camelCase."""
    if not segment or segment.startswith("{"):
        return False
    return bool(re.search(r'[a-z][A-Z]', segment))


def is_snake_case(segment):
    """Check if a path segment uses snake_case."""
    if not segment or segment.startswith("{"):
        return False
    return "_" in segment


def collect_schema_refs(obj, refs=None):
    """Recursively collect all $ref targets from the spec."""
    if refs is None:
        refs = set()
    if isinstance(obj, dict):
        if "$ref" in obj:
            refs.add(obj["$ref"])
        for v in obj.values():
            collect_schema_refs(v, refs)
    elif isinstance(obj, list):
        for item in obj:
            collect_schema_refs(item, refs)
    return refs


def validate_spec(spec):
    """Validate an OpenAPI spec dict and return a list of Findings."""
    findings = []

    # --- ERRORS ---

    # Missing openapi version field
    if "openapi" not in spec:
        findings.append(Finding("error", "openapi", "Missing required 'openapi' version field"))
    else:
        version = str(spec["openapi"])
        if not (version.startswith("3.0") or version.startswith("3.1")):
            findings.append(Finding("error", "openapi", f"Unsupported OpenAPI version: {version} (expected 3.0.x or 3.1.x)"))

    # Missing info.title
    info = spec.get("info")
    if not isinstance(info, dict):
        findings.append(Finding("error", "info", "Missing required 'info' object"))
    else:
        if "title" not in info or not info["title"]:
            findings.append(Finding("error", "info.title", "Missing required 'info.title' field"))

    # Missing paths
    if "paths" not in spec:
        findings.append(Finding("error", "paths", "Missing required 'paths' object"))

    # Invalid HTTP methods in paths
    paths = spec.get("paths", {})
    if isinstance(paths, dict):
        for path_key, path_item in paths.items():
            if not isinstance(path_item, dict):
                continue
            for method_key in path_item:
                # Skip non-method keys like parameters, summary, description, servers
                if method_key in ("parameters", "summary", "description", "servers", "$ref"):
                    continue
                if method_key.lower() not in VALID_HTTP_METHODS:
                    findings.append(Finding(
                        "error",
                        f"paths.{path_key}.{method_key}",
                        f"Invalid HTTP method: '{method_key}'"
                    ))

    # --- WARNINGS ---

    # Missing info.description
    if isinstance(info, dict) and ("description" not in info or not info.get("description")):
        findings.append(Finding("warning", "info.description", "Missing 'info.description'"))

    # Check operations for missing summary/description and response descriptions
    if isinstance(paths, dict):
        for path_key, path_item in paths.items():
            if not isinstance(path_item, dict):
                continue
            for method_key, operation in path_item.items():
                if method_key.lower() not in VALID_HTTP_METHODS:
                    continue
                if not isinstance(operation, dict):
                    continue
                op_path = f"paths.{path_key}.{method_key}"

                # Missing operation summary or description
                has_summary = operation.get("summary")
                has_description = operation.get("description")
                if not has_summary and not has_description:
                    findings.append(Finding(
                        "warning",
                        op_path,
                        "Operation is missing both 'summary' and 'description'"
                    ))

                # Missing response descriptions
                responses = operation.get("responses", {})
                if isinstance(responses, dict):
                    for status_code, response_obj in responses.items():
                        if isinstance(response_obj, dict) and not response_obj.get("description"):
                            findings.append(Finding(
                                "warning",
                                f"{op_path}.responses.{status_code}",
                                "Response is missing 'description'"
                            ))

    # Inconsistent path naming (mixing camelCase and snake_case)
    if isinstance(paths, dict):
        camel_paths = []
        snake_paths = []
        for path_key in paths:
            segments = [s for s in path_key.split("/") if s and not s.startswith("{")]
            for seg in segments:
                if is_camel_case(seg):
                    camel_paths.append(path_key)
                    break
                if is_snake_case(seg):
                    snake_paths.append(path_key)
                    break
        if camel_paths and snake_paths:
            findings.append(Finding(
                "warning",
                "paths",
                "Inconsistent path naming: mix of camelCase and snake_case detected"
            ))

    # Unused schema definitions
    components = spec.get("components", {})
    if isinstance(components, dict):
        schemas = components.get("schemas", {})
        if isinstance(schemas, dict) and schemas:
            all_refs = collect_schema_refs(spec)
            for schema_name in schemas:
                ref_string = f"#/components/schemas/{schema_name}"
                if ref_string not in all_refs:
                    findings.append(Finding(
                        "warning",
                        f"components.schemas.{schema_name}",
                        f"Schema '{schema_name}' is defined but never referenced"
                    ))

    return findings


def main():
    args = sys.argv[1:]
    filepath = None
    output_format = "text"
    strict = False

    for arg in args:
        if arg == "--strict":
            strict = True
        elif arg.startswith("--format="):
            output_format = arg.split("=", 1)[1]
        elif not arg.startswith("-"):
            filepath = arg

    if not filepath:
        print("Usage: validate.py <openapi-spec.json> [--format=text|json] [--strict]", file=sys.stderr)
        sys.exit(2)

    # Read and parse the file
    try:
        with open(filepath, "r") as f:
            raw = f.read()
    except FileNotFoundError:
        print(f"Error: File not found: {filepath}", file=sys.stderr)
        sys.exit(2)
    except OSError as e:
        print(f"Error: Cannot read file: {e}", file=sys.stderr)
        sys.exit(2)

    try:
        spec = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON: {e}", file=sys.stderr)
        sys.exit(2)

    if not isinstance(spec, dict):
        print("Error: OpenAPI spec must be a JSON object", file=sys.stderr)
        sys.exit(2)

    # Validate
    findings = validate_spec(spec)

    # In strict mode, promote warnings to errors
    if strict:
        for f_item in findings:
            if f_item.severity == "warning":
                f_item.severity = "error"

    errors = [f_item for f_item in findings if f_item.severity == "error"]
    warnings = [f_item for f_item in findings if f_item.severity == "warning"]

    # Output
    if output_format == "json":
        result = {
            "findings": [f_item.to_dict() for f_item in findings],
            "summary": {
                "errors": len(errors),
                "warnings": len(warnings),
            }
        }
        print(json.dumps(result, indent=2))
    else:
        if not findings:
            print("No issues found.")
        else:
            for f_item in findings:
                print(f_item.to_text())
            print(f"\nSummary: {len(errors)} error(s), {len(warnings)} warning(s)")

    # Exit code
    if errors:
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
