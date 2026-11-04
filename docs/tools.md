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
