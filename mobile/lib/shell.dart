import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'art.dart';
import 'theme.dart';

/// Native entry point of the Android app: a short animated splash, then the web app (lib/main.dart
/// built with `flutter build web`) in a full-screen WebView, so app changes ship with a server deploy.
/// Build: flutter build apk --release -t lib/shell.dart
const appUrl = String.fromEnvironment(
  'APP_URL',
  defaultValue: 'https://kundaliapi.zivantaai.com/',
);
// Same palette as the web app (theme.dart), so the hand-over from splash to app is seamless.
const cream = Palette.background, maroon = Palette.green;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: cream,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: cream,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'KundliMilan',
      home: ShellScreen(),
    ),
  );
}

/// Links inside the app stay in the WebView; anything else (signed PDF links) opens outside it.
bool isAppLink(Uri url, Uri home) =>
    url.scheme == 'about' || (url.host == home.host && url.port == home.port);

/// JavaScript that stores the native app's earlier guest session where the web app's
/// SharedPreferences reads it: key 'flutter.kundli_handoff', value `jsonEncode(payloadJsonText)`,
/// written as a JS string literal (hence three encodings). Adopted once by lib/main.dart.
String handoffScript(Map<String, Object?> payload) =>
    "localStorage.setItem('flutter.kundli_handoff', ${jsonEncode(jsonEncode(jsonEncode(payload)))});"
    "location.replace('./');";

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});
  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen>
    with SingleTickerProviderStateMixin {
  final home = Uri.parse(appUrl);
  late final intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  late final WebViewController web;
  Map<String, Object?>? handoff;
  bool ready = false, failed = false, introDone = false;
  int attempt = 0;

  @override
  void initState() {
    super.initState();
    intro
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) setState(() => introDone = true);
      })
      ..forward();
    web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(cream)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final url = Uri.parse(request.url);
            if (isAppLink(url, home)) return NavigationDecision.navigate;
            launchUrl(url, mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          },
          onPageFinished: finished,
          onWebResourceError: (e) {
            if (e.isForMainFrame ?? true) setState(() => failed = true);
          },
        ),
      );
    open();
  }

  @override
  void dispose() {
    intro.dispose();
    super.dispose();
  }

  /// Loads the web app, first passing the old native guest session over if it has not been yet.
  Future<void> open() async {
    attempt++;
    setState(() {
      failed = false;
      ready = false;
    });
    final prefs = await SharedPreferences.getInstance();
    final session = await const FlutterSecureStorage().read(key: 'session');
    handoff = session != null && !(prefs.getBool('web_handoff_done') ?? false)
        ? {
            'session': session,
            'locale': prefs.getString('locale'),
            'onboarded': prefs.getBool('onboarded') ?? false,
          }
        : null;
    await web.loadRequest(
      handoff == null ? home : home.resolve('handoff.html'),
    );
  }

  Future<void> finished(String url) async {
    if (failed) return;
    if (handoff != null && Uri.parse(url).path.endsWith('handoff.html')) {
      await web.runJavaScript(handoffScript(handoff!));
      handoff = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('web_handoff_done', true);
      return;
    }
    await waitForFlutter(attempt);
  }

  /// The page finishes loading before Flutter has drawn anything; keep the splash until it has.
  Future<void> waitForFlutter(int forAttempt) async {
    for (var i = 0; i < 100 && mounted && forAttempt == attempt; i++) {
      try {
        final drawn = await web.runJavaScriptReturningResult(
          "document.querySelector('flutter-view, flt-glass-pane') != null",
        );
        if (drawn == true || drawn.toString() == 'true') break;
      } catch (_) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    // A short beat lets the first frame paint before the splash fades.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (mounted && forAttempt == attempt && !failed) {
      setState(() => ready = true);
    }
  }

  /// Back closes the web app's top screen or dialog first; at its home screen it leaves the app.
  Future<void> back() async {
    if (ready && !failed) {
      try {
        final handled = await web.runJavaScriptReturningResult(
          'window.kundliBack ? window.kundliBack() : false',
        );
        if (handled == true || handled.toString() == 'true') return;
      } catch (_) {}
      if (await web.canGoBack()) return web.goBack();
    }
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final showApp = ready && introDone && !failed;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back();
      },
      child: Scaffold(
        backgroundColor: cream,
        body: SafeArea(
          child: Stack(
            children: [
              if (!failed) WebViewWidget(controller: web),
              IgnorePointer(
                ignoring: showApp,
                child: AnimatedOpacity(
                  opacity: showApp ? 0 : 1,
                  duration: const Duration(milliseconds: 450),
                  child: failed
                      ? Offline(onRetry: open)
                      : Splash(intro: intro, waiting: introDone && !ready),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Splash extends StatelessWidget {
  final Animation<double> intro;
  final bool waiting;
  const Splash({super.key, required this.intro, required this.waiting});
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: cream,
    child: Center(
      child: AnimatedBuilder(
        animation: intro,
        builder: (context, _) {
          final text = Curves.easeOut.transform(
            ((intro.value - 0.55) / 0.45).clamp(0, 1),
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: const Size.square(150),
                painter: MandalaPainter(
                  Curves.easeOut.transform((intro.value / 0.75).clamp(0, 1)),
                ),
              ),
              const SizedBox(height: 28),
              Opacity(
                opacity: text,
                child: Transform.translate(
                  offset: Offset(0, 12 * (1 - text)),
                  child: Column(
                    children: [
                      Text('KundliMilan', style: heading(34, color: maroon)),
                      const SizedBox(height: 6),
                      Text(
                        'कुंडली मिलान · Guna Milan',
                        style: heading(15, color: const Color(0xff8a6a3a)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 120,
                height: 3,
                child: waiting
                    ? const LinearProgressIndicator(
                        color: maroon,
                        backgroundColor: Color(0xfff1e2c8),
                      )
                    : null,
              ),
            ],
          );
        },
      ),
    ),
  );
}

class Offline extends StatelessWidget {
  final VoidCallback onRetry;
  const Offline({super.key, required this.onRetry});
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: cream,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 56, color: maroon),
            const SizedBox(height: 20),
            const Text(
              'No internet connection',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'इंटरनेट कनेक्शन नहीं है',
              style: TextStyle(fontSize: 16, color: Color(0xff8a6a52)),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: maroon),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry · फिर प्रयास करें'),
            ),
          ],
        ),
      ),
    ),
  );
}
