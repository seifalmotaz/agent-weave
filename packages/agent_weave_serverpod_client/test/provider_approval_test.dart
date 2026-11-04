import 'package:agent_weave_serverpod_client/agent_weave_serverpod_client.dart';
import 'package:tanstack_ai_dart/tanstack_ai_dart.dart' as client;
import 'package:test/test.dart';

client.ChatInterrupt descriptor({
  Map<String, dynamic>? metadata = const {
    'providerApproval': {
      'provider': 'openai.responses',
      'serverLabel': 'support',
    },
    'toolName': 'escalate',
  },
  Object? input = const {'ticket': 42},
  String? toolCallId = 'local-call',
  String kind = 'generic',
  bool canResolve = true,
  Object? Function(dynamic, [dynamic])? resolve,
}) => client.ChatInterrupt(
  id: 'approval',
  kind: kind,
  reason: 'tool_call',
  threadId: 't',
  interruptedRunId: 'r',
  generation: 1,
  metadata: metadata,
  input: input,
  toolCallId: toolCallId,
  canResolve: canResolve,
  onResolveInterrupt: resolve,
);

void main() {
  test('reads typed provider identity and snapshots nested JSON arguments', () {
    final input = <String, Object?>{
      'customer': <String, Object?>{'name': 'Ali'},
      'tags': <Object?>['new'],
    };
    final approval = descriptor(input: input).providerApproval!;
    expect(approval.id, 'approval');
    expect(approval.provider, 'openai.responses');
    expect(approval.serverLabel, 'support');
    expect(approval.toolName, 'escalate');
    expect(approval.toolCallId, 'local-call');
    (input['customer'] as Map)['name'] = 'changed';
    (input['tags'] as List).clear();
    expect((approval.arguments['customer'] as Map)['name'], 'Ali');
    expect(approval.arguments['tags'], ['new']);
    expect(
      () => (approval.arguments['customer'] as Map).clear(),
      throwsUnsupportedError,
    );
    expect(
      () => (approval.arguments['tags'] as List).clear(),
      throwsUnsupportedError,
    );
  });

  test('ordinary interrupts have no provider approval', () {
    expect(descriptor(metadata: null).providerApproval, isNull);
    expect(descriptor(metadata: const {}).providerApproval, isNull);
  });

  test(
    'malformed declared provider metadata fails without echoing its data',
    () {
      for (final interrupt in [
        descriptor(metadata: {'providerApproval': 'PRIVATE_MARKER'}),
        descriptor(
          metadata: {
            'providerApproval': {'provider': '', 'serverLabel': 'support'},
            'toolName': 'escalate',
          },
        ),
        descriptor(
          metadata: {
            'providerApproval': {'provider': 'p', 'serverLabel': null},
            'toolName': 'escalate',
          },
        ),
        descriptor(input: 'PRIVATE_MARKER'),
        descriptor(toolCallId: null),
        descriptor(kind: 'client-tool-execution'),
      ]) {
        try {
          interrupt.providerApproval;
          fail('Expected malformed metadata rejection.');
        } on FormatException catch (error) {
          expect(error.source, isNull);
          expect(error.toString(), isNot(contains('PRIVATE_MARKER')));
        }
      }
    },
  );

  test('stages generic approval and denial with optional reason', () async {
    final payloads = <Object?>[];
    final approval = descriptor(
      resolve: (payload, [options]) {
        payloads.add(payload);
        return true;
      },
    ).providerApproval!;
    await approval.approve();
    await approval.reject(reason: 'Outside scope');
    expect(payloads, [
      {'approved': true},
      {'approved': false, 'reason': 'Outside scope'},
    ]);
  });

  test('unresolvable snapshot cannot invoke its callback', () async {
    var invoked = false;
    final approval = descriptor(
      canResolve: false,
      resolve: (_, [options]) {
        invoked = true;
        return true;
      },
    ).providerApproval!;
    expect(approval.canResolve, false);
    await expectLater(approval.approve(), throwsStateError);
    await expectLater(approval.reject(), throwsStateError);
    expect(invoked, false);
    expect(descriptor(kind: 'unbound').providerApproval!.canResolve, false);
  });

  test(
    'awaiting the action propagates asynchronous callback failure',
    () async {
      final approval = descriptor(
        resolve: (_, [options]) async => throw StateError('callback rejected'),
      ).providerApproval!;
      await expectLater(approval.approve(), throwsStateError);
    },
  );
}
