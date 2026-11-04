import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as api;
import 'package:test/test.dart';
import 'chat_test.dart' as f;

void main() {
  test(
    'computer calls retain block order when block stops arrive out of order',
    () async {
      final tool = api.AnthropicComputerTool<void>(
        environmentId: 'desktop',
        execute: (_, _) =>
            fail('Model normalization cannot execute the driver'),
      );
      final model = api.AnthropicProtocolModel(
        model: 'fixture',
        transport: (_, _) async* {
          yield f.start();
          for (final index in [0, 1]) {
            yield f.block(index, {
              'type': 'tool_use',
              'id': 'computer-$index',
              'toolset_name': 'computer',
              'name': 'key',
              'input': {'text': '$index'},
            });
          }
          yield f.stop(1);
          yield f.stop(0);
          yield f.finish('tool_use');
          yield f.done;
        },
      );
      final events = await model
          .stream(
            ModelRequest(messages: [], tools: [tool.definition]),
            cancellation: CancellationToken(),
          )
          .toList();
      expect(events.whereType<NativeToolCallReady>().map((e) => e.call.id), [
        'computer-0',
        'computer-1',
      ]);
    },
  );

  test(
    'native configuration supports scoped file handles while old typed SDK fails clearly',
    () async {
      final request = ModelRequest(
        messages: [
          ChatMessage(
            id: 'u',
            role: MessageRole.user,
            content: [DocumentPart.fileId('file', provider: 'anthropic')],
          ),
        ],
      );
      final raw = api.AnthropicProtocolModel(
        model: 'fixture',
        configure: (body) => {
          ...body,
          'cache_control': {'type': 'ephemeral'},
        },
        transport: (body, _) async* {
          expect(
            ((body['messages'] as List).single['content'] as List)
                .single['source'],
            {'type': 'file', 'file_id': 'file'},
          );
          yield f.start();
          yield f.finish('end_turn');
          yield f.done;
        },
      );
      await raw
          .stream(request, cancellation: CancellationToken())
          .drain<void>();
      final client = f.fixture(
        [],
        (_) => fail('Unsupported SDK input must not dispatch'),
      );
      await expectLater(
        api.AnthropicChatModel(
          client: client,
          model: 'fixture',
          configure: (r) => r.copyWith(temperature: .2),
        ).stream(request, cancellation: CancellationToken()).toList(),
        throwsUnsupportedError,
      );
    },
  );

  test('SDK option and cache edits preserve opaque replay fields', () async {
    final replay = <JsonObject>[
      {
        'type': 'thinking',
        'thinking': 'private',
        'signature': 'signed',
        'future_field': {
          'opaque': [1, 2],
        },
      },
      {'type': 'text', 'text': 'prior', 'future_text_field': 'preserved'},
    ];
    JsonObject? sent;
    final client = f.fixture([f.start(), f.finish('end_turn'), f.done], (r) {
      sent = Map<String, Object?>.from(jsonDecode(r.body) as Map);
    });
    final model = api.AnthropicChatModel(
      client: client,
      model: 'fixture',
      configure: (r) {
        final json = r.toJson();
        final messages = json['messages'] as List;
        final content = messages.first['content'] as List;
        content.first['cache_control'] = {'type': 'ephemeral', 'ttl': '1h'};
        return api.MessageCreateRequest.fromJson(
          json,
        ).copyWith(temperature: .2);
      },
    );
    await model
        .stream(
          ModelRequest(
            messages: [
              ChatMessage.user('hi', id: 'u'),
              ChatMessage(
                id: 'a',
                role: MessageRole.assistant,
                providerData: {'anthropic.messages': replay},
              ),
            ],
          ),
          cancellation: CancellationToken(),
        )
        .drain<void>();
    expect(sent!['temperature'], .2);
    final messages = sent!['messages'] as List;
    expect(messages[0]['content'][0]['cache_control'], {
      'type': 'ephemeral',
      'ttl': '1h',
    });
    expect(messages[1]['content'], replay);
  });

  test('SDK callback cannot mutate canonical history in place', () async {
    var dispatched = false;
    final client = f.fixture([], (_) => dispatched = true);
    final model = api.AnthropicChatModel(
      client: client,
      model: 'fixture',
      configure: (r) {
        r.messages.clear();
        return r;
      },
    );
    await expectLater(
      model.stream(f.request, cancellation: CancellationToken()).toList(),
      throwsArgumentError,
    );
    expect(dispatched, false);
  });

  test(
    'raw configuration is immutable and protects absent fields and schemas',
    () async {
      var dispatched = 0;
      final request = ModelRequest(
        messages: [ChatMessage.user('hi', id: 'u')],
        outputSchema: {'type': 'object'},
      );
      for (final configure in <JsonObject Function(JsonObject)>[
        (r) => {...r, 'system': 'injected'},
        (r) => {...r, 'messages': []},
        (r) => {...r, 'max_tokens': 9000},
        (r) => {...r, 'stream': false},
        (r) => {
          ...r,
          'output_config': {
            'format': {'type': 'text'},
          },
        },
      ]) {
        final model = api.AnthropicProtocolModel(
          model: 'fixture',
          configure: configure,
          transport: (_, _) async* {
            dispatched++;
          },
        );
        await expectLater(
          model.stream(request, cancellation: CancellationToken()).toList(),
          throwsArgumentError,
        );
      }
      final model = api.AnthropicProtocolModel(
        model: 'fixture',
        configure: (r) {
          (r['messages'] as List).clear();
          return r;
        },
        transport: (_, _) async* {
          dispatched++;
        },
      );
      await expectLater(
        model.stream(request, cancellation: CancellationToken()).toList(),
        throwsUnsupportedError,
      );
      expect(dispatched, 0);
    },
  );

  test(
    'raw blocks, citations and cumulative cache/reasoning usage survive',
    () async {
      final citation = {
        'type': 'web_search_result_location',
        'url': 'https://example.com',
        'title': 'source',
        'cited_text': 'source text',
        'encrypted_index': 'opaque',
        'future': {'signature': 'private'},
      };
      final model = api.AnthropicProtocolModel(
        model: 'requested-alias',
        transport: (_, _) async* {
          yield f.start();
          yield f.block(0, {'type': 'text', 'text': '', 'extra': 'private'});
          yield f.delta(0, {'type': 'text_delta', 'text': 'answer'});
          yield f.delta(0, {'type': 'citations_delta', 'citation': citation});
          yield f.stop(0);
          yield {
            'type': 'message_delta',
            'delta': {'stop_reason': 'end_turn'},
            'usage': {
              'input_tokens': 20,
              'output_tokens': 9,
              'cache_creation_input_tokens': 5,
              'cache_read_input_tokens': null,
              'output_tokens_details': {'thinking_tokens': 3},
              'unknown_usage': 'retained',
            },
          };
          yield f.done;
        },
      );
      final events = await model
          .stream(f.request, cancellation: CancellationToken())
          .toList();
      final usage = events.whereType<TokenUsage>().single;
      expect(usage.inputTokens, 29);
      expect(usage.outputTokens, 9);
      expect(usage.cachedInputTokens, 4);
      expect(usage.reasoningTokens, 3);
      expect(usage.model, 'fixture');
      final outputs = events.whereType<ProviderOutput>().toList();
      final replay = outputs
          .singleWhere((e) => e.provider == 'anthropic.messages')
          .items;
      expect(replay.single['citations'], [citation]);
      expect(replay.single['extra'], 'private');
      final metadata = outputs
          .singleWhere((e) => e.provider.endsWith('.metadata'))
          .items
          .single;
      expect((metadata['usage'] as Map)['unknown_usage'], 'retained');
      expect(metadata.containsKey('content'), false);
    },
  );

  for (final type in [
    'text_delta',
    'thinking_delta',
    'signature_delta',
    'input_json_delta',
    'citations_delta',
  ]) {
    test('rejects $type on a mismatched block', () async {
      final model = api.AnthropicProtocolModel(
        model: 'fixture',
        transport: (_, _) async* {
          yield f.start();
          yield f.block(0, {'type': 'redacted_thinking', 'data': 'opaque'});
          yield f.delta(0, {'type': type});
        },
      );
      await expectLater(
        model.stream(f.request, cancellation: CancellationToken()).toList(),
        throwsFormatException,
      );
    });
  }
}
