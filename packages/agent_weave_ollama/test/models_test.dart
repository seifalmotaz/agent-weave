import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_ollama/agent_weave_ollama.dart'
    hide ChatMessage, MessageRole;
import 'package:ollama_dart/ollama_dart.dart' as api;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final request = ModelRequest(messages: [ChatMessage.user('hi', id: 'u')]);
  OllamaNativeClient clientFor(
    List<Map<String, Object?>> frames, [
    void Function(Map<String, dynamic>)? capture,
  ]) => OllamaNativeClient(
    httpClient: MockClient((r) async {
      capture?.call(jsonDecode(r.body) as Map<String, dynamic>);
      return http.Response('${frames.map(jsonEncode).join('\n')}\n', 200);
    }),
  );
  Future<List<ModelEvent>> run(
    OllamaNativeClient c, {
    ModelRequest? input,
    OllamaChatModel? model,
  }) => (model ?? c.chatModel(model: 'm'))
      .stream(input ?? request, cancellation: CancellationToken())
      .toList();
  Map<String, Object?> frame({
    String? reason = 'stop',
    List<Object?>? calls,
    String? text,
    String? think,
  }) => {
    'model': 'm',
    'message': {
      'role': 'assistant',
      'content': ?text,
      'thinking': ?think,
      'tool_calls': ?calls,
    },
    'done': true,
    'done_reason': ?reason,
  };
  Map<String, Object?> call(
    String name, {
    int? index,
    String? id,
    int value = 1,
  }) => {
    'id': ?id,
    'function': {
      'name': name,
      'arguments': {'v': value},
      'index': ?index,
    },
  };

  test('typed options and structured output serialize', () async {
    final c = clientFor([frame()], (body) {
      expect(body['options']['temperature'], 0.3);
      expect(body['options']['num_predict'], 20);
      expect(body['think'], 'high');
      expect(body['keep_alive'], '5m');
      expect(body['format']['type'], 'object');
    });
    await run(
      c,
      input: ModelRequest(
        messages: request.messages,
        maxOutputTokens: 20,
        outputSchema: {'type': 'object'},
      ),
      model: c.chatModel(
        model: 'm',
        options: const api.ModelOptions(temperature: 0.3),
        think: const api.ThinkValue.level(api.ThinkLevel.high),
        keepAlive: const api.KeepAlive.duration('5m'),
      ),
    );
    c.close();
  });
  for (final field in ['model', 'messages', 'stream', 'tools']) {
    test('configure cannot replace $field', () async {
      final c = clientFor([frame()]);
      await expectLater(
        run(
          c,
          model: c.chatModel(
            model: 'm',
            configure: (body) => {...body, field: 'bad'},
          ),
        ),
        throwsArgumentError,
      );
      c.close();
    });
  }
  test('configure cannot replace num_predict', () async {
    final c = clientFor([frame()]);
    await expectLater(
      run(
        c,
        model: c.chatModel(
          model: 'm',
          configure: (body) => {
            ...body,
            'options': {'num_predict': 2},
          },
        ),
      ),
      throwsArgumentError,
    );
    c.close();
  });
  test('typed num_predict mismatch rejected', () async {
    final c = clientFor([frame()]);
    await expectLater(
      run(
        c,
        model: c.chatModel(
          model: 'm',
          options: const api.ModelOptions(numPredict: 4),
        ),
      ),
      throwsArgumentError,
    );
    c.close();
  });
  test(
    'thinking and unknown message metadata survive private replay, frames retain logprobs',
    () async {
      final f = frame(think: 'exact', text: 'hello');
      (f['message'] as Map)['unknown'] = {'x': 1};
      f['logprobs'] = [
        {'token': 'x'},
      ];
      final c = clientFor([f]);
      final out = await run(c);
      final replay = out.whereType<ProviderOutput>().singleWhere(
        (e) => e.provider == 'ollama.chat',
      );
      final frames = out.whereType<ProviderOutput>().singleWhere(
        (e) => e.provider == 'ollama.chat.frames',
      );
      expect(replay.items.single['thinking'], 'exact');
      expect(replay.items.single['unknown'], {'x': 1});
      expect(frames.items.single['logprobs'], isNotNull);
      c.close();
    },
  );
  test(
    'tool call emitted only after terminal frame and local ID differs from native',
    () async {
      final c = clientFor([
        {
          'message': {
            'role': 'assistant',
            'tool_calls': [call('x', index: 0, id: 'native')],
          },
          'done': false,
        },
        frame(),
      ]);
      final events = await run(c);
      final tool = events.whereType<ToolCallReady>().single.call;
      expect(tool.id, isNot('native'));
      expect(tool.id, startsWith('ollama-'));
      c.close();
    },
  );
  test('duplicate identical native index is one call', () async {
    final c = clientFor([
      {
        'message': {
          'role': 'assistant',
          'tool_calls': [call('x', index: 0, id: 'native')],
        },
        'done': false,
      },
      frame(calls: [call('x', index: 0, id: 'native')]),
    ]);
    expect((await run(c)).whereType<ToolCallReady>(), hasLength(1));
    c.close();
  });
  test('conflicting repeated index fails before tools', () async {
    final c = clientFor([
      {
        'message': {
          'role': 'assistant',
          'tool_calls': [call('x', index: 0)],
        },
        'done': false,
      },
      frame(calls: [call('x', index: 0, value: 2)]),
    ]);
    await expectLater(run(c), throwsUnsupportedError);
    c.close();
  });
  test('calls without id or index are distinct', () async {
    final c = clientFor([
      frame(calls: [call('x'), call('x')]),
    ]);
    expect((await run(c)).whereType<ToolCallReady>(), hasLength(2));
    c.close();
  });
  test('length completion with tool call never executes', () async {
    final c = clientFor([
      frame(reason: 'length', calls: [call('x')]),
    ]);
    await expectLater(run(c), throwsFormatException);
    c.close();
  });
  test('unknown completion reason fails closed', () async {
    final c = clientFor([frame(reason: 'other')]);
    await expectLater(run(c), throwsUnsupportedError);
    c.close();
  });
  test('embedding validates dimensions and immutability', () {
    for (final metadata in [
      {'model': 3},
      {'prompt_eval_count': '5'},
      {'prompt_eval_count': 1.5},
      {'prompt_eval_count': -1},
    ]) {
      expect(
        () => OllamaEmbeddingResult.fromJson({'embeddings': [], ...metadata}),
        throwsFormatException,
      );
    }
    final result = OllamaEmbeddingResult.fromJson({
      'embeddings': [
        [1, 2],
        [3, 4],
      ],
      'model': 'm',
    });
    expect(result.embeddings[0], [1.0, 2.0]);
    expect(() => result.embeddings[0].add(3), throwsUnsupportedError);
    expect(() => result.raw['x'] = 2, throwsUnsupportedError);
    expect(
      () => OllamaEmbeddingResult.fromJson({
        'embeddings': [
          [1],
          [2, 3],
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => OllamaEmbeddingResult.fromJson({
        'embeddings': [
          [double.nan],
        ],
      }),
      throwsFormatException,
    );
  });
  test(
    'tool replay retains thinking and uses name without invented native id',
    () async {
      var count = 0;
      final c = clientFor(
        [
          frame(calls: [call('lookup')], think: 'private'),
        ],
        (body) {
          if (++count == 2) {
            final messages = body['messages'] as List;
            expect(messages[0]['thinking'], 'private');
            expect(messages[1]['tool_name'], 'lookup');
            expect(messages[1].containsKey('tool_call_id'), false);
          }
        },
      );
      final events = await run(c);
      final tool = events.whereType<ToolCallReady>().single.call;
      final provider = {
        for (final event in events.whereType<ProviderOutput>())
          event.provider: event.items,
      };
      await run(
        c,
        input: ModelRequest(
          messages: [
            ChatMessage(
              id: 'a',
              role: MessageRole.assistant,
              toolCalls: [tool],
              providerData: provider,
            ),
            ChatMessage(
              id: 'r',
              role: MessageRole.tool,
              toolCallId: tool.id,
              content: [const TextPart('result')],
            ),
          ],
        ),
      );
      c.close();
    },
  );
  test(
    'reused native ID across separate turns gets distinct local IDs',
    () async {
      final c = clientFor([
        frame(calls: [call('x', id: 'same', index: 0)]),
      ]);
      final first = (await run(c)).whereType<ToolCallReady>().single.call.id;
      final second = (await run(c)).whereType<ToolCallReady>().single.call.id;
      expect(first, isNot(second));
      c.close();
    },
  );
  test('inline image is base64 without data prefix', () async {
    final c = clientFor([frame()], (body) {
      expect(body['messages'][0]['images'], ['YQ==']);
    });
    await run(
      c,
      input: ModelRequest(
        messages: [
          ChatMessage(
            id: 'u',
            role: MessageRole.user,
            content: [const ImagePart('data:image/png;base64,YQ==')],
          ),
        ],
      ),
    );
    c.close();
  });
  test('remote image URL rejected before HTTP request', () async {
    var contacted = false;
    final c = clientFor([frame()], (_) {
      contacted = true;
    });
    await expectLater(
      run(
        c,
        input: ModelRequest(
          messages: [
            ChatMessage(
              id: 'u',
              role: MessageRole.user,
              content: [const ImagePart('https://example.test/a.png')],
            ),
          ],
        ),
      ),
      throwsUnsupportedError,
    );
    expect(contacted, false);
    c.close();
  });
  test('truncated text reports length', () async {
    final c = clientFor([frame(reason: 'length', text: 'partial')]);
    expect((await run(c)).whereType<ModelFinished>().single.reason, 'length');
    c.close();
  });
}
