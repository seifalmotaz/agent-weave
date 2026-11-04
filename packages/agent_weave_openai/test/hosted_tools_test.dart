import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final imageOptions = <String, Object?>{
    'type': 'image_generation',
    'action': 'edit',
    'background': 'transparent',
    'input_fidelity': 'high',
    'input_image_mask': {'image_url': 'data:image/png;base64,AA=='},
    'moderation': 'low',
    'output_compression': 75,
    'output_format': 'webp',
    'partial_images': 2,
    'quality': 'high',
    'size': '1024x1024',
    'future_option': {'nested': true},
  };
  final hosted = openai.OpenAIHostedTool.fromJson(imageOptions);

  test(
    'native request preserves all image options and snapshots input',
    () async {
      JsonObject? sent;
      final definition = jsonDecode(jsonEncode(imageOptions)) as JsonObject;
      final tool = openai.OpenAIHostedTool.fromJson(definition);
      (definition['future_option'] as Map)['nested'] = false;
      final model = openai.ResponsesProtocolModel.native(
        authorityBindingId: 'fixture-authority',
        model: 'm',
        hostedTools: [tool],
        options: const {'temperature': 0.2},
        transport: (body, _) async* {
          sent = body;
          yield {
            'type': 'response.completed',
            'response': {'status': 'completed', 'output': <Object?>[]},
          };
        },
      );
      await model
          .stream(ModelRequest(messages: []), cancellation: CancellationToken())
          .toList();
      expect((sent!['tools'] as List).single, imageOptions);
      expect(sent!['temperature'], 0.2);
      expect(
        () => (tool.definition['future_option'] as Map)['nested'] = false,
        throwsUnsupportedError,
      );
    },
  );

  test('typed SDK configuration preserves unknown hosted fields', () async {
    JsonObject? sent;
    final transport = MockClient((request) async {
      sent = jsonDecode(request.body) as JsonObject;
      return http.Response(
        'data: ${jsonEncode({
          'type': 'response.completed',
          'response': {'status': 'completed', 'output': <Object?>[]},
        })}\n\ndata: [DONE]\n\n',
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final client = openai.OpenAIClient(
      config: const openai.OpenAIConfig(
        authProvider: openai.ApiKeyProvider('fixture-key'),
        retryPolicy: openai.RetryPolicy(maxRetries: 0),
      ),
      httpClient: transport,
      streamClientFactory: () => transport,
    );
    addTearDown(client.close);
    final model = openai.OpenAIResponsesModel(
      authorityBindingId: 'fixture-authority',
      client: client,
      model: 'm',
      hostedTools: [
        openai.OpenAIHostedTool.fromJson({
          'type': 'web_search',
          'future_field': {'nested': 42},
        }),
      ],
      options: const {'temperature': 0.2},
    );
    await model
        .stream(ModelRequest(messages: []), cancellation: CancellationToken())
        .toList();
    expect((sent!['tools'] as List).single['future_field'], {'nested': 42});
    expect(sent!['temperature'], 0.2);
  });

  test('configure cannot mutate runtime history before dispatch', () async {
    var dispatched = false;
    final model = openai.ResponsesProtocolModel.native(
      authorityBindingId: 'fixture-authority',
      model: 'm',
      configure: (body) {
        (body['input'] as List).clear();
        return body;
      },
      transport: (_, _) {
        dispatched = true;
        return const Stream.empty();
      },
    );
    await expectLater(
      model
          .stream(
            ModelRequest(
              messages: [
                ChatMessage(
                  id: 'u',
                  role: MessageRole.user,
                  content: [TextPart('hello')],
                ),
              ],
            ),
            cancellation: CancellationToken(),
          )
          .toList(),
      throwsA(anyOf(isA<ArgumentError>(), isA<UnsupportedError>())),
    );
    expect(dispatched, isFalse);
  });

  test('hosted definitions reject invalid registrations', () async {
    for (final invalid in <JsonObject>[
      {'type': 'function', 'name': 'unregistered'},
      {'type': 'file_search', 'vector_store_ids': []},
      {'type': 'code_interpreter', 'container': ''},
      {'type': 'tool_search', 'execution': 'client'},
      {'type': 'image_generation', 'output_compression': 101},
      {'type': 'image_generation', 'output_compression': 2.5},
      {'type': 'image_generation', 'input_image_mask': 'bad'},
    ]) {
      expect(
        () => openai.OpenAIHostedTool.fromJson(invalid),
        throwsArgumentError,
      );
    }
    final model = openai.ResponsesProtocolModel.native(
      authorityBindingId: 'fixture-authority',
      model: 'm',
      hostedTools: [
        openai.OpenAIHostedTool.fromJson({'type': 'web_search'}),
        openai.OpenAIHostedTool.fromJson({'type': 'web_search_preview'}),
      ],
      transport: (_, _) => throw StateError('must not dispatch'),
    );
    await expectLater(
      model
          .stream(ModelRequest(messages: []), cancellation: CancellationToken())
          .toList(),
      throwsArgumentError,
    );
  });

  test(
    'terminal hosted output is replayed exactly on the next request',
    () async {
      final raw = <JsonObject>[
        {
          'type': 'tool_search_call',
          'id': 'search-call',
          'call_id': null,
          'execution': 'server',
          'status': 'completed',
          'arguments': {'query': 'tools'},
          'future_field': 'private',
        },
        {
          'type': 'tool_search_output',
          'id': 'search-output',
          'call_id': null,
          'execution': 'server',
          'status': 'completed',
          'tools': <Object?>[],
        },
        {
          'type': 'image_generation_call',
          'id': 'img',
          'status': 'completed',
          'result': 'AA==',
          'future_field': {'opaque': 1},
        },
        {
          'type': 'message',
          'id': 'msg',
          'role': 'assistant',
          'content': [
            {'type': 'output_text', 'text': 'done'},
          ],
        },
      ];
      final requests = <JsonObject>[];
      final model = openai.ResponsesProtocolModel.native(
        authorityBindingId: 'fixture-authority',
        model: 'm',
        hostedTools: [
          hosted,
          openai.OpenAIHostedTool.fromJson({
            'type': 'tool_search',
            'execution': 'server',
          }),
        ],
        transport: (body, _) async* {
          requests.add(body);
          yield {
            'type': 'response.completed',
            'response': {
              'status': 'completed',
              'output': requests.length == 1 ? raw : <Object?>[],
            },
          };
        },
      );
      final events = await model
          .stream(ModelRequest(messages: []), cancellation: CancellationToken())
          .toList();
      final replay = events.whereType<ProviderOutput>().first.items;
      expect(replay, raw);
      await model
          .stream(
            ModelRequest(
              messages: [
                ChatMessage(
                  id: 'a',
                  role: MessageRole.assistant,
                  providerData: {'openai.responses': replay},
                ),
              ],
            ),
            cancellation: CancellationToken(),
          )
          .toList();
      expect(requests.last['input'], raw);
    },
  );

  test(
    'image placement, MIME and base64 follow terminal output order',
    () async {
      final model = openai.ResponsesProtocolModel.native(
        authorityBindingId: 'fixture-authority',
        model: 'm',
        hostedTools: [hosted],
        transport: (_, _) async* {
          yield {
            'type': 'response.completed',
            'response': {
              'status': 'completed',
              'output': [
                {
                  'type': 'message',
                  'id': 'a',
                  'content': [
                    {'type': 'output_text', 'text': 'before'},
                  ],
                },
                {
                  'type': 'image_generation_call',
                  'id': 'i',
                  'status': 'completed',
                  'result': 'AA==',
                },
                {
                  'type': 'message',
                  'id': 'b',
                  'content': [
                    {'type': 'output_text', 'text': 'after'},
                  ],
                },
              ],
            },
          };
        },
      );
      final events = await model
          .stream(ModelRequest(messages: []), cancellation: CancellationToken())
          .toList();
      final part = events.whereType<ContentPartReady>().single;
      expect(part.textOffset, 6);
      expect((part.part as ImagePart).url, 'data:image/webp;base64,AA==');
    },
  );

  test('unsafe terminal output never releases a local function call', () async {
    final call = {
      'type': 'function_call',
      'id': 'item',
      'call_id': 'call',
      'name': 'local',
      'arguments': '{}',
      'status': 'completed',
    };
    for (final terminal in <JsonObject>[
      {
        'type': 'response.incomplete',
        'response': {
          'status': 'incomplete',
          'output': [call],
        },
      },
      {
        'type': 'response.completed',
        'response': {
          'status': 'completed',
          'output': [
            call,
            {'type': 'unknown_future_call', 'id': 'x'},
          ],
        },
      },
      {
        'type': 'response.completed',
        'response': {
          'status': 'completed',
          'output': [
            call,
            {
              'type': 'image_generation_call',
              'id': 'i',
              'status': 'completed',
              'result': '!!!',
            },
          ],
        },
      },
    ]) {
      final events = <ModelEvent>[];
      final model = openai.ResponsesProtocolModel.native(
        authorityBindingId: 'fixture-authority',
        model: 'm',
        hostedTools: [hosted],
        transport: (_, _) async* {
          yield terminal;
        },
      );
      await expectLater(
        model
            .stream(
              ModelRequest(messages: []),
              cancellation: CancellationToken(),
            )
            .map((event) {
              events.add(event);
              return event;
            })
            .toList(),
        throwsA(anything),
      );
      expect(events.whereType<ToolCallReady>(), isEmpty);
    }
  });
}
