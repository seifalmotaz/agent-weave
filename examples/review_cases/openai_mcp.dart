// Offline MCP approval consumer: dart run examples/review_cases/openai_mcp.dart
import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;
import 'package:agent_weave_serverpod_client/agent_weave_serverpod_client.dart';
import 'package:tanstack_ai_dart/tanstack_ai_dart.dart' as client_api;

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Map<String, Object?> mcp(String label, {String? url}) => {
  'type': 'mcp',
  'server_label': label,
  'server_url': url ?? 'https://$label.example.invalid/mcp',
  'require_approval': 'always',
};

Future<void> main() async {
  final bodies = <Map<String, dynamic>>[];
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    bodies.add(
      jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>,
    );
    request.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    final output = bodies.length == 1
        ? <Object?>[
            {
              'id': 'list-a',
              'type': 'mcp_list_tools',
              'server_label': 'tickets',
              'tools': <Object?>[],
              'private_future': 'PRIVATE_REPLAY',
            },
            {
              'id': 'approve-a',
              'type': 'mcp_approval_request',
              'name': 'escalate',
              'server_label': 'tickets',
              'arguments': '{"ticket":42}',
            },
            {
              'id': 'approve-b',
              'type': 'mcp_approval_request',
              'name': 'notify',
              'server_label': 'messages',
              'arguments': '{"ticket":42}',
            },
          ]
        : <Object?>[
            {
              'id': 'answer',
              'type': 'message',
              'role': 'assistant',
              'status': 'completed',
              'content': [
                {
                  'type': 'output_text',
                  'text': 'Decisions recorded.',
                  'annotations': <Object?>[],
                },
              ],
            },
          ];
    void send(Map<String, Object?> event) =>
        request.response.write('data: ${jsonEncode(event)}\n\n');
    for (var i = 0; i < output.length; i++) {
      send({
        'type': 'response.output_item.done',
        'output_index': i,
        'item': output[i],
      });
    }
    if (bodies.length > 1) {
      send({
        'type': 'response.output_text.delta',
        'item_id': 'answer',
        'output_index': 0,
        'content_index': 0,
        'delta': 'Decisions recorded.',
      });
    }
    send({
      'type': 'response.completed',
      'response': {
        'id': 'response-${bodies.length}',
        'object': 'response',
        'created_at': 0,
        'status': 'completed',
        'model': 'fixture',
        'output': output,
      },
    });
    request.response.write('data: [DONE]\n\n');
    await request.response.close();
  });
  final client = openai.OpenAIClient(
    config: openai.OpenAIConfig(
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      authProvider: openai.ApiKeyProvider('fixture'),
    ),
  );
  final store = MemoryRunStore();
  var credentialResolutions = 0;
  AiAgent<void> agent({bool changed = false}) => AiAgent<void>(
    store: store,
    model: openai.OpenAIResponsesModel.native(
      authorityBindingId: 'example-authority',
      client: client,
      model: 'fixture',
      mcpTools: [
        openai.OpenAIMcpTool.fromJson(
          mcp(
            'tickets',
            url: changed ? 'https://changed.example.invalid/mcp' : null,
          ),
          credentialBindingId: 'tickets-account',
          credentials: () => openai.OpenAIMcpCredentials(
            authorization: 'SECRET_${++credentialResolutions}',
          ),
        ),
        openai.OpenAIMcpTool.fromJson(mcp('messages')),
      ],
    ),
  );
  try {
    final paused = await agent().generate(
      ChatRequest(
        threadId: 'support',
        runId: 'first',
        messages: [ChatMessage.user('Escalate and notify', id: 'user')],
      ),
      ownerId: 'owner',
      context: null,
    );
    check(
      paused.status == RunStatus.interrupted &&
          paused.interrupts.length == 2 &&
          bodies.length == 1,
      'Expected two approvals before continuation',
    );
    check(
      paused.interrupts.every((i) => i.call is ProviderApprovalCall),
      'Missing typed provider approval',
    );
    final decisions = [
      paused.interrupts[0].approve(),
      paused.interrupts[1].reject(),
    ];
    try {
      await agent(changed: true).generate(
        ChatRequest(
          threadId: 'support',
          runId: 'changed',
          parentRunId: paused.runId,
          resume: decisions,
        ),
        ownerId: 'owner',
        context: null,
      );
      throw StateError('Changed server contract accepted');
    } on AgentRunException catch (e) {
      check(
        e.code == 'INVALID_INPUT' && bodies.length == 1,
        'Changed contract must fail before provider call: ${e.code}',
      );
    }
    final resumed = await agent().generate(
      ChatRequest(
        threadId: 'support',
        runId: 'second',
        parentRunId: paused.runId,
        resume: decisions,
      ),
      ownerId: 'owner',
      context: null,
    );
    check(
      resumed.status == RunStatus.completed &&
          resumed.text == 'Decisions recorded.',
      'Resume did not complete',
    );
    check(bodies.length == 2, 'Unexpected provider invocations');
    final responses = (bodies.last['input'] as List)
        .whereType<Map<dynamic, dynamic>>()
        .where((item) => item['type'] == 'mcp_approval_response')
        .toList();
    check(
      responses.length == 2 &&
          responses[0]['approval_request_id'] == 'approve-a' &&
          responses[0]['approve'] == true &&
          responses[1]['approval_request_id'] == 'approve-b' &&
          responses[1]['approve'] == false,
      'Native decision mapping differs: $responses',
    );
    check(
      credentialResolutions == 2 &&
          jsonEncode(bodies.first).contains('SECRET_1') &&
          jsonEncode(bodies.last).contains('SECRET_2'),
      'Credentials not refreshed per request',
    );
    final raw = jsonEncode(bodies.last);
    check(
      raw.contains('mcp_approval_response') &&
          raw.contains('approve-a') &&
          raw.contains('approve-b') &&
          raw.contains('PRIVATE_REPLAY'),
      'Native responses or replay missing',
    );
    check(
      !raw.contains('function_call_output'),
      'MCP decisions became local function results',
    );
    final hydration = jsonEncode(
      chatHydration(await store.load(ownerId: 'owner', threadId: 'support')),
    );
    check(
      !hydration.contains('PRIVATE_REPLAY') &&
          !hydration.contains('approve-a') &&
          !hydration.contains('approve-b') &&
          !hydration.contains('SECRET_'),
      'Private provider state leaked',
    );
    check(
      await store.load(ownerId: 'other-owner', threadId: 'support') == null,
      'History crossed owner boundary',
    );
    try {
      await agent().generate(
        ChatRequest(
          threadId: 'cancelled',
          runId: 'cancel',
          messages: [ChatMessage.user('Cancel', id: 'cancel-user')],
        ),
        ownerId: 'owner',
        context: null,
        cancellation: CancellationToken()..cancel(),
      );
      throw StateError('Pre-cancelled operation completed');
    } on RunCancelled {
      check(bodies.length == 2, 'Cancelled operation contacted provider');
    }
    print(
      'PASS two servers, approve and reject, recreated agent, changed contract, private replay',
    );
    bodies.clear();
    final chatAgent = agent();
    final chat = client_api.ChatClient(
      threadId: 'client',
      connection: serverpodConnection(
        send: (raw) => chatAgent
            .run(
              ChatRequest.fromJson(
                Map<String, Object?>.from(jsonDecode(raw) as Map),
              ),
              ownerId: 'owner',
              context: null,
            )
            .map((event) => jsonEncode(event.json)),
      ),
    );
    try {
      await chat.sendText('Escalate and notify');
      check(
        chat.error == null &&
            chat.getInterrupts().length == 2 &&
            chat.getInterrupts().every(
              (i) => i.kind == 'generic' && i.canResolve,
            ),
        'Dart client approvals unavailable',
      );
      final clientInterrupts = chat.getInterrupts();
      clientInterrupts[0].resolveInterrupt({'approved': true});
      clientInterrupts[1].resolveInterrupt({'approved': false});
      for (
        var i = 0;
        i < 100 &&
            chat.error == null &&
            !chat.messages.any((m) => m.answer == 'Decisions recorded.');
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      check(
        chat.error == null &&
            bodies.length == 2 &&
            chat.messages.last.answer == 'Decisions recorded.',
        'Dart client approval did not complete',
      );
      print('PASS Dart client generic approval and denial');
    } finally {
      await chat.dispose();
    }
  } finally {
    client.close();
    await server.close(force: true);
  }
}
