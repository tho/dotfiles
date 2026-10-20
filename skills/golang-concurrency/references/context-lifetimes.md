# Context lifetimes

Carry the caller's lifetime through derived contexts. Cancellation is a signal, not preemption; blocking operations and CPU loops must observe it. A child cannot extend its parent's deadline. Nested timeouts provide at most the parent's remaining budget, so a fixed overall deadline cannot promise each sequential operation its full independent timeout.

## Cancel ownership

Call the cancellation function from WithCancel, WithTimeout, or WithDeadline on every owned exit, or explicitly transfer that responsibility. A timeout firing does not eliminate the value of promptly releasing cancellation resources.

Use ctx.Err() for cancellation/deadline status and preserve inspectable errors when wrapping them. WithCancelCause and context.Cause (Go 1.20), and timeout/deadline cause constructors (Go 1.21), can carry a more specific reason. An operation failure need not equal ctx.Err(); preserve the useful underlying failure according to the API contract.

## AfterFunc

context.AfterFunc (Go 1.21) runs its callback in a separate goroutine after cancellation. Its stop function prevents a callback only if it has not started; stop does not wait for a running callback. Registration alone does not clean up a resource when the context never cancels.

Cleanup has two separate obligations: release exactly once, and release only after the last unsafe use has ended. sync.Once or OnceFunc can satisfy the first while leaving a release-versus-use race. Make both obligations visible in the implementation; a caveat after code that releases an in-use resource does not make that code safe.

When release cannot overlap use, give the resource a completion signal covering all users. Cancellation requests those users to stop; the release path waits for their completion before releasing. If AfterFunc performs release, its callback and the normal cleanup path can share a OnceFunc that waits for that signal and then releases. The owner must signal completion before calling or waiting for cleanup, or it can deadlock with a callback already waiting inside OnceFunc. Join a started callback before returning if cleanup completion is promised. Normal completion still releases even if cancellation never happens.

If a resource explicitly supports concurrent Close to interrupt a blocked operation, use that documented contract instead, then join the interrupted users. Do not infer this property from an arbitrary release function. A user that cannot stop can prevent safe cleanup from finishing; cancellation does not justify releasing its resource underneath it.

## Detached work

context.WithoutCancel (Go 1.21) preserves values while removing cancellation and deadline; its Done channel is nil. Derive a new bounded timeout if work must outlive the request. Assign service-level ownership for shutdown and error reporting, and account for retained context values or request-owned objects that may no longer be safe to use.

WithoutCancel cannot guarantee delivery after a process crash, deployment, or forced shutdown. If the contract requires durable completion, use a durable queue or transactional outbox with retries and idempotency as appropriate.
