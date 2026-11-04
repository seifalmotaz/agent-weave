# Typed tools and approvals

Use `Tool<I, O, C>` to declare the decoded input, return value, and trusted
application context. JSON Schema validates inputs before `decode` and validates
encoded results before they enter the conversation.

```dart
final doubleNumber = Tool<int, int, Session>(
  name: 'double',
  description: 'Double an integer',
  inputSchema: const {
    'type': 'object',
    'properties': {'number': {'type': 'integer'}},
    'required': ['number'],
    'additionalProperties': false,
  },
  outputSchema: const {'type': 'integer'},
  decode: (json) => json['number'] as int,
  encode: (result) => result,
  execute: (number, context) => number * 2,
);
```

`context.value` is your application context. `context.ownerId` comes from
authentication. Use both to enforce application permissions. Registering a tool
does not grant a user permission to operate on every database row.

## Approval

Set `needsApproval: true` to pause before a tool executes. The terminal event
contains a TanStack interrupt binding. Configure the matching input and output
schemas in the UI client so it can bind the approval.

The Dart client uses `interrupt.resolveApproval(true)`. The pinned JavaScript
client uses `interrupt.resolveInterrupt(true)`. Both submit AG-UI resume entries
with `interruptId`, `status`, and `payload`.

A new run identifies the interrupted run with `parentRunId`. Every pending
interrupt must receive one answer. AgentWeave validates the entire answer batch
before executing any resumed tool. Invalid answers preserve the previous
pending snapshot so the user can correct them.

Default approvals support approval, rejection, and schema-validated edited
arguments. Custom approval payload schemas and first-party generic interrupts
are not implemented yet.

### Edit tool arguments in a client

Register matching input and output schemas on both sides. After the user edits
the proposed arguments, resolve the typed approval using your client's API.
The Dart and JavaScript method arguments differ.

For the workspace-pinned Dart `ChatClient`:

```dart
final interrupt = chat.getInterrupts().single;
interrupt.resolveInterrupt({
  'approved': true,
  'editedArgs': {'priority': 2},
});
```

For the pinned official JavaScript `ChatClient`:

```javascript
const [interrupt] = chat.getInterrupts();
interrupt.resolveInterrupt(true, {editedArgs: {priority: 2}});
```

These are client calls. Direct Dart backend code instead resumes a
`ChatRequest` using `paused.interrupts.single.approve(editedArgs: ...)`, as shown
in the [Dart API guide](dart-api.md). Do not automatically approve on behalf of
the user or use a client decision as authorization for an unrelated resource.

The tested raw object schema uses a local `$defs`/`$ref` for `priority`. Both
clients bind the approval and complete a valid edit. Invalid edits can reach the
backend with raw JSON schemas; the backend rejects them before effects. Do not
assume that a client accepting the edit proves it matches the schema.
This covers the named raw schema case, not every reference or validator.

## Client tools

Register `ClientTool<C>` on the server to allow an explicitly named client-side
operation. Its result arrives through the same interrupt continuation protocol
and is validated against the configured output schema. Client-advertised tool
names do not automatically become trusted executable server tools.

## External effects

Pass `context.idempotencyKey` as an idempotency key to services that support it.
If a process crashes after an external service commits an effect, inspect that
service before retrying. Database history cannot make an unrelated external
service execute exactly once.


## Resume the original contract

Persisted approvals bind a private exact tool contract, including schemas and
execution kind. Recreated agents must preserve it. Older checkpoints without
this snapshot require a new conversation; their history remains readable.
See [approval contracts](approval-contracts.md) for recovery and custom-store
migration. Public client schema hashes remain a separate wire contract.

## Native text tools and declared fallbacks

Use [OpenAI custom text tools](openai-custom-tools.md) for raw string input and
native text/image/file output. These use `NativeToolCall` and approval-only
responses; their grammar does not replace application validation or authorization.

Provider authors can implement `NativeToolFallback<C>` to declare pure denial,
cancelled-approval and skipped results. Core validates these values against the
output schema and binds them into the private tool profile. Only an explicit
fallback can continue a rejected native call. Unknown execution exceptions and
caller cancellation still close the native continuation; no fallback implies
rollback or permission to repeat an external effect. Existing computer tools
retain their screenshot and closed-continuation requirements.
