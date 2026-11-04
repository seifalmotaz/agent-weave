import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as api;
import 'package:test/test.dart';
import 'chat_test.dart' as f;

final variants = <Map<String, Object?>>[
  {
    'type': 'char_location',
    'cited_text': 'quote',
    'document_index': 0,
    'document_title': 'D',
    'start_char_index': 2,
    'end_char_index': 5,
    'file_id': 'private',
  },
  {
    'type': 'page_location',
    'cited_text': 'quote',
    'document_index': 1,
    'document_title': null,
    'start_page_number': 1,
    'end_page_number': 2,
    'file_id': 'private',
  },
  {
    'type': 'content_block_location',
    'cited_text': 'quote',
    'document_index': 0,
    'document_title': null,
    'start_block_index': 0,
    'end_block_index': 1,
    'file_id': 'private',
  },
  {
    'type': 'search_result_location',
    'cited_text': 'quote',
    'search_result_index': 1,
    'source': 'source',
    'title': 'S',
    'start_block_index': 0,
    'end_block_index': 1,
  },
  {
    'type': 'web_search_result_location',
    'cited_text': 'quote',
    'url': 'https://example.com',
    'title': 'web',
    'encrypted_index': 'private',
  },
];

void main() {
  test(
    'projects five citation kinds at block stop with UTF-16 spans and replays safely',
    () async {
      var calls = 0;
      late List<JsonObject> replay;
      final model = api.AnthropicProtocolModel(
        model: 'fixture',
        citations: true,
        transport: (body, _) async* {
          final content =
              ((body['messages'] as List).first as Map)['content'] as List;
          expect((content.first as Map)['citations'], {'enabled': true});
          if (calls++ == 1) {
            final blocks =
                ((body['messages'] as List)[1] as Map)['content'] as List;
            final raw = (blocks[0] as Map)['citations'] as List;
            expect((raw[0] as Map).containsKey('file_id'), false);
            expect(raw[4]['encrypted_index'], 'private');
            expect(raw[4]['future'], 'retained');
          }
          yield f.start();
          yield f.block(0, {
            'type': 'text',
            'text': '😀',
            'citations': [variants[0]],
          });
          for (final c in variants.skip(1)) {
            yield f.delta(0, {
              'type': 'citations_delta',
              'citation': {
                ...c,
                if (c['type'] == 'web_search_result_location')
                  'future': 'retained',
              },
            });
          }
          yield f.delta(0, {'type': 'text_delta', 'text': 'ab'});
          yield f.stop(0);
          yield f.block(1, {'type': 'text', 'text': 'z'});
          yield f.stop(1);
          yield f.finish('end_turn');
          yield f.done;
        },
      );
      final doc = ChatMessage(
        id: 'u',
        role: MessageRole.user,
        content: [DocumentPart.url('https://example.com/a.pdf')],
      );
      final result = await model
          .stream(
            ModelRequest(messages: [doc]),
            cancellation: CancellationToken(),
          )
          .toList();
      final citations = result
          .whereType<CitationReady>()
          .map((e) => e.citation)
          .toList();
      expect(citations.length, 5);
      expect(citations.map((c) => [c.start, c.end]), everyElement([0, 4]));
      expect(citations.map((c) => c.source.runtimeType), [
        DocumentCitationSource,
        DocumentCitationSource,
        DocumentCitationSource,
        SearchResultCitationSource,
        UrlCitationSource,
      ]);
      expect(citations[0].source.toJson()['location'], {
        'unit': 'characters',
        'start': 2,
        'end': 5,
      });
      replay = result.whereType<ProviderOutput>().first.items;
      expect((replay.first['citations'] as List).first['file_id'], 'private');
      await model
          .stream(
            ModelRequest(
              messages: [
                doc,
                ChatMessage(
                  id: 'a',
                  role: MessageRole.assistant,
                  providerData: {'anthropic.messages': replay},
                ),
                ChatMessage.user('next', id: 'next'),
              ],
            ),
            cancellation: CancellationToken(),
          )
          .drain<void>();
    },
  );
  test(
    'rejects unsafe, unknown, malformed and interleaved citations',
    () async {
      for (final c in [
        {...variants[0], 'start_char_index': 9},
        {...variants[4], 'url': 'https://u:p@example.com'},
        {'type': 'future', 'cited_text': 'x'},
        {...variants[0], 'document_index': 'bad'},
      ]) {
        final model = api.AnthropicProtocolModel(
          model: 'fixture',
          transport: (_, _) async* {
            yield f.start();
            yield f.block(0, {
              'type': 'text',
              'text': 'a',
              'citations': [c],
            });
            yield f.stop(0);
            yield f.finish('end_turn');
            yield f.done;
          },
        );
        await expectLater(
          model.stream(f.request, cancellation: CancellationToken()).toList(),
          throwsA(anything),
        );
      }
      final overlap = api.AnthropicProtocolModel(
        model: 'fixture',
        transport: (_, _) async* {
          yield f.start();
          yield f.block(0, {'type': 'text', 'text': 'a'});
          yield f.block(1, {'type': 'text', 'text': 'b'});
        },
      );
      await expectLater(
        overlap.stream(f.request, cancellation: CancellationToken()).toList(),
        throwsFormatException,
      );
    },
  );
  test(
    'validates all document settings and structured output before transport',
    () async {
      final docs = ModelRequest(
        messages: [
          ChatMessage(
            id: 'u',
            role: MessageRole.user,
            content: [
              DocumentPart.url('https://example.com/1.pdf'),
              DocumentPart.fileId('id', provider: 'anthropic'),
            ],
          ),
        ],
      );
      var sent = false;
      api.AnthropicProtocolModel build(
        JsonObject Function(JsonObject) configure,
      ) => api.AnthropicProtocolModel(
        model: 'fixture',
        configure: configure,
        transport: (_, _) async* {
          sent = true;
          yield f.start();
          yield f.finish('end_turn');
          yield f.done;
        },
      );
      JsonObject change(
        JsonObject body,
        void Function(List<dynamic> content) mutate,
      ) {
        final messages = [
          for (final m in body['messages'] as List)
            Map<String, Object?>.from(m as Map),
        ];
        final content = [
          for (final b in messages.first['content'] as List)
            Map<String, Object?>.from(b as Map),
        ];
        messages.first['content'] = content;
        mutate(content);
        return {...body, 'messages': messages};
      }

      await build(
        (b) => change(b, (c) {
          for (final doc in c) {
            doc['citations'] = {'enabled': true};
            doc['context'] = 'context';
            doc['cache_control'] = {'type': 'ephemeral'};
          }
        }),
      ).stream(docs, cancellation: CancellationToken()).drain<void>();
      expect(sent, true);
      sent = false;
      for (final configure in <JsonObject Function(JsonObject)>[
        (b) => change(b, (c) {
          c.first['citations'] = {'enabled': true};
        }),
        (b) => change(b, (c) {
          c.first['source'] = {'type': 'url', 'url': 'https://other.example'};
        }),
        (b) => {
          ...change(b, (c) {
            for (final doc in c) {
              doc['citations'] = {'enabled': true};
            }
          }),
          'output_format': {'type': 'json_schema'},
        },
      ]) {
        await expectLater(
          build(
            configure,
          ).stream(docs, cancellation: CancellationToken()).toList(),
          throwsArgumentError,
        );
        expect(sent, false);
      }
    },
  );
  test('SDK facade sends citation setting over serialized SSE', () async {
    final client = f.fixture(
      [
        f.start(),
        f.block(0, {'type': 'text', 'text': 'answer'}),
        f.delta(0, {'type': 'citations_delta', 'citation': variants.first}),
        f.stop(0),
        f.finish('end_turn'),
        f.done,
      ],
      (http) {
        expect(http.body, contains('"citations":{"enabled":true}'));
      },
    );
    final model = api.AnthropicChatModel(
      client: client,
      model: 'fixture',
      citations: true,
    );
    final result = await model
        .stream(
          ModelRequest(
            messages: [
              ChatMessage(
                id: 'u',
                role: MessageRole.user,
                content: [DocumentPart.url('https://example.com/a.pdf')],
              ),
            ],
          ),
          cancellation: CancellationToken(),
        )
        .toList();
    expect(result.whereType<CitationReady>().length, 1);
  });
  test(
    'a malformed citation or EOF never releases staged tool calls',
    () async {
      for (final malformed in [true, false]) {
        final model = api.AnthropicProtocolModel(
          model: 'fixture',
          transport: (_, _) async* {
            yield f.start();
            yield f.block(0, {
              'type': 'tool_use',
              'id': 't',
              'name': 'lookup',
              'input': <String, Object?>{},
            });
            yield f.stop(0);
            if (malformed) {
              yield f.block(1, {
                'type': 'text',
                'text': 'x',
                'citations': [
                  {'type': 'future'},
                ],
              });
              yield f.stop(1);
            }
          },
        );
        final seen = <ModelEvent>[];
        await expectLater(
          model.stream(f.request, cancellation: CancellationToken()).map((e) {
            seen.add(e);
            return e;
          }).toList(),
          throwsA(anything),
        );
        expect(seen.whereType<ToolCallReady>(), isEmpty);
      }
    },
  );
  test('citation-enabled models advertise no structured output', () {
    final client = f.fixture([], (_) {});
    expect(
      api.AnthropicChatModel(
        client: client,
        model: 'x',
      ).capabilities.structuredOutput,
      isTrue,
    );
    expect(
      api.AnthropicChatModel(
        client: client,
        model: 'x',
        citations: true,
      ).capabilities.structuredOutput,
      isFalse,
    );
    Stream<JsonObject> transport(JsonObject _, CancellationToken _) =>
        const Stream.empty();
    expect(
      api.AnthropicProtocolModel(
        model: 'x',
        transport: transport,
      ).capabilities.structuredOutput,
      isTrue,
    );
    expect(
      api.AnthropicProtocolModel(
        model: 'x',
        transport: transport,
        citations: true,
      ).capabilities.structuredOutput,
      isFalse,
    );
  });
  test('citation enabled value must be a boolean when present', () async {
    final doc = ModelRequest(
      messages: [
        ChatMessage(
          id: 'u',
          role: MessageRole.user,
          content: [DocumentPart.url('https://example.com/doc.pdf')],
        ),
      ],
    );
    for (final bad in [null, 1, 'true']) {
      var sent = false;
      final model = api.AnthropicProtocolModel(
        model: 'x',
        configure: (body) {
          final message = Map<String, Object?>.from(
            (body['messages'] as List).single as Map,
          );
          final content = Map<String, Object?>.from(
            (message['content'] as List).single as Map,
          );
          content['citations'] = {'enabled': bad};
          message['content'] = [content];
          return {
            ...body,
            'messages': [message],
          };
        },
        transport: (_, _) async* {
          sent = true;
        },
      );
      await expectLater(
        model.stream(doc, cancellation: CancellationToken()).toList(),
        throwsFormatException,
      );
      expect(sent, isFalse);
    }
  });
}
