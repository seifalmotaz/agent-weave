import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:test/test.dart';

void main() {
  test('reservation is atomic across concurrent attempts', () async {
    final store = MemoryRunStore();
    final futures = List.generate(
      10,
      (i) => store
          .begin(ownerId: 'owner', threadId: 'thread', runId: '$i')
          .then((_) => true, onError: (Object error) => false),
    );
    expect((await Future.wait(futures)).where((v) => v).length, 1);
  });
  test('snapshots do not expose mutable storage internals', () async {
    final store = MemoryRunStore();
    await store.begin(ownerId: 'owner', threadId: 'thread', runId: 'run');
    final state = <String, Object?>{
      'nested': {'secret': 1},
    };
    await store.save(
      ownerId: 'owner',
      threadId: 'thread',
      runId: 'run',
      state: state,
      release: true,
    );
    (state['nested'] as Map)['secret'] = 2;
    final loaded = await store.load(ownerId: 'owner', threadId: 'thread');
    expect((loaded!['nested'] as Map)['secret'], 1);
    (loaded['nested'] as Map)['secret'] = 3;
    expect(
      ((await store.load(ownerId: 'owner', threadId: 'thread'))!['nested']
          as Map)['secret'],
      1,
    );
    expect(await store.load(ownerId: 'other', threadId: 'thread'), isNull);
    await expectLater(
      store.save(
        ownerId: 'owner',
        threadId: 'thread',
        runId: 'run',
        state: {},
        release: true,
      ),
      throwsA(isA<RunConflict>()),
    );
  });

  test('parses TanStack text and image message parts', () {
    final request = ChatRequest.fromJson({
      'threadId': 't',
      'runId': 'r',
      'messages': [
        {
          'id': 'm',
          'role': 'user',
          'parts': [
            {'type': 'text', 'content': 'Hello'},
            {
              'type': 'image',
              'source': {'url': 'https://example.com/image.png'},
            },
          ],
        },
      ],
    });
    expect(request.messages.single.text, 'Hello');
    expect(request.messages.single.content.last, isA<ImagePart>());
  });
  for (final value in ['', 'x' * 257]) {
    test('rejects invalid identifier length ${value.length}', () {
      expect(
        () => ChatRequest(threadId: value, runId: 'r'),
        throwsFormatException,
      );
    });
  }
  test('rejects missing fields, duplicate messages and duplicate answers', () {
    expect(() => ChatRequest.fromJson({}), throwsFormatException);
    expect(
      () => ChatRequest(
        threadId: 't',
        runId: 'r',
        messages: [
          ChatMessage.user('a', id: 'm'),
          ChatMessage.user('b', id: 'm'),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => ChatRequest(
        threadId: 't',
        runId: 'r',
        resume: [
          const ResumeAnswer(interruptId: 'i', value: true),
          const ResumeAnswer(interruptId: 'i', value: false),
        ],
      ),
      throwsFormatException,
    );
  });
  test('SSE safely encodes newlines and non-Latin text', () {
    final event = AgentEvent({
      'type': 'TEXT_MESSAGE_CONTENT',
      'delta': 'اهلا\nCairo',
    });
    final encoded = event.toSse();
    expect(encoded.split('\n').length, 3);
    expect(jsonDecode(encoded.substring(6).trim()), event.json);
  });
  test('schema identity is independent of map insertion order', () {
    expect(
      schemaHash({
        'b': 1,
        'a': {'d': 2, 'c': 3},
      }),
      schemaHash({
        'a': {'c': 3, 'd': 2},
        'b': 1,
      }),
    );
    expect(canonicalJson({'n': 1.0}), '{"n":1}');
    expect(schemaHash(null), isNot(schemaHash({})));
  });
  test('all content parts and tool calls survive a storage round trip', () {
    final message = ChatMessage(
      id: 'm',
      role: MessageRole.assistant,
      content: const [
        TextPart('Hi'),
        ImagePart('https://example.com/a'),
        FilePart('file-1'),
      ],
      toolCalls: [
        ToolCall(id: 'c', name: 'lookup', arguments: {'a': 1}),
      ],
    );
    expect(ChatMessage.fromJson(message.toJson()).toJson(), message.toJson());
  });
}
