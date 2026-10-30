import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // Language for the splash artwork: remembered from the web app (see rememberLocale), else the old
  // native app's choice.
  final locale =
      prefs.getString('splash_locale') ?? prefs.getString('locale') ?? 'en';
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: cream,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: cream,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'KundliMilan',
      home: ShellScreen(locale: locale == 'hi' ? 'hi' : 'en'),
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
  final String locale;
  const ShellScreen({super.key, this.locale = 'en'});
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
  late final splashLocale = widget.locale;
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
      rememberLocale();
    }
  }

  /// Keeps the next splash in the language chosen inside the web app.
  Future<void> rememberLocale() async {
    try {
      final value = await web.runJavaScriptReturningResult(
        "localStorage.getItem('flutter.locale') || ''",
      );
      final locale = value.toString().contains('hi') ? 'hi' : 'en';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('splash_locale', locale);
    } catch (_) {}
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
                      : Splash(
                          intro: intro,
                          waiting: introDone && !ready,
                          locale: splashLocale,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The asset pack's splash artwork (wordmark and tagline included) fading in with a slow, gentle zoom.
class Splash extends StatelessWidget {
  final Animation<double> intro;
  final bool waiting;
  final String locale;
  const Splash({
    super.key,
    required this.intro,
    required this.waiting,
    this.locale = 'en',
  });
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: cream,
    child: AnimatedBuilder(
      animation: intro,
      builder: (context, _) {
        final t = Curves.easeOut.transform(intro.value);
        return Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: (intro.value / 0.4).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 1.08 - 0.08 * t,
                child: Image.asset(
                  'assets/images/splash_$locale.jpg',
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
            Align(
              alignment: const Alignment(0, 0.62),
              child: SizedBox(
                width: 120,
                height: 3,
                child: waiting
                    ? const LinearProgressIndicator(
                        color: maroon,
                        backgroundColor: Color(0x66ffffff),
                      )
                    : null,
              ),
            ),
          ],
        );
      },
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
