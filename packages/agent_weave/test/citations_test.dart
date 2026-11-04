import 'package:agent_weave/agent_weave.dart';
import 'package:test/test.dart';
import 'runtime_test.dart' as f;

TextCitation cite(int start, int end) => TextCitation(
  start: start,
  end: end,
  source: UrlCitationSource('https://example.com/a'),
);

class PartialModel implements ChatModel {
  @override
  ModelCapabilities get capabilities => const ModelCapabilities();
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    yield const TextDelta('hello');
    yield CitationReady(cite(0, 5));
    throw StateError('provider failure');
  }
}

class WaitingModel implements ChatModel {
  @override
  ModelCapabilities get capabilities => const ModelCapabilities();
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    yield const TextDelta('hello');
    yield CitationReady(cite(0, 5));
    await cancellation.whenCancelled;
    cancellation.throwIfCancelled();
  }
}

void main() {
  test('typed citations round trip and validate UTF16 boundaries', () {
    final values = [
      cite(1, 3),
      TextCitation(
        start: 0,
        end: 1,
        source: DocumentCitationSource(
          index: 0,
          location: CitationLocation(
            unit: CitationUnit.pages,
            start: 1,
            end: 2,
          ),
        ),
      ),
      TextCitation(
        start: 0,
        end: 1,
        source: SearchResultCitationSource(
          index: 1,
          source: 'origin',
          location: CitationLocation(
            unit: CitationUnit.blocks,
            start: 0,
            end: 2,
          ),
        ),
      ),
    ];
    for (final value in values) {
      expect(TextCitation.fromJson(value.toJson()).toJson(), value.toJson());
    }
    cite(1, 3).validateFor('a😀b');
    expect(() => cite(1, 2).validateFor('a😀b'), throwsFormatException);
    expect(() => cite(2, 3).validateFor('a😀b'), throwsFormatException);
    expect(() => cite(1, 9).validateFor('a😀b'), throwsFormatException);
    expect(
      () => UrlCitationSource('https://user:secret@example.com/'),
      throwsFormatException,
    );
    expect(
      () => CitationLocation(unit: CitationUnit.pages, start: 0, end: 1),
      throwsFormatException,
    );
    expect(
      () => TextCitation.fromJson({'start': 'bad'}),
      throwsFormatException,
    );
    expect(
      () => ChatMessage(
        id: 'u',
        role: MessageRole.user,
        content: [TextPart('x')],
        citations: [values[1]],
      ),
      throwsFormatException,
    );
    final old = ChatMessage.user('hello', id: 'u').toJson();
    expect(ChatMessage.fromJson(old).toJson(), old);
  });
  test(
    'events, persistence, hydration and continuation preserve citations',
    () async {
      final model = f.FakeModel([
        [
          const TextDelta('hello'),
          CitationReady(cite(0, 5)),
          const ModelFinished.continuation(),
        ],
        [const TextDelta('done'), const ModelFinished()],
      ]);
      final store = MemoryRunStore();
      final events = await f.run(AiAgent<String>(model: model, store: store));
      final event = events.singleWhere(
        (e) => e.type == 'CUSTOM' && e.json['name'] == 'agent_weave:citation',
      );
      expect((event.json['value'] as Map)['citation'], cite(0, 5).toJson());
      expect((event.json['value'] as Map)['citationIndex'], 0);
      expect(events.any((e) => e.type == 'MESSAGES_SNAPSHOT'), true);
      final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
      final messages = (state['messages'] as List)
          .map((m) => ChatMessage.fromJson(Map<String, Object?>.from(m as Map)))
          .toList();
      expect(
        messages
            .firstWhere((m) => m.role == MessageRole.assistant)
            .citations
            .single
            .toJson(),
        cite(0, 5).toJson(),
      );
      expect(
        model.requests.last.messages
            .firstWhere((m) => m.role == MessageRole.assistant)
            .citations,
        hasLength(1),
      );
      final hydrated =
          (chatHydration(state)['messages'] as List).firstWhere(
                (m) => m['role'] == 'assistant',
              )
              as Map;
      expect(hydrated['metadata']['agent_weave']['citations'], [
        cite(0, 5).toJson(),
      ]);
    },
  );
  test('failure preserves valid partial citation', () async {
    final store = MemoryRunStore();
    final events = await f.run(
      AiAgent<String>(model: PartialModel(), store: store),
    );
    expect(events.last.type, 'RUN_ERROR');
    final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
    final message = ChatMessage.fromJson(
      Map<String, Object?>.from((state['messages'] as List).last as Map),
    );
    expect(message.text, 'hello');
    expect(message.citations.single.toJson(), cite(0, 5).toJson());
  });
  test('invalid model citation emits no public citation', () async {
    final model = f.FakeModel([
      [const TextDelta('x'), CitationReady(cite(0, 2)), const ModelFinished()],
    ]);
    final store = MemoryRunStore();
    final events = await f.run(AiAgent<String>(model: model, store: store));
    expect(events.last.type, 'RUN_ERROR');
    expect(
      events.where(
        (e) => e.type == 'CUSTOM' && e.json['name'] == 'agent_weave:citation',
      ),
      isEmpty,
    );
    final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
    final message = ChatMessage.fromJson(
      Map<String, Object?>.from((state['messages'] as List).last as Map),
    );
    expect(message.citations, isEmpty);
  });
  test('cancellation retains valid partial citations', () async {
    final store = MemoryRunStore();
    final token = CancellationToken();
    final agent = AiAgent<String>(model: WaitingModel(), store: store);
    await for (final event in agent.run(
      f.request(),
      ownerId: 'owner',
      context: 'x',
      cancellation: token,
    )) {
      if (event.type == 'CUSTOM' &&
          event.json['name'] == 'agent_weave:citation') {
        token.cancel();
      }
    }
    final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
    final message = ChatMessage.fromJson(
      Map<String, Object?>.from((state['messages'] as List).last as Map),
    );
    expect(message.text, 'hello');
    expect(message.citations.single.toJson(), cite(0, 5).toJson());
  });
  test('message snapshots citations and malformed JSON is rejected', () {
    final citations = [cite(0, 1)];
    final message = ChatMessage(
      id: 'a',
      role: MessageRole.assistant,
      content: [TextPart('x')],
      citations: citations,
    );
    citations.clear();
    expect(message.citations, hasLength(1));
    expect(() => message.citations.clear(), throwsUnsupportedError);
    final json = message.toJson();
    json['citations'] = 'bad';
    expect(() => ChatMessage.fromJson(json), throwsFormatException);
  });
  test('approval resume retains cited assistant message', () async {
    final model = f.FakeModel([
      [
        const TextDelta('hello'),
        CitationReady(cite(0, 5)),
        f.call(),
        const ModelFinished(),
      ],
      [const TextDelta('done'), const ModelFinished()],
    ]);
    final store = MemoryRunStore();
    final agent = AiAgent<String>(
      model: model,
      store: store,
      tools: [f.tool(approval: true)],
    );
    final paused = await agent.generate(
      f.request(),
      ownerId: 'owner',
      context: 'x',
    );
    expect(paused.status, RunStatus.interrupted);
    final resumed = await agent.generate(
      f.request(
        run: 'next',
        parent: 'run',
        text: null,
        resume: [paused.interrupts.single.approve()],
      ),
      ownerId: 'owner',
      context: 'x',
    );
    expect(resumed.status, RunStatus.completed);
    final assistant = model.requests.last.messages.firstWhere(
      (m) => m.role == MessageRole.assistant && m.text == 'hello',
    );
    expect(assistant.citations.single.toJson(), cite(0, 5).toJson());
  });
  test(
    'citation ending on dangling high surrogate is rejected before publication',
    () async {
      final model = f.FakeModel([
        [
          TextDelta(String.fromCharCode(0xD83D)),
          CitationReady(cite(0, 1)),
          TextDelta(String.fromCharCode(0xDE00)),
          const ModelFinished(),
        ],
      ]);
      final store = MemoryRunStore();
      final events = await f.run(AiAgent<String>(model: model, store: store));
      expect(events.last.type, 'RUN_ERROR');
      expect(
        events.where(
          (e) => e.type == 'CUSTOM' && e.json['name'] == 'agent_weave:citation',
        ),
        isEmpty,
      );
      final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
      final message = ChatMessage.fromJson(
        Map<String, Object?>.from((state['messages'] as List).last as Map),
      );
      expect(message.citations, isEmpty);
    },
  );
}
