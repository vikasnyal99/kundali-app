import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';

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
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    onboarded = prefs.getBool('onboarded') ?? false;
    await language(prefs.getString('locale') ?? 'en');
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

  String t(String key) => strings[key]?.toString() ?? key;
  @override
  Widget build(BuildContext context) {
    final primary = locale == 'hi'
        ? const Color(0xff9e4f24)
        : const Color(0xff355c50);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'KundliMilan',
      locale: Locale(locale),
      supportedLocales: const [Locale('en'), Locale('hi')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          primary: primary,
          surface: locale == 'hi'
              ? const Color(0xfffff8ef)
              : const Color(0xfff8f7f2),
        ),
        scaffoldBackgroundColor: locale == 'hi'
            ? const Color(0xfffff8ef)
            : const Color(0xfff8f7f2),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xffe2e7df)),
          ),
        ),
      ),
      home: strings.isEmpty
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : onboarded
          ? Shell(api: api, t: t, locale: locale, onLanguage: language)
          : Scaffold(
              body: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(Icons.auto_awesome, size: 68, color: primary),
                          const SizedBox(height: 24),
                          Text(
                            t('appName'),
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Text(t('tagline'), textAlign: TextAlign.center),
                          const SizedBox(height: 40),
                          Text(
                            t('chooseLanguage'),
                            style: const TextStyle(fontSize: 22),
                          ),
                          const SizedBox(height: 16),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'en',
                                label: Text('English'),
                              ),
                              ButtonSegment(value: 'hi', label: Text('हिन्दी')),
                            ],
                            selected: {locale},
                            onSelectionChanged: (v) => language(v.first),
                          ),
                          const SizedBox(height: 24),
                          Text(t('privacyIntro')),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: () async {
                              final p = await SharedPreferences.getInstance();
                              await p.setBool('onboarded', true);
                              if (mounted) setState(() => onboarded = true);
                            },
                            child: Text(t('continue')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

typedef Translate = String Function(String);

/// Localised message for an API error code; unknown codes stay visible for support.
String describeError(Object e, Translate t) {
  if (e is! ApiException) return t('error');
  final key = 'err_${e.code}';
  final text = t(key);
  return text == key ? '${t('error')} (${e.code})' : text;
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
        setState(() => error = describeError(e, t));
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
  Future<void> editor([Map<String, dynamic>? person]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PersonEditor(api: widget.api, t: widget.t, person: person),
      ),
    );
    if (mounted) await task(reload);
  }

  void matching(bool compare) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MatchFlow(
          api: widget.api,
          t: widget.t,
          locale: widget.locale,
          people: people,
          compare: compare,
        ),
      ),
    ).then((_) {
      if (mounted) task(reload);
    });
  }

  Widget tile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback action,
  ) => Card(
    color: Colors.white,
    elevation: 0,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: action,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            Icon(icon, size: 30, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16),
          ],
        ),
      ),
    ),
  );
  Widget home() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.auto_awesome, color: Color(0xffd5b66d), size: 32),
            const SizedBox(height: 24),
            Text(
              t('tagline'),
              style: const TextStyle(
                fontSize: 30,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              t('comparisonIntro'),
              style: const TextStyle(color: Colors.white70, height: 1.6),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      tile(
        Icons.favorite_border,
        t('match'),
        t('newMatch'),
        () => matching(false),
      ),
      tile(
        Icons.compare_arrows,
        t('compare'),
        t('selectTwo'),
        () => matching(true),
      ),
      tile(
        Icons.people_outline,
        t('people'),
        '${people.length}',
        () => setState(() => tab = 1),
      ),
      tile(
        Icons.description_outlined,
        t('reports'),
        '${reports.length}',
        () => setState(() => tab = 2),
      ),
      const SizedBox(height: 20),
      Text(
        t('disclaimer'),
        style: const TextStyle(
          fontSize: 12,
          color: Colors.black54,
          height: 1.6,
        ),
      ),
    ],
  );
  Widget peoplePage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        onPressed: () => editor(),
        icon: const Icon(Icons.add),
        label: Text(t('addPerson')),
      ),
      const SizedBox(height: 16),
      TextField(
        onChanged: (v) => setState(() => search = v),
        decoration: InputDecoration(
          labelText: t('search'),
          prefixIcon: const Icon(Icons.search),
        ),
      ),
      const SizedBox(height: 16),
      if (people.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 50),
          child: Column(
            children: [
              const Icon(Icons.people_outline, size: 60),
              const SizedBox(height: 20),
              Text(t('emptyPeople'), style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 12),
              Text(t('emptyPeopleBody'), textAlign: TextAlign.center),
            ],
          ),
        ),
      for (final p in people.where(
        (p) => p['display_name'].toString().toLowerCase().contains(
          search.toLowerCase(),
        ),
      ))
        Card(
          color: Colors.white,
          elevation: 0,
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              child: Text(p['display_name'].toString().substring(0, 1)),
            ),
            title: Text(p['display_name']),
            subtitle: Text(
              '${p['birth_date']} · ${p['birth_time_local']}\n${p['birth_place_name']} · ${p['birth_timezone']}',
            ),
            isThreeLine: true,
            onTap: () => editor(Map<String, dynamic>.from(p)),
            trailing: IconButton(
              tooltip: t('delete'),
              icon: const Icon(Icons.delete_outline),
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
        ),
    ],
  );
  Widget reportPage() => Column(
    children: [
      if (reports.isEmpty)
        Padding(
          padding: const EdgeInsets.all(40),
          child: Text(t('emptyReports')),
        ),
      for (final r in reports)
        Card(
          child: ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text('PDF · ${r['locale']}'),
            subtitle: Text(t(r['status'])),
            trailing: IconButton(
              tooltip: t(r['status'] == 'ready' ? 'download' : 'refresh'),
              icon: Icon(
                r['status'] == 'ready' ? Icons.download : Icons.refresh,
              ),
              onPressed: () => task(() async {
                if (r['status'] == 'ready') {
                  final d = await widget.api.request(
                    'POST',
                    '/v1/reports/${r['id']}/download-url',
                  );
                  if (!await launchUrl(
                    Uri.parse(d['url']),
                    mode: LaunchMode.externalApplication,
                  )) {
                    throw Exception();
                  }
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
        ),
    ],
  );
  Widget settingsPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(t('chooseLanguage'), style: const TextStyle(fontSize: 20)),
      const SizedBox(height: 16),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'en', label: Text('English')),
          ButtonSegment(value: 'hi', label: Text('हिन्दी')),
        ],
        selected: {widget.locale},
        onSelectionChanged: (v) => widget.onLanguage(v.first),
      ),
      const SizedBox(height: 28),
      Text(
        t('method'),
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      Text(t('engineInfo')),
      const SizedBox(height: 16),
      Text(t('disclaimer')),
      const SizedBox(height: 16),
      Text(t('sessionNote')),
      const SizedBox(height: 16),
      Text(
        t('placesAttribution'),
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
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
            : t(['home', 'people', 'reports', 'settings'][tab]),
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
          constraints: const BoxConstraints(maxWidth: 680),
          child: RefreshIndicator(
            onRefresh: () => task(reload),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (busy) const LinearProgressIndicator(),
                if (error != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
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
          label: t('home'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.people_outline),
          label: t('people'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.description_outlined),
          label: t('reports'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.settings_outlined),
          label: t('settings'),
        ),
      ],
    ),
  );
}

class PersonEditor extends StatefulWidget {
  final Api api;
  final Translate t;
  final Map<String, dynamic>? person;
  const PersonEditor({
    super.key,
    required this.api,
    required this.t,
    this.person,
  });
  @override
  State<PersonEditor> createState() => _PersonEditorState();
}

String placeLabel(Map<String, dynamic> p) => [
  p['name'],
  p['region'],
  p['country'],
].where((v) => v != null && v.toString().isNotEmpty).join(', ');

class _PersonEditorState extends State<PersonEditor> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  bool consent = false, busy = false;
  String accuracy = 'exact';
  int? fold;
  String? error;
  final labels = {
    'display_name': 'name',
    'birth_date': 'date',
    'birth_time_local': 'time',
    'birth_place_name': 'place',
    'latitude': 'latitude',
    'longitude': 'longitude',
    'birth_timezone': 'timezone',
  };
  @override
  void initState() {
    super.initState();
    for (final key in labels.keys) {
      fields[key] = TextEditingController(
        text:
            widget.person?[key]?.toString() ??
            (key == 'birth_timezone' ? 'Asia/Kolkata' : ''),
      );
    }
    accuracy = widget.person?['time_accuracy'] ?? 'exact';
    fold = widget.person?['fold'];
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate() || !consent) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = <String, dynamic>{
        for (final e in fields.entries) e.key: e.value.text.trim(),
        'time_accuracy': accuracy,
        'fold': fold,
      };
      data['latitude'] = double.parse(data['latitude']);
      data['longitude'] = double.parse(data['longitude']);
      await widget.api.request(
        widget.person == null ? 'POST' : 'PATCH',
        widget.person == null
            ? '/v1/people'
            : '/v1/people/${widget.person!['id']}',
        data,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => error = describeError(e, widget.t));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.t(widget.person == null ? 'addPerson' : 'editPerson')),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(widget.t('manualPlace')),
              const SizedBox(height: 20),
              Autocomplete<Map<String, dynamic>>(
                displayStringForOption: placeLabel,
                optionsBuilder: (value) async {
                  final q = value.text.trim();
                  if (q.length < 2) return const [];
                  try {
                    return List<Map<String, dynamic>>.from(
                      await widget.api.request(
                        'GET',
                        '/v1/places?q=${Uri.encodeQueryComponent(q)}',
                      ),
                    );
                  } catch (_) {
                    return const []; // manual entry still works offline
                  }
                },
                onSelected: (p) => setState(() {
                  fields['birth_place_name']!.text = placeLabel(p);
                  fields['latitude']!.text = '${p['latitude']}';
                  fields['longitude']!.text = '${p['longitude']}';
                  fields['birth_timezone']!.text = p['timezone'];
                }),
                fieldViewBuilder: (context, controller, focus, submit) =>
                    TextField(
                      controller: controller,
                      focusNode: focus,
                      decoration: InputDecoration(
                        labelText: widget.t('placeSearch'),
                        prefixIcon: const Icon(Icons.search),
                      ),
                    ),
              ),
              const SizedBox(height: 16),
              for (final e in labels.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextFormField(
                    controller: fields[e.key],
                    decoration: InputDecoration(labelText: widget.t(e.value)),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return widget.t('required');
                      }
                      if (['latitude', 'longitude'].contains(e.key) &&
                          double.tryParse(v) == null) {
                        return widget.t('required');
                      }
                      return null;
                    },
                  ),
                ),
              DropdownButtonFormField<String>(
                initialValue: accuracy,
                decoration: InputDecoration(labelText: widget.t('precision')),
                items: [
                  for (final v in ['exact', 'approximate', 'unknown'])
                    DropdownMenuItem(value: v, child: Text(widget.t(v))),
                ],
                onChanged: (v) => setState(() => accuracy = v!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: fold ?? -1,
                decoration: InputDecoration(labelText: widget.t('dst')),
                items: [
                  DropdownMenuItem(
                    value: -1,
                    child: Text(widget.t('automatic')),
                  ),
                  DropdownMenuItem(value: 0, child: Text(widget.t('first'))),
                  DropdownMenuItem(value: 1, child: Text(widget.t('second'))),
                ],
                onChanged: (v) => fold = v == -1 ? null : v,
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: consent,
                onChanged: (v) => setState(() => consent = v!),
                title: Text(widget.t('consent')),
              ),
              if (error != null) Text(error!),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy || !consent ? null : save,
                child: Text(widget.t('save')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class MatchFlow extends StatefulWidget {
  final Api api;
  final Translate t;
  final String locale;
  final List<dynamic> people;
  final bool compare;
  const MatchFlow({
    super.key,
    required this.api,
    required this.t,
    required this.locale,
    required this.people,
    required this.compare,
  });
  @override
  State<MatchFlow> createState() => _MatchFlowState();
}

class _MatchFlowState extends State<MatchFlow> {
  late List<dynamic> people;
  String? fixed, second, resultId, error;
  Set<String> candidates = {};
  List<dynamic> results = [];
  bool busy = false, polling = false;
  Timer? timer;
  String t(String k) => widget.t(k);
  @override
  void initState() {
    super.initState();
    people = List.from(widget.people);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> add() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PersonEditor(api: widget.api, t: widget.t),
      ),
    );
    try {
      final p = await widget.api.request('GET', '/v1/people');
      if (mounted) setState(() => people = p);
    } catch (_) {
      if (mounted) setState(() => error = t('error'));
    }
  }

  Future<void> run() async {
    if (fixed == null ||
        (widget.compare ? candidates.length < 2 : second == null)) {
      return;
    }
    timer?.cancel();
    setState(() {
      busy = true;
      error = null;
      results = [];
      resultId = null;
    });
    try {
      final d = await widget.api
          .request('POST', widget.compare ? '/v1/comparisons' : '/v1/matches', {
            'person1_id': fixed,
            if (widget.compare)
              'person2_ids': candidates.toList()
            else
              'person2_id': second,
            'locale': widget.locale,
          });
      if (!mounted) return;
      setState(() {
        resultId = d['id'];
        results = widget.compare ? d['results'] : [d];
      });
      timer = Timer.periodic(const Duration(seconds: 3), (_) => poll());
    } catch (e) {
      if (mounted) {
        setState(() => error = describeError(e, t));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> poll() async {
    if (resultId == null || polling) return;
    polling = true;
    try {
      final d = await widget.api.request(
        'GET',
        widget.compare ? '/v1/comparisons/$resultId' : '/v1/matches/$resultId',
      );
      if (!mounted) return;
      setState(() => results = widget.compare ? d['results'] : [d]);
      if (results.every(
        (m) => m['status'] == 'ready' || m['status'] == 'failed',
      )) {
        timer?.cancel();
      }
    } catch (_) {
      timer?.cancel();
      if (mounted) setState(() => error = t('error'));
    } finally {
      polling = false;
    }
  }

  /// Equal scores are labelled rather than silently ranked apart.
  bool tied(dynamic m) => results.any(
    (o) =>
        !identical(o, m) &&
        o['status'] == 'ready' &&
        o['facts']['score']['earned'] == m['facts']['score']['earned'],
  );

  void resetResults() {
    timer?.cancel();
    resultId = null;
    results = [];
    error = null;
  }

  Widget picker(
    String label,
    String? value,
    void Function(String?) changed, {
    String? exclude,
  }) => DropdownButtonFormField<String>(
    key: ValueKey('$label-$value-${people.length}'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final p in people.where((p) => p['id'] != exclude))
        DropdownMenuItem(
          value: p['id'] as String,
          child: Text(p['display_name'], overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: busy ? null : changed,
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t(widget.compare ? 'compare' : 'match'))),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              t('comparisonIntro'),
              style: const TextStyle(fontSize: 17, height: 1.5),
            ),
            const SizedBox(height: 20),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: picker(
                  t('person1'),
                  fixed,
                  (v) => setState(() {
                    fixed = v;
                    candidates.remove(v);
                    if (second == v) second = null;
                    resetResults();
                  }),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (widget.compare) ...[
              Text(t('selectTwo')),
              for (final p in people.where((p) => p['id'] != fixed))
                CheckboxListTile(
                  value: candidates.contains(p['id']),
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          v!
                              ? candidates.add(p['id'])
                              : candidates.remove(p['id']);
                          resetResults();
                        }),
                  title: Text(p['display_name']),
                  subtitle: Text(p['birth_place_name']),
                ),
            ] else ...[
              picker(
                t('person2'),
                second,
                (v) => setState(() {
                  second = v;
                  resetResults();
                }),
                exclude: fixed,
              ),
              TextButton.icon(
                onPressed: fixed == null || second == null
                    ? null
                    : () => setState(() {
                        final temp = fixed;
                        fixed = second;
                        second = temp;
                        resetResults();
                      }),
                icon: const Icon(Icons.swap_vert),
                label: Text(t('swap')),
              ),
            ],
            OutlinedButton.icon(
              onPressed: busy ? null : add,
              icon: const Icon(Icons.person_add_outlined),
              label: Text(t('addPerson')),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed:
                  busy ||
                      fixed == null ||
                      (widget.compare ? candidates.length < 2 : second == null)
                  ? null
                  : run,
              child: Text(t(widget.compare ? 'runComparison' : 'generate')),
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null) Text(error!),
            const SizedBox(height: 24),
            for (final (i, m) in results.indexed)
              Card(
                color: Colors.white,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(20),
                  title: Text(
                    widget.compare && m['status'] == 'ready'
                        ? '${i + 1}. ${m['people'][1]['display_name']}'
                        : m['people'][1]['display_name'],
                  ),
                  subtitle: Text(
                    m['status'] == 'ready'
                        ? [
                            '${m['facts']['score']['earned']} / 36',
                            if (tied(m)) t('tie'),
                            if ((m['facts']['warnings'] as List).isNotEmpty)
                              t('hasWarnings'),
                          ].join(' · ')
                        : m['failure_code'] == 'calculation_unavailable'
                        ? t('unavailable')
                        : t(m['status']),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MatchDetail(
                            api: widget.api,
                            t: widget.t,
                            locale: widget.locale,
                            match: Map<String, dynamic>.from(m),
                          ),
                        ),
                      ).then((_) {
                        poll();
                      }),
                ),
              ),
            if (results.any(
              (m) => ['pending', 'processing'].contains(m['status']),
            ))
              Text(t('waiting')),
            if (results.isNotEmpty)
              TextButton(onPressed: poll, child: Text(t('refresh'))),
            const SizedBox(height: 20),
            Text(
              t('engineInfo'),
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    ),
  );
}

class MatchDetail extends StatefulWidget {
  final Api api;
  final Translate t;
  final String locale;
  final Map<String, dynamic> match;
  const MatchDetail({
    super.key,
    required this.api,
    required this.t,
    required this.locale,
    required this.match,
  });
  @override
  State<MatchDetail> createState() => _MatchDetailState();
}

class _MatchDetailState extends State<MatchDetail> {
  late Map<String, dynamic> match;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    match = widget.match;
  }

  Future<void> action(Future<void> Function() fn) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => error = describeError(e, widget.t));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final facts = match['facts'];
    return Scaffold(
      appBar: AppBar(title: Text(t('results'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                '${match['people'][0]['display_name']}  &  ${match['people'][1]['display_name']}',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              if (busy) const LinearProgressIndicator(),
              if (error != null) Text(error!),
              if (facts != null) ...[
                Container(
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      Text(t('score')),
                      Text(
                        '${facts['score']['earned']} / 36',
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if ((facts['warnings'] as List).contains(
                  'independent_validation_pending',
                ))
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(t('provisional')),
                    ),
                  ),
                Text(t('breakdown'), style: const TextStyle(fontSize: 22)),
                const SizedBox(height: 12),
                for (final k in facts['score']['kootas'])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(k['key'].toString().replaceAll('_', ' ')),
                    trailing: Text('${k['earned']} / ${k['possible']}'),
                  ),
                const Divider(),
                Text(t('noManglik')),
                const SizedBox(height: 20),
                Text(t('disclaimer')),
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(t('createReport')),
                  onPressed: busy
                      ? null
                      : () => action(() async {
                          final messenger = ScaffoldMessenger.of(context);
                          await widget.api.request(
                            'POST',
                            '/v1/matches/${match['id']}/reports',
                            {'locale': widget.locale},
                          );
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text(t('pending'))),
                            );
                          }
                        }),
                ),
                const SizedBox(height: 20),
                ExpansionTile(
                  title: Text(t('method')),
                  children: [
                    SelectableText(
                      const JsonEncoder.withIndent(
                        '  ',
                      ).convert(facts['calculation']),
                    ),
                  ],
                ),
              ] else ...[
                Icon(
                  match['status'] == 'failed'
                      ? Icons.info_outline
                      : Icons.hourglass_top,
                  size: 50,
                ),
                const SizedBox(height: 20),
                Text(
                  match['failure_code'] == 'calculation_unavailable'
                      ? t('unavailable')
                      : t(match['status']),
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => action(() async {
                          if (match['status'] == 'failed') {
                            await widget.api.request(
                              'POST',
                              '/v1/matches/${match['id']}/retry',
                            );
                          }
                          final d = await widget.api.request(
                            'GET',
                            '/v1/matches/${match['id']}',
                          );
                          if (mounted) {
                            setState(
                              () => match = Map<String, dynamic>.from(d),
                            );
                          }
                        }),
                  child: Text(
                    t(match['status'] == 'failed' ? 'retry' : 'refresh'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
