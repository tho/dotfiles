# Application and API documentation

## Commands and configuration

Compare help text and instructions with command definitions and practical `--help` output. Verify subcommands, flags, defaults, required arguments, exit behavior, and examples. Inspect startup behavior before executing a command; help paths can still initialize services in some applications.

Read the configuration loader to establish actual precedence between flags, environment, files, and defaults rather than assuming the conventional order. Document names, value formats and units, locations, required settings, default values, validation, and reload behavior only where supported. Use obvious placeholders for credentials and avoid real secrets in snippets or output.

Verify documented build and installation paths against the current command package and supported release artifacts.

## Service contracts

Follow the project's existing authoritative schema (OpenAPI, protobuf, AsyncAPI) or generation pipeline. Check routes, methods, request/response fields, status codes, errors, authentication, and versioning against implementation and contract tests. Flag disagreement rather than silently treating generated docs as proof of implementation behavior.

Inspect generator configuration and pinned versions before documenting generation commands or output formats. Do not assume a Swagger generator emits OpenAPI 3, or that newer Go tool-management commands work on the supported Go floor. Regenerate through the existing pipeline when practical and inspect the diff; editing generated output alone leaves the next generation stale.

Check code snippets and example payloads against current types and validation rules. Run existing schema validation, linting, or documentation build commands where available.
