# OpenAI integration

`agent_weave_openai` uses `openai_dart 11.0.1` for typed provider transport.
AgentWeave implements orchestration and protocol adaptation around that SDK.

| Capability | Entry point |
| --- | --- |
| Responses chat | `OpenAIResponsesModel` |
| Chat Completions | `OpenAIChatModel` |
| Images | `OpenAIImageModel`, `imageTask`, or `client.images` |
| Speech | `OpenAISpeechModel`, `speechTask`, or `client.audio.speech` |
| Transcription | `OpenAITranscriptionModel`, `transcriptionTask`, or `client.audio.transcriptions` |
| Decisions | `OpenAIDecisionModel` or `client.decisions` |
| Embeddings | `OpenAIEmbeddingModel` or `client.embeddings` |
| Video jobs | `OpenAIVideoModel` or `client.videos` |
| Realtime | `OpenAIRealtimeModel`, `client.realtime`, or `client.realtimeSessions` |
| Supporting resources | Typed provider client resources |
| Additional JSON operations | `OpenAIPlatformApi` |

Use `configure` on chat adapters to set typed provider-specific options. Model
capabilities describe the adapter's request formats; selecting an incompatible
provider model can still produce a provider error.

The provider SDK also exposes conversations, files, uploads, batches, models,
moderation, fine-tuning, evals, containers, vector stores, skills, ChatKit,
webhooks, safety resources, Live sessions, saved agents, and Vaults. These are
delegated APIs, not independently implemented AgentWeave features.

`OpenAIPlatformApi` supports additional JSON requests and binary downloads,
including administration operations with an appropriate credential. It is an
explicit raw escape hatch. It does not imply typed or tested parity for every
OpenAI endpoint. Mutation requests through this helper are not automatically
retried.

The [operation inventory](openai-api-inventory.json) records the official
reference index for update reviews. Each entry is a discovery/review item, not
a passing endpoint test. See [validation](validation.md) for what was exercised.

## Media and realtime

`imageTask`, `speechTask`, and `transcriptionTask` emit normalized TanStack
generation results. Direct model wrappers retain provider-specific types.

Non-streaming image requests cannot abort in-flight through the underlying
SDK. Use its streaming operation when an abortable transport is required.
Cancelling a video wait does not cancel a provider job or its charges.
Close realtime connections explicitly when the session ends.

Use separate prefixed imports for realtime event classes:

```dart
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;
import 'package:agent_weave_openai/realtime.dart' as realtime;
```

The deprecated Assistants API has a separate `assistants.dart` import.
Provider/model deprecations remain OpenAI's schedule. In particular, the Speech
API models are scheduled to shut down on January 6, 2027; new voice integrations
should evaluate the Realtime API. Check the
[official speech guide](https://developers.openai.com/api/docs/guides/text-to-speech)
before choosing a model.
