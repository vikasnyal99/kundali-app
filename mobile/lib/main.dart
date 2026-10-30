import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'common.dart';
import 'matching.dart';
import 'people.dart';
import 'theme.dart';
import 'web_bridge.dart';

export 'common.dart' show Translate, describeError, failureText, points;

void main() => runApp(const KundliApp());

class KundliApp extends StatefulWidget {
  final Api? api;
  const KundliApp({super.key, this.api});
  @override
  State<KundliApp> createState() => _KundliAppState();
}

class _KundliAppState extends State<KundliApp> {
  String locale = 'en';
  Map<String, dynamic> strings = {};
  bool onboarded = false;
  late final api = widget.api ?? Api();
  final navigator = GlobalKey<NavigatorState>();
  @override
  void initState() {
    super.initState();
    exposeBack(() {
      final nav = navigator.currentState;
      if (nav == null || !nav.canPop()) return false;
      nav.maybePop();
      return true;
    });
    load();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    await adoptHandoff(prefs);
    onboarded = prefs.getBool('onboarded') ?? false;
    await language(prefs.getString('locale') ?? 'en');
  }

  /// The native shell hands its earlier guest session over once (see lib/shell.dart), so people
  /// saved in the old native app stay reachable from the web app.
  Future<void> adoptHandoff(SharedPreferences prefs) async {
    final raw = prefs.getString('kundli_handoff');
    if (raw == null) return;
    await prefs.remove('kundli_handoff');
    try {
      final h = jsonDecode(raw) as Map<String, dynamic>;
      if (h['session'] is String &&
          await api.storage.read(key: 'session') == null) {
        await api.storage.write(key: 'session', value: h['session']);
      }
      if (h['locale'] is String) await prefs.setString('locale', h['locale']);
      if (h['onboarded'] == true) await prefs.setBool('onboarded', true);
    } catch (_) {
      // A malformed hand-over only means starting with a fresh guest session.
    }
  }

  Future<void> language(String value) async {
    final data =
        jsonDecode(await rootBundle.loadString('lib/l10n/app_$value.arb'))
            as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', value);
    if (mounted) {
      setState(() {
        locale = value;
        strings = data;
      });
    }
  }

  /// Choosing a language on the first screen also finishes onboarding.
  Future<void> begin(String value) async {
    await language(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', true);
    if (mounted) setState(() => onboarded = true);
  }

  String t(String key) => strings[key]?.toString() ?? key;
  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigator,
    debugShowCheckedModeBanner: false,
    title: 'KundliMilan',
    locale: Locale(locale),
    supportedLocales: const [Locale('en'), Locale('hi')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: kundliTheme(),
    home: strings.isEmpty
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : onboarded
        ? Shell(api: api, t: t, locale: locale, onLanguage: language)
        : LanguageScreen(t: t, locale: locale, onChoose: begin),
  );
}

/// First screen: the asset pack's splash artwork for the current language (its wordmark and tagline
/// are part of the image) with real buttons over the river; choosing a language enters the app.
class LanguageScreen extends StatelessWidget {
  final Translate t;
  final String locale;
  final Future<void> Function(String) onChoose;
  const LanguageScreen({
    super.key,
    required this.t,
    required this.locale,
    required this.onChoose,
  });
  Widget choice(String code, String label) {
    final active = code == locale;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: active
          ? PrimaryButton(label, arrow: false, onPressed: () => onChoose(code))
          : OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: Palette.surface.withValues(alpha: 0.94),
                side: const BorderSide(color: Palette.border),
                shape: const StadiumBorder(),
              ),
              onPressed: () => onChoose(code),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Palette.ink,
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Palette.background,
    body: LayoutBuilder(
      builder: (context, size) {
        // Keep the portrait artwork whole: never wider than its own proportions at this height,
        // so the buttons can sit just below the artwork's tagline (which ends about 59% down).
        final width = [
          480.0,
          size.maxHeight * 1074 / 1920,
          size.maxWidth,
        ].reduce((a, b) => a < b ? a : b);
        return Center(
          child: SizedBox(
            width: width,
            height: size.maxHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: Image.asset(
                      'assets/images/splash_$locale.jpg',
                      key: ValueKey(locale),
                      width: width,
                      height: size.maxHeight,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                ),
                Positioned(
                  left: width * 0.11,
                  right: width * 0.11,
                  top: size.maxHeight * 0.62,
                  child: Column(
                    children: [
                      choice('en', 'English'),
                      const SizedBox(height: 12),
                      choice('hi', 'हिंदी'),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Palette.surface.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          t('footerValues'),
                          style: const TextStyle(color: Color(0xff8a6a3a)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class Shell extends StatefulWidget {
  final Api api;
  final Translate t;
  final String locale;
  final Future<void> Function(String) onLanguage;
  const Shell({
    super.key,
    required this.api,
    required this.t,
    required this.locale,
    required this.onLanguage,
  });
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  bool busy = true;
  String? error;
  List<dynamic> people = [], reports = [];
  String search = '';
  String t(String k) => widget.t(k);
  @override
  void initState() {
    super.initState();
    start();
  }

  Future<void> start() async {
    await task(() async {
      await widget.api.init();
      if (widget.api.sessionReplaced && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t('sessionReplaced'))));
      }
      await reload();
    });
  }

  Future<void> reload() async {
    final data = await Future.wait([
      widget.api.request('GET', '/v1/people'),
      widget.api.request('GET', '/v1/reports'),
    ]);
    if (mounted) {
      setState(() {
        people = data[0];
        reports = data[1];
      });
    }
  }

  Future<void> task(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => error = describeError(e, widget.t));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(t('delete')),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) await task(reload);
  }

  Future<void> editor([Map<String, dynamic>? person]) => open(
    PersonEditor(
      api: widget.api,
      t: widget.t,
      locale: widget.locale,
      person: person,
    ),
  );

  /// Match Kundlis: Select Person 1 → Select Person 2 → the detailed report.
  Future<void> startMatch() async {
    Map? first;
    while (true) {
      if (!mounted) return;
      first = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PickPersonPage(
            api: widget.api,
            t: widget.t,
            locale: widget.locale,
            title: t('selectPerson1'),
            action: t('next'),
            hint: t('person1Hint'),
            selected: first?['id'],
          ),
        ),
      );
      if (first == null || !mounted) break;
      final person1 = first;
      final done = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (pageContext) => PickPersonPage(
            api: widget.api,
            t: widget.t,
            locale: widget.locale,
            title: t('selectPerson2'),
            action: t('match'),
            exclude: person1['id'],
            onConfirm: (second) async {
              final m = await widget.api.request('POST', '/v1/matches', {
                'person1_id': person1['id'],
                'person2_id': second['id'],
                'locale': widget.locale,
              });
              if (!pageContext.mounted) return;
              await Navigator.pushReplacement(
                pageContext,
                MaterialPageRoute(
                  builder: (_) => MatchDetail(
                    api: widget.api,
                    t: widget.t,
                    locale: widget.locale,
                    match: Map<String, dynamic>.from(m),
                  ),
                ),
                result: true,
              );
            },
          ),
        ),
      );
      // Back from Person 2 returns to Person 1 with the choice kept.
      if (done == true) break;
    }
    if (mounted) await task(reload);
  }

  Future<void> openReport(Map r) => task(() async {
    final m = await widget.api.request('GET', '/v1/matches/${r['match_id']}');
    if (!mounted) return;
    await open(
      MatchDetail(
        api: widget.api,
        t: widget.t,
        locale: widget.locale,
        match: Map<String, dynamic>.from(m),
      ),
    );
  });

  String reportSubtitle(Map r) => [
    r['locale'] == 'hi' ? 'हिन्दी' : 'English',
    r['status'] == 'failed'
        ? failureText(widget.t, r['failure_code'])
        : t(r['status']),
  ].join(' · ');

  Widget tile(IconData icon, String label, VoidCallback onTap) => Expanded(
    child: AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
      child: Column(
        children: [
          Icon(icon, color: Palette.gold, size: 28),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, height: 1.25),
          ),
        ],
      ),
    ),
  );

  Widget home() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          color: const Color(0xfff7efe2),
          child: Column(
            children: [
              const SizedBox(
                height: 170,
                width: double.infinity,
                child: Art(
                  'home_banner',
                  fit: BoxFit.cover,
                  alignment: Alignment(0, -0.2),
                  on: null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                child: Column(
                  children: [
                    Text(
                      t('discover'),
                      textAlign: TextAlign.center,
                      style: heading(27),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t('discoverBody'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Palette.muted, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    PrimaryButton(t('match'), onPressed: startMatch),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          tile(
            Icons.diversity_3_outlined,
            t('compareShort'),
            () => open(
              CompareFlow(api: widget.api, t: widget.t, locale: widget.locale),
            ),
          ),
          const SizedBox(width: 10),
          tile(
            Icons.person_outline,
            t('savedShort'),
            () => setState(() => tab = 1),
          ),
          const SizedBox(width: 10),
          tile(
            Icons.description_outlined,
            t('previousReports'),
            () => setState(() => tab = 2),
          ),
        ],
      ),
      const SizedBox(height: 22),
      Row(
        children: [
          Expanded(child: Text(t('recentReports'), style: heading(17))),
          TextButton(
            onPressed: () => setState(() => tab = 2),
            child: Text(t('viewAll')),
          ),
        ],
      ),
      if (reports.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            t('emptyReports'),
            style: const TextStyle(color: Palette.muted),
          ),
        ),
      for (final r in reports.reversed.take(3))
        ReportRow(
          names: r['people'] ?? [],
          score: r['score'],
          subtitle: reportSubtitle(r),
          t: widget.t,
          onTap: () => openReport(r),
        ),
      const SizedBox(height: 16),
      Text(
        t('disclaimer'),
        style: const TextStyle(fontSize: 12, color: Palette.muted, height: 1.5),
      ),
    ],
  );

  Widget peoplePage() {
    final q = search.toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(
          t('addPerson'),
          arrow: false,
          icon: Icons.add,
          onPressed: () => editor(),
        ),
        const SizedBox(height: 14),
        SearchBox(
          hint: t('searchHint'),
          onChanged: (v) => setState(() => search = v),
        ),
        const SizedBox(height: 14),
        if (people.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                const Art('state_no_people', height: 170),
                const SizedBox(height: 12),
                Text(t('emptyPeople'), style: heading(19)),
                const SizedBox(height: 8),
                Text(t('emptyPeopleBody'), textAlign: TextAlign.center),
              ],
            ),
          ),
        for (final p in people.where(
          (p) =>
              p['display_name'].toString().toLowerCase().contains(q) ||
              p['birth_place_name'].toString().toLowerCase().contains(q),
        ))
          PersonRow(
            person: p,
            t: widget.t,
            locale: widget.locale,
            withTime: true,
            onTap: () => editor(Map<String, dynamic>.from(p)),
            trailing: IconButton(
              tooltip: t('delete'),
              icon: const Icon(Icons.delete_outline, color: Palette.muted),
              onPressed: () async {
                if (await confirm(t('confirmDelete'))) {
                  await task(() async {
                    await widget.api.request('DELETE', '/v1/people/${p['id']}');
                    await reload();
                  });
                }
              },
            ),
          ),
      ],
    );
  }

  Widget reportPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (reports.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 30),
          child: Column(
            children: [
              const Art('state_no_reports', height: 170),
              const SizedBox(height: 12),
              Text(t('emptyReports'), textAlign: TextAlign.center),
            ],
          ),
        ),
      for (final r in reports.reversed)
        ReportRow(
          names: r['people'] ?? [],
          score: r['score'],
          subtitle: reportSubtitle(r),
          t: widget.t,
          onTap: () => openReport(r),
          trailing: IconButton(
            tooltip: t(r['status'] == 'ready' ? 'download' : 'refresh'),
            icon: Icon(
              r['status'] == 'ready' ? Icons.download : Icons.refresh,
              color: Palette.green,
            ),
            onPressed: () => task(() async {
              if (r['status'] == 'ready') {
                final d = await widget.api.request(
                  'POST',
                  '/v1/reports/${r['id']}/download-url',
                );
                if (!await openPdf(d['url'])) throw Exception();
              } else if (r['status'] == 'failed') {
                await widget.api.request(
                  'POST',
                  '/v1/matches/${r['match_id']}/reports',
                  {'locale': r['locale']},
                );
              }
              await reload();
            }),
          ),
        ),
    ],
  );

  Widget settingsPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: 130,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Art('settings_banner', fit: BoxFit.cover, on: null),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(t('appName'), style: heading(24, color: Colors.white)),
                    Text(
                      t('appTagline').replaceAll('\n', ' '),
                      style: const TextStyle(color: Color(0xfff2e3c2)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('chooseLanguage'), style: heading(17)),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'en', label: Text('English')),
                ButtonSegment(value: 'hi', label: Text('हिन्दी')),
              ],
              selected: {widget.locale},
              showSelectedIcon: false,
              onSelectionChanged: (v) => widget.onLanguage(v.first),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('method'), style: heading(17)),
            const SizedBox(height: 10),
            Text(t('engineInfo'), style: const TextStyle(height: 1.45)),
            const SizedBox(height: 12),
            Text(t('disclaimer'), style: const TextStyle(height: 1.45)),
            const SizedBox(height: 12),
            Text(t('sessionNote'), style: const TextStyle(height: 1.45)),
            const SizedBox(height: 12),
            Text(
              t('placesAttribution'),
              style: const TextStyle(fontSize: 12, color: Palette.muted),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          minimumSize: const Size.fromHeight(48),
        ),
        icon: const Icon(Icons.file_download_outlined),
        label: Text(t('export')),
        onPressed: () => task(() async {
          final data = await widget.api.request('GET', '/v1/me/export');
          if (!mounted) return;
          await showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
              title: Text(t('export')),
              content: SingleChildScrollView(
                child: SelectableText(
                  const JsonEncoder.withIndent('  ').convert(data),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: Text(t('back')),
                ),
              ],
            ),
          );
        }),
      ),
      TextButton(
        onPressed: () async {
          if (await confirm(t('eraseConfirm'))) {
            await task(() async {
              await widget.api.request('DELETE', '/v1/me');
              await widget.api.storage.delete(key: 'session');
              await widget.api.newSession();
              await reload();
            });
          }
        },
        child: Text(t('erase'), style: const TextStyle(color: Colors.red)),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        tab == 0
            ? t('appName')
            : t(['home', 'peopleTab', 'reports', 'settings'][tab]),
        style: heading(
          tab == 0 ? 22 : 19,
          color: tab == 0 ? Palette.green : Palette.ink,
        ),
      ),
      actions: [
        IconButton(
          tooltip: t('refresh'),
          onPressed: busy ? null : () => task(reload),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: RefreshIndicator(
            onRefresh: () => task(reload),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppCard(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Column(
                        children: [
                          Text(error!),
                          TextButton(onPressed: start, child: Text(t('retry'))),
                        ],
                      ),
                    ),
                  ),
                [home, peoplePage, reportPage, settingsPage][tab](),
              ],
            ),
          ),
        ),
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (v) => setState(() => tab = v),
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home),
          label: t('home'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.people_outline),
          selectedIcon: const Icon(Icons.people),
          label: t('peopleTab'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.description_outlined),
          selectedIcon: const Icon(Icons.description),
          label: t('reports'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.settings_outlined),
          selectedIcon: const Icon(Icons.settings),
          label: t('settings'),
        ),
      ],
    ),
  );
}
