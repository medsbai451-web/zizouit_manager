import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Uses an isolated Chrome profile and loopback server; never touches a user's browser data.
Future<void> main() async {
  final root = Directory(Directory('build/web').resolveSymbolicLinksSync());
  if (!File('${root.path}/offline-assets.json').existsSync()) {
    throw StateError(
      'Run tool/prepare_offline.dart after building the web app.',
    );
  }
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    try {
      final relative = request.uri.path == '/'
          ? 'index.html'
          : request.uri.path.substring(1);
      final file = File.fromUri(root.uri.resolve(relative));
      if (!file.absolute.path.startsWith(
            '${root.path}${Platform.pathSeparator}',
          ) ||
          !await file.exists()) {
        request.response.statusCode = 404;
      } else {
        final extension = file.path.split('.').last;
        final mime = {
          'html': 'text/html',
          'js': 'application/javascript',
          'json': 'application/json',
          'wasm': 'application/wasm',
          'png': 'image/png',
          'ttf': 'font/ttf',
          'otf': 'font/otf',
        };
        request.response.headers.contentType = ContentType.parse(
          mime[extension] ?? 'application/octet-stream',
        );
        await request.response.addStream(file.openRead());
      }
    } catch (_) {
      request.response.statusCode = 500;
    } finally {
      await request.response.close();
    }
  });
  final portProbe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final debugPort = portProbe.port;
  await portProbe.close();
  final profile = Directory(
    'build/browser-smoke-${DateTime.now().millisecondsSinceEpoch}',
  ).absolute;
  await profile.create(recursive: true);
  final chrome = await Process.start(
    r'C:\Program Files\Google\Chrome\Application\chrome.exe',
    [
      '--headless=new',
      '--no-first-run',
      '--no-default-browser-check',
      '--remote-debugging-port=$debugPort',
      '--user-data-dir=${profile.path}',
      'about:blank',
    ],
  );
  chrome.stdout.drain<void>();
  chrome.stderr.drain<void>();
  final http = HttpClient();
  WebSocket? socket;
  try {
    List<dynamic>? targets;
    for (var attempt = 0; attempt < 100; attempt++) {
      try {
        final response = await (await http.getUrl(
          Uri.parse('http://127.0.0.1:$debugPort/json/list'),
        )).close();
        targets = jsonDecode(
          await utf8.decoder.bind(response).join(),
        ) as List<dynamic>;
        if (targets.any((t) => t['type'] == 'page')) break;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (targets == null) throw StateError('Chrome DevTools did not start.');
    final target = targets.firstWhere((t) => t['type'] == 'page');
    socket = await WebSocket.connect(target['webSocketDebuggerUrl'] as String);
    final pending = <int, Completer<Map<String, dynamic>>>{};
    var sequence = 0;
    socket.listen((raw) {
      final message = jsonDecode(raw as String) as Map<String, dynamic>;
      if (message['id'] != null) {
        pending.remove(message['id'])?.complete(message);
      }
      if (message['method'] == 'Runtime.exceptionThrown') {
        final details = message['params']['exceptionDetails'];
        stderr.writeln(
          'Browser exception: ${details['exception']?['description'] ?? details['text']}',
        );
      }
      if (message['method'] == 'Log.entryAdded') {
        stderr.writeln('Browser log: ${message['params']['entry']['text']}');
      }
    });
    Future<Map<String, dynamic>> send(
      String method, [
      Map<String, dynamic>? params,
    ]) async {
      final id = ++sequence;
      final completion = Completer<Map<String, dynamic>>();
      pending[id] = completion;
      socket!.add(
        jsonEncode({'id': id, 'method': method, 'params': params ?? {}}),
      );
      final result = await completion.future.timeout(
        const Duration(seconds: 45),
      );
      if (result['error'] != null) throw StateError('${result['error']}');
      return (result['result'] as Map<String, dynamic>?) ?? {};
    }

    Future<dynamic> evaluate(String expression) async {
      final result = await send('Runtime.evaluate', {
        'expression': expression,
        'awaitPromise': true,
        'returnByValue': true,
      });
      if (result['exceptionDetails'] != null) {
        throw StateError('${result['exceptionDetails']}');
      }
      return (result['result'] as Map<String, dynamic>)['value'];
    }

    Future<void> ready() async {
      for (var attempt = 0; attempt < 120; attempt++) {
        try {
          if (await evaluate(
                "!!document.querySelector('flutter-view,flt-glass-pane')",
              ) ==
              true) {
            return;
          }
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      throw StateError('Flutter view did not load.');
    }

    await send('Page.enable');
    await send('Runtime.enable');
    await send('Log.enable');
    await send('Network.enable');
    await send('Emulation.setDeviceMetricsOverride', {
      'width': 1280,
      'height': 900,
      'deviceScaleFactor': 1,
      'mobile': false,
    });
    await send('Page.navigate', {'url': 'http://127.0.0.1:${server.port}/'});
    await ready();
    final worker = await evaluate(
      '(async()=>{const r=await navigator.serviceWorker.ready;return r.active.scriptURL;})()',
    );
    if (!(worker as String).endsWith('zizouit_service_worker.js')) {
      throw StateError('Custom offline worker is not active.');
    }
    await evaluate("localStorage.setItem('zizouit_smoke_marker','saved');");
    stdout.writeln('Online app and offline service worker loaded.');
    await send('Network.emulateNetworkConditions', {
      'offline': true,
      'latency': 0,
      'downloadThroughput': 0,
      'uploadThroughput': 0,
    });
    await send('Page.reload');
    await Future<void>.delayed(const Duration(seconds: 2));
    await ready();
    final retained = await evaluate(
      "localStorage.getItem('zizouit_smoke_marker')",
    );
    if (retained != 'saved') {
      throw StateError('Local browser storage did not survive reload.');
    }
    final screenshot = await send('Page.captureScreenshot', {'format': 'png'});
    await File('build/web-offline-preview.png')
        .writeAsBytes(base64Decode(screenshot['data'] as String));
    stdout.writeln(
      'Offline reload passed; local storage retained; screenshot: build/web-offline-preview.png',
    );
    await send('Network.emulateNetworkConditions', {
      'offline': false,
      'latency': 0,
      'downloadThroughput': -1,
      'uploadThroughput': -1,
    });
    try {
      await send('Browser.close');
    } catch (_) {}
  } finally {
    await socket?.close();
    http.close(force: true);
    await server.close(force: true);
    chrome.kill();
  }
}
