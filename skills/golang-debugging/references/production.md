# Production evidence and mitigation

Use existing logs, traces, errors, and deployment/configuration history to delimit the affected requests and time window. Tie evidence to a revision, instance, timestamp and operation. A correlation with deployment is a lead; establish the changed condition before declaring the cause.

When the user mentions evidence but has not supplied its values, ask for the exact error and relevant request context. Offer a conditional experiment without inventing their contents: for example, if the error identifies an upstream timeout, correlate that request with the upstream trace. An upstream failure supports the dependency hypothesis; a successful upstream response shifts attention to local handling or deadline propagation. Choose a branch justified by the supplied symptom and label it as illustrative until the error is available.

## Bounded capture

Volatile evidence disappears on restart. Select the smallest useful capture for the hypothesis: error stacks for a panic, repeated goroutine stacks for a hang, or sanitized request metadata for a boundary failure. Capturing every profile is not a prerequisite to mitigation.

Use an existing protected diagnostic endpoint only after verifying its address and access controls. When the service actually exposes `/debug/pprof/goroutine`, `?debug=1` merges identical stacks with counts and `?debug=2` shows each goroutine's wait state and duration. Quote URLs in shell commands and apply connection and total timeouts appropriate to the capture. Do not assume a port, create a public debug server, or expose the default HTTP mux to obtain evidence.

Runtime diagnostics can reveal sensitive state and impose overhead. Preserve artifacts in the project's approved location with restricted access. Redact secrets and personal payloads; prefer IDs, lengths, error classes, and bounded excerpts over complete headers, bodies, or environment dumps. Debugger attachment and process signals can stop or terminate a service; do not present them as harmless stack-capture mechanisms.

## Interpret only what the evidence establishes

Distinguish the failing component from the place that reports its error. Follow the request across boundaries using existing correlation identifiers, compare successful and failing requests, and test the relevant dependency or configuration hypothesis. Do not assume a timeout is a deadlock or that a blocked stack proves a goroutine leak.

## Incident handoff

Report the mitigation and its observed effect, the evidence preserved, the confirmed cause or remaining hypotheses, and the next discriminating experiment.
