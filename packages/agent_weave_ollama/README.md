# AgentWeave Ollama

Connect AgentWeave to an existing Ollama HTTP server using native JSON and NDJSON streaming. Normalized chat supports function tools and structured output where the model supports them; embeddings use typed SDK requests and immutable results. No model is downloaded automatically.

See the [Ollama guide](../../docs/ollama.md) and [runnable example](../../examples/ollama_demo.dart) for setup, cancellation, private replay and limitations. Keep optional server credentials on the backend and close the client when finished.
