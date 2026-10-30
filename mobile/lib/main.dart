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

/// First screen: the opening scene with two raised language buttons; choosing one enters the app.
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
  Widget choice(String code, String label) => PrimaryButton(
    label,
    arrow: false,
    ivory: code != locale,
    shine: code == locale,
    onPressed: () => onChoose(code),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Palette.background,
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: BrandScene(
          name: t('appName'),
          tagline: t('appTagline'),
          below: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                children: [
                  Reveal(delay: 460, child: choice('en', 'English')),
                  const SizedBox(height: 16),
                  Reveal(delay: 580, child: choice('hi', 'हिंदी')),
                  const SizedBox(height: 18),
                  Reveal(
                    delay: 720,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xff10301f).withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0x66f3d78e)),
                      ),
                      child: Text(
                        t('footerValues'),
                        style: const TextStyle(
                          color: Color(0xfff8e8c0),
                          fontSize: 13,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ],
        ),
      ),
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode the next screens' artwork early so they appear complete.
    if (Motion.ambient) {
      for (final name in ['home_hero', 'zodiac_wheel', 'lotus', 'night']) {
        precacheImage(AssetImage('assets/images/$name.webp'), context);
      }
    }
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

  /// The portrait of a report's second person, when that person is still saved with one.
  String? reportImage(Map r) {
    final names = r['people'] as List? ?? [];
    if (names.isEmpty) return null;
    for (final p in people) {
      if (p['display_name'] == names.last) return p['avatar'] as String?;
    }
    return null;
  }

  Widget tile(IconData icon, String label, VoidCallback onTap) => Expanded(
    child: AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      child: Column(
        children: [
          Medallion(icon),
          const SizedBox(height: 9),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.25,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );

  /// Edge-to-edge painting that melts into the page, with the headline resting on its misty water.
  Widget hero() => SizedBox(
    height: 408,
    child: Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 300,
          child: ClipRect(
            child: Ambient(
              period: const Duration(seconds: 24),
              reverse: true,
              builder: (_, v) => Transform.scale(
                scale: 1.01 + 0.05 * Curves.easeInOut.transform(v),
                child: const Art(
                  'home_hero',
                  fit: BoxFit.cover,
                  alignment: Alignment(0, -0.35),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 301,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.5, 0.74, 1],
                colors: [
                  Palette.background.withValues(alpha: 0),
                  Palette.background.withValues(alpha: 0),
                  Palette.background.withValues(alpha: 0.82),
                  Palette.background,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 22,
          right: 22,
          bottom: 8,
          child: Column(
            children: [
              Reveal(
                delay: 80,
                child: Text(
                  t('discover'),
                  textAlign: TextAlign.center,
                  style: heading(
                    30,
                    shadows: const [
                      Shadow(color: Color(0xccfffaf0), blurRadius: 12),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Reveal(
                delay: 170,
                child: Text(
                  t('discoverBody'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Palette.muted, height: 1.4),
                ),
              ),
              const SizedBox(height: 18),
              Reveal(
                delay: 260,
                child: PrimaryButton(
                  t('match'),
                  shine: true,
                  onPressed: startMatch,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget home() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      hero(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Reveal(
              delay: 340,
              child: Row(
                children: [
                  tile(
                    Icons.diversity_3_outlined,
                    t('compareShort'),
                    () => open(
                      CompareFlow(
                        api: widget.api,
                        t: widget.t,
                        locale: widget.locale,
                      ),
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
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(child: Text(t('recentReports'), style: heading(18))),
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
            for (final (i, r) in reports.reversed.take(3).indexed)
              Reveal(
                delay: 420 + 70 * i,
                child: ReportRow(
                  names: r['people'] ?? [],
                  score: r['score'],
                  subtitle: reportSubtitle(r),
                  image: reportImage(r),
                  t: widget.t,
                  onTap: () => openReport(r),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              t('disclaimer'),
              style: const TextStyle(
                fontSize: 12,
                color: Palette.muted,
                height: 1.5,
              ),
            ),
          ],
        ),
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
                const Art('state_no_people', height: 180),
                const SizedBox(height: 12),
                Text(t('emptyPeople'), style: heading(19)),
                const SizedBox(height: 8),
                Text(t('emptyPeopleBody'), textAlign: TextAlign.center),
              ],
            ),
          ),
        for (final (i, p)
            in people
                .where(
                  (p) =>
                      p['display_name'].toString().toLowerCase().contains(q) ||
                      p['birth_place_name'].toString().toLowerCase().contains(
                        q,
                      ),
                )
                .indexed)
          Reveal(
            key: ValueKey('person-${p['id']}'),
            delay: 50 * i.clamp(0, 6),
            child: PersonRow(
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
                      await widget.api.request(
                        'DELETE',
                        '/v1/people/${p['id']}',
                      );
                      await reload();
                    });
                  }
                },
              ),
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
              const Art('state_no_reports', height: 180),
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
          image: reportImage(r),
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
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 150,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Art(
                'night',
                fit: BoxFit.cover,
                alignment: Alignment(0, -0.1),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
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
            PillSwitch<String>(
              options: const [('en', 'English'), ('hi', 'हिन्दी')],
              value: widget.locale,
              onChanged: widget.onLanguage,
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
      PrimaryButton(
        t('export'),
        ivory: true,
        arrow: false,
        height: 50,
        icon: Icons.file_download_outlined,
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
      const SizedBox(height: 8),
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

  Widget brandTitle() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Art('mandala', width: 30, height: 30),
      const SizedBox(width: 9),
      Text(t('appName'), style: heading(23, color: Palette.greenDeep)),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: tab == 0
          ? brandTitle()
          : Text(t(['home', 'peopleTab', 'reports', 'settings'][tab])),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(
            child: RoundIconButton(
              icon: Icons.refresh_rounded,
              tooltip: t('refresh'),
              onPressed: busy ? null : () => task(reload),
            ),
          ),
        ),
      ],
    ),
    body: SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: RefreshIndicator(
            onRefresh: () => task(reload),
            child: ListView(
              padding: tab == 0
                  ? const EdgeInsets.only(bottom: 24)
                  : const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(minHeight: 2.5),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
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
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topCenter,
                    children: [...previous, ?current],
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(tab),
                    child: [home, peoplePage, reportPage, settingsPage][tab](),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    bottomNavigationBar: KundliNavBar(
      index: tab,
      onTap: (v) => setState(() => tab = v),
      items: [
        (Icons.home_outlined, Icons.home_rounded, t('home')),
        (Icons.people_outline, Icons.people, t('peopleTab')),
        (Icons.description_outlined, Icons.description, t('reports')),
        (Icons.settings_outlined, Icons.settings, t('settings')),
      ],
    ),
  );
}
