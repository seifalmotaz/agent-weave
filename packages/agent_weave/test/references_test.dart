import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:test/test.dart';
import 'runtime_test.dart' as f;

OutputReference reference(
  ReferencePosition position, {
  int start = 0,
  int end = 1,
}) => OutputReference(
  provider: 'openai',
  source: FileCitationSource(
    provider: 'openai',
    fileId: 'file-1',
    filename: 'report',
  ),
  partStart: start,
  partEnd: end,
  position: position,
);

class Partial implements ChatModel {
  final bool cancel;
  Partial(this.cancel);
  @override
  ModelCapabilities get capabilities => const ModelCapabilities();
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    yield const TextDelta('x');
    yield ReferenceReady(reference(FileListPosition(4)));
    if (cancel) {
      await cancellation.whenCancelled;
      cancellation.throwIfCancelled();
    }
    throw StateError('failed');
  }
}

class EmptyFailure implements ChatModel {
  @override
  ModelCapabilities get capabilities => const ModelCapabilities();
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    yield ReferenceReady(reference(FileListPosition(0), end: 0));
    throw StateError('failed');
  }
}

void main() {
  test(
    'typed positions are opaque and references validate text separately',
    () {
      final positions = [
        ProviderTextRange(start: 0, end: 0),
        ProviderTextRange(start: 900, end: 999),
        ProviderTextPosition(999),
        FileListPosition(999),
      ];
      for (final position in positions) {
        final value = reference(position, end: 0);
        value.validateFor('');
        expect(
          OutputReference.fromJson(value.toJson()).toJson(),
          value.toJson(),
        );
      }
      expect(
        () => reference(ProviderTextPosition(0), end: 2).validateFor('😀'),
        returnsNormally,
      );
      expect(
        () => reference(ProviderTextPosition(0), end: 1).validateFor('😀'),
        throwsFormatException,
      );
      expect(
        () => reference(
          ProviderTextPosition(0),
          end: 1,
        ).validateFor(String.fromCharCode(0xD83D)),
        throwsFormatException,
      );
      expect(
        () => OutputReference(
          provider: 'other',
          source: FileCitationSource(provider: 'openai', fileId: 'file'),
          partStart: 0,
          partEnd: 0,
          position: FileListPosition(0),
        ),
        throwsFormatException,
      );
      expect(
        () => FileCitationSource(provider: 'openai', fileId: ''),
        throwsFormatException,
      );
      expect(
        () => OutputReference.fromJson({'provider': 42}),
        throwsFormatException,
      );
      expect(
        () => ReferencePosition.fromJson({'type': 'file_list', 'index': -1}),
        throwsFormatException,
      );
      expect(
        FileCitationSource(
          provider: 'openai',
          fileId: 'f',
          filename: 'report',
        ).title,
        'report',
      );
    },
  );
  test(
    'references persist through approval and hydrate alongside citations',
    () async {
      final ref = reference(ProviderTextRange(start: 0, end: 0));
      final citation = TextCitation(
        start: 0,
        end: 1,
        source: UrlCitationSource('https://example.com'),
      );
      final model = f.FakeModel([
        [
          const TextDelta('x'),
          ReferenceReady(ref),
          CitationReady(citation),
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
      final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
      final events = await store.events(
        ownerId: 'owner',
        threadId: 'thread',
        runId: 'run',
      );
      final custom = events.singleWhere(
        (e) => e['type'] == 'CUSTOM' && e['name'] == 'agent_weave:reference',
      );
      expect((custom['value'] as Map)['referenceIndex'], 0);
      expect((custom['value'] as Map)['reference'], ref.toJson());
      expect(events.any((e) => e['type'] == 'MESSAGES_SNAPSHOT'), true);
      final hydrated =
          (chatHydration(state)['messages'] as List).firstWhere(
                (m) => m['role'] == 'assistant',
              )
              as Map;
      expect(hydrated['metadata']['agent_weave']['references'], [ref.toJson()]);
      expect(hydrated['metadata']['agent_weave']['citations'], [
        citation.toJson(),
      ]);
      expect(jsonEncode(hydrated), isNot(contains('providerData')));
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
      expect(
        model.requests.last.messages
            .firstWhere((m) => m.role == MessageRole.assistant && m.text == 'x')
            .references
            .single
            .toJson(),
        ref.toJson(),
      );
    },
  );
  for (final cancel in [false, true]) {
    test(
      'partial failure or cancellation retains reference: $cancel',
      () async {
        final store = MemoryRunStore();
        final token = CancellationToken();
        final agent = AiAgent<String>(model: Partial(cancel), store: store);
        await for (final e in agent.run(
          f.request(),
          ownerId: 'owner',
          context: 'x',
          cancellation: token,
        )) {
          if (cancel &&
              e.type == 'CUSTOM' &&
              e.json['name'] == 'agent_weave:reference') {
            token.cancel();
          }
        }
        final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
        final message = ChatMessage.fromJson(
          Map<String, Object?>.from((state['messages'] as List).last as Map),
        );
        expect(
          message.references.single.toJson(),
          reference(FileListPosition(4)).toJson(),
        );
      },
    );
  }
  test('immutable message and malformed reference JSON', () {
    final refs = [reference(FileListPosition(0))];
    final message = ChatMessage(
      id: 'a',
      role: MessageRole.assistant,
      content: [TextPart('x')],
      references: refs,
    );
    refs.clear();
    expect(message.references, hasLength(1));
    expect(() => message.references.clear(), throwsUnsupportedError);
    final json = message.toJson();
    expect(
      ChatMessage.fromJson(json).references.single.toJson(),
      message.references.single.toJson(),
    );
    json['references'] = 'bad';
    expect(() => ChatMessage.fromJson(json), throwsFormatException);
    expect(
      () => ChatMessage(
        id: 'u',
        role: MessageRole.user,
        content: [TextPart('x')],
        references: message.references,
      ),
      throwsFormatException,
    );
  });
  test('invalid reference fails before any public annotation', () async {
    final model = f.FakeModel([
      [
        const TextDelta('x'),
        ReferenceReady(reference(FileListPosition(0), end: 2)),
        const ModelFinished(),
      ],
    ]);
    final store = MemoryRunStore();
    final events = await f.run(AiAgent<String>(model: model, store: store));
    expect(events.last.type, 'RUN_ERROR');
    expect(
      events.where(
        (e) => e.type == 'CUSTOM' && e.json['name'] == 'agent_weave:reference',
      ),
      isEmpty,
    );
  });
  test('empty segment reference survives partial provider failure', () async {
    final store = MemoryRunStore();
    final events = await f.run(
      AiAgent<String>(model: EmptyFailure(), store: store),
    );
    expect(events.last.type, 'RUN_ERROR');
    final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
    final message = ChatMessage.fromJson(
      Map<String, Object?>.from((state['messages'] as List).last as Map),
    );
    expect(message.text, isEmpty);
    expect(message.references.single.partEnd, 0);
  });
}
