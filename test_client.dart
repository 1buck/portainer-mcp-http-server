// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main() async {
  final serverUrl = 'http://localhost:8080/sse';

  print('Connecting to $serverUrl...');

  final client = HttpClient();

  try {
    final request = await client.getUrl(Uri.parse(serverUrl));
    request.headers.set('Accept', 'text/event-stream');
    request.headers.set('Cache-Control', 'no-cache');
    request.headers.set('Connection', 'keep-alive');

    final response = await request.close();

    print('Response status: ${response.statusCode}');

    if (response.statusCode != 200) {
      print('Error: Unexpected status code');
      return;
    }

    String? messageEndpoint;
    final buffer = StringBuffer();

    // Create a stream subscription we can control
    final subscription = response
        .transform(utf8.decoder)
        .listen(
          (data) {
            buffer.write(data);
            print(
              'Received: ${data.replaceAll('\n', '\\n').replaceAll('\r', '\\r')}',
            );

            final content = buffer.toString();
            final parts = content.split('\n\n');

            for (var i = 0; i < parts.length - 1; i++) {
              final eventBlock = parts[i];

              String? eventType;
              String? eventData;

              for (final line in eventBlock.split('\n')) {
                if (line.startsWith('event:')) {
                  eventType = line.substring(6).trim();
                } else if (line.startsWith('data:')) {
                  eventData = line.substring(5).trim();
                }
              }

              print('Event: $eventType, Data: $eventData');

              if (eventType == 'endpoint' && eventData != null) {
                messageEndpoint = eventData;
              } else if (eventData != null) {
                print('Response: $eventData');
                try {
                  final json = jsonDecode(eventData);
                  print(
                    'Parsed JSON: ${JsonEncoder.withIndent('  ').convert(json)}',
                  );
                } catch (_) {}
              }
            }

            buffer.clear();
            buffer.write(parts.last);
          },
          onError: (e) => print('Error: $e'),
          onDone: () => print('Stream closed'),
        );

    // Wait for endpoint
    print('Waiting for endpoint...');
    await Future.delayed(Duration(seconds: 2));

    if (messageEndpoint == null) {
      print('No endpoint received!');
      return;
    }

    print('\n=== Message endpoint: $messageEndpoint ===\n');

    // Send initialize
    await sendJsonRpc(messageEndpoint!, 1, 'initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': {},
      'clientInfo': {'name': 'test-client', 'version': '1.0.0'},
    });

    print('Waiting for response...');
    await Future.delayed(Duration(seconds: 3));

    // Send tools/list
    await sendJsonRpc(messageEndpoint!, 2, 'tools/list', {});

    print('Waiting for tools response...');
    await Future.delayed(Duration(seconds: 3));

    await subscription.cancel();
  } catch (e, stackTrace) {
    print('Error: $e');
    print('StackTrace: $stackTrace');
  } finally {
    client.close();
  }
}

Future<void> sendJsonRpc(
  String endpoint,
  int id,
  String method,
  Map<String, dynamic> params,
) async {
  final client = HttpClient();

  try {
    final uri = Uri.parse(endpoint);
    print('\nSending $method to: $uri');

    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;

    final message = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };

    final jsonStr = jsonEncode(message);
    print('Request: $jsonStr');

    request.write(jsonStr);

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    print('Response status: ${response.statusCode}, body: $body');
  } catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
