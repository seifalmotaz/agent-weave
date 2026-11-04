import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';
import 'package:test/test.dart';

void main() {
  test('document bytes snapshot caller-owned buffers', () {
    final bytes = [65, 66, 67];
    final part =
        DocumentPart.bytes(bytes, mimeType: 'APPLICATION/PDF')
            as Base64DocumentPart;
    bytes[0] = 0;
    expect(part.data, 'QUJD');
    expect(part.mimeType, 'application/pdf');
  });

  final parts = <DocumentPart>[
    DocumentPart.url(
      'https://example.com/report.pdf?signature=fixture',
      filename: 'report.pdf',
    ),
    DocumentPart.base64(
      base64Encode(utf8.encode('PDF fixture')),
      mimeType: 'application/pdf',
      filename: 'report.pdf',
    ),
    DocumentPart.fileId('file-1', provider: 'openai', filename: 'report.pdf'),
  ];
  for (final part in parts) {
    test(
      '${part.runtimeType} survives storage and authorized history hydration',
      () {
        final message = ChatMessage(
          id: 'm',
          role: MessageRole.user,
          content: [part],
        );
        final encoded = message.toJson();
        final decoded = ChatMessage.fromJson(encoded);
        expect(decoded.toJson(), encoded);
        final history = chatHydration({
          'messages': [encoded],
          'status': 'completed',
        });
        final request = ChatRequest.fromJson({
          'threadId': 't',
          'runId': 'r',
          'messages': history['messages'],
        });
        expect(request.messages.single.toJson(), encoded);
      },
    );
  }
  for (final source in [
    'file:///tmp/report.pdf',
    'https://user:password@example.com/a',
    'relative.pdf',
    'javascript:alert(1)',
  ]) {
    test('rejects document URL $source', () {
      expect(() => DocumentPart.url(source), throwsArgumentError);
    });
  }
  test('invalid base64, MIME and empty handles fail at construction', () {
    expect(
      () => DocumentPart.base64('not base64!', mimeType: 'application/pdf'),
      throwsArgumentError,
    );
    expect(
      () => DocumentPart.base64('', mimeType: 'application/pdf'),
      throwsArgumentError,
    );
    expect(
      () => DocumentPart.base64('QQ==', mimeType: 'not-a-mime'),
      throwsArgumentError,
    );
    expect(
      () => DocumentPart.fileId('', provider: 'openai'),
      throwsArgumentError,
    );
    expect(
      () => DocumentPart.fileId('file', provider: ''),
      throwsArgumentError,
    );
    expect(
      () => DocumentPart.url('https://example.com/a', filename: '\n'),
      throwsArgumentError,
    );
  });
  test('wire input validates source variants and protects filename fields', () {
    expect(
      () => ContentPart.fromJson({
        'type': 'document',
        'source': {'type': 'file', 'fileId': 'x'},
      }),
      throwsFormatException,
    );
    expect(
      () => ContentPart.fromJson({
        'type': 'document',
        'source': {
          'type': 'data',
          'data': 'invalid',
          'mimeType': 'application/pdf',
        },
      }),
      throwsFormatException,
    );
    expect(
      () => ContentPart.fromJson({
        'type': 'document',
        'source': {'type': 'unknown'},
      }),
      throwsFormatException,
    );
  });
  test('legacy file handles remain unchanged', () {
    final request = ChatRequest.fromJson({
      'threadId': 't',
      'runId': 'r',
      'messages': [
        {
          'id': 'u',
          'role': 'user',
          'parts': [
            {
              'type': 'document',
              'source': {'type': 'file', 'fileId': 'old-id'},
            },
          ],
        },
      ],
    });
    expect(request.messages.single.content.single, isA<FilePart>());
  });
  test('legacy document sources decode and emit canonical source values', () {
    for (final source in <JsonObject>[
      {'type': 'url', 'url': 'https://example.com/a.pdf'},
      {'type': 'data', 'data': 'UERG', 'mimeType': 'application/pdf'},
      {'type': 'file', 'fileId': 'file-1', 'provider': 'openai'},
    ]) {
      final part = DocumentPart.fromJson({
        'type': 'document',
        'source': source,
      });
      expect(part.sourceJson, {
        'type': source['type'],
        if (source.containsKey('mimeType')) 'mimeType': source['mimeType'],
        if (source.containsKey('provider')) 'provider': source['provider'],
        'value': switch (source['type']) {
          'url' => 'https://example.com/a.pdf',
          'data' => 'UERG',
          _ => 'file-1',
        },
      });
    }
  });
  test('unsupported document capability prevents model submission', () async {
    final model = ScriptedChatModel(steps: []);
    final agent = AiAgent<void>(model: model);
    await expectLater(
      agent.generate(
        ChatRequest(
          threadId: 't',
          runId: 'r',
          messages: [
            ChatMessage(
              id: 'u',
              role: MessageRole.user,
              content: [parts.first],
            ),
          ],
        ),
        ownerId: 'o',
        context: null,
      ),
      throwsA(
        isA<AgentRunException>().having((e) => e.code, 'code', 'INVALID_INPUT'),
      ),
    );
    expect(model.requests, isEmpty);
  });
  for (final state in <JsonObject>[
    {
      'messages': [
        {'type': 'future-unknown-content'},
      ],
    },
    {'messages': [], 'generation': 'invalid'},
  ]) {
    test(
      'unreadable snapshot releases ownership without erasing data $state',
      () async {
        final store = MemoryRunStore();
        await store.begin(ownerId: 'o', threadId: 't', runId: 'old');
        await store.save(
          ownerId: 'o',
          threadId: 't',
          runId: 'old',
          state: state,
          release: true,
        );
        final agent = AiAgent<void>(
          model: ScriptedChatModel(steps: []),
          store: store,
        );
        await expectLater(
          agent
              .run(
                ChatRequest(threadId: 't', runId: 'new'),
                ownerId: 'o',
                context: null,
              )
              .toList(),
          throwsFormatException,
        );
        expect(await store.load(ownerId: 'o', threadId: 't'), state);
        await store.begin(ownerId: 'o', threadId: 't', runId: 'retry');
      },
    );
  }
}
