# Injection and interpretation boundaries

Assess whether attacker-controlled data becomes syntax or executable behavior. Establish the interpreter and existing constraints before calling a pattern exploitable.

## SQL and commands

- Parameterize SQL values with the driver's placeholder syntax. Parameters do not stand for identifiers or keywords: map requested columns, directions, and table choices to fixed allowed SQL fragments. For dynamic IN lists, generate placeholders and pass values separately, or use the driver's array support. Handle empty lists explicitly.
- Formatting a successfully parsed integer with `%d` does not let it inject SQL syntax. Parameterization may improve consistency, but label that as hardening rather than a demonstrated injection vulnerability. Neither `database/sql` nor switching to a different driver automatically makes string-built queries safe.
- Separate the executable and arguments with `exec.Command` or `exec.CommandContext`. Separate arguments prevent shell interpretation but not option injection or dangerous tool-specific syntax. Constrain executables, operands, working directories, and privileges; use `--` where the tool supports it.
- Executing an intentionally supplied script is code execution by design. Argument separation and a timeout do not sandbox it. Establish authorization, isolation, filesystem/network access, and resource limits appropriate to that capability.

## Templates and output

- Render HTML using `html/template` with trusted template source. Untrusted values passed to `Execute` are normal data; parsing untrusted template source or converting input to trusted `template.HTML`, `JS`, or `URL` bypasses that protection.
- `text/template` does not provide contextual HTML escaping. Encoding for one context does not secure another, such as JavaScript, CSS, a URL, SQL, or a shell.
- For XPath or other query languages, use binding APIs where available or fixed query structure with appropriately constrained values. A general input regex is not a substitute for context-specific handling.

## Decoding

Bound request bytes before decoding and bound decoded sizes and processing costs. Concrete structs simplify validation but do not themselves stop resource exhaustion. Reject trailing documents or unknown fields where the endpoint contract requires it.

Go's `encoding/xml` does not fetch and expand external entities by default. Do not report XXE solely because `xml.NewDecoder` is used. Inspect custom entity handling, external parsers, and surrounding fetch behavior; distinguish those from document size or nesting attacks.

`encoding/gob` is not designed for hostile input with configurable resource limits. Prefer a format and decoder suited to the trust boundary, and assess allocation amplification even when the encoded body is bounded. JSON decoding does not execute arbitrary constructors, but still requires input and work limits.
