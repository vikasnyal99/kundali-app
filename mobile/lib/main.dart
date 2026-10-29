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
              '${displayDate(p['birth_date'])} · ${p['time_accuracy'] == 'unknown' ? t('unknownTime') : displayTime(p['birth_time_local'])}\n${p['birth_place_name']}',
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
            title: Text(
              r['people'] is List
                  ? (r['people'] as List).join(' & ')
                  : 'PDF',
            ),
            subtitle: Text(
              [
                if (r['score'] != null) '${points(r['score'])} / 36',
                r['locale'] == 'hi' ? 'हिन्दी' : 'English',
                r['status'] == 'failed'
                    ? failureText(widget.t, r['failure_code'])
                    : t(r['status']),
              ].join(' · '),
            ),
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
  p['pincode'],
].where((v) => v != null && v.toString().isNotEmpty).join(', ');

/// Stored dates are YYYY-MM-DD; people read them as DD/MM/YYYY.
String displayDate(String iso) {
  final parts = iso.split('-');
  return parts.length == 3 ? '${parts[2]}/${parts[1]}/${parts[0]}' : iso;
}

/// Stored times are 24-hour HH:MM:SS; people read them as h:mm AM/PM.
String displayTime(String value) {
  final parts = value.split(':');
  if (parts.length < 2) return value;
  final h = int.tryParse(parts[0]) ?? 0;
  return '${h % 12 == 0 ? 12 : h % 12}:${parts[1]} ${h < 12 ? 'AM' : 'PM'}';
}

class _PersonEditorState extends State<PersonEditor> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final day = TextEditingController(), month = TextEditingController();
  final year = TextEditingController();
  final hour = TextEditingController(), minute = TextEditingController();
  final focus = List.generate(5, (_) => FocusNode());
  Map<String, dynamic>? place;
  String placeText = '';
  bool consent = false, busy = false, pm = false, askFold = false;
  String accuracy = 'exact';
  int? fold;
  String? error;
  String t(String k) => widget.t(k);

  @override
  void initState() {
    super.initState();
    final p = widget.person;
    if (p == null) return;
    name.text = p['display_name'] ?? '';
    placeText = p['birth_place_name'] ?? '';
    place = {
      'label': placeText,
      'latitude': p['latitude'],
      'longitude': p['longitude'],
      'timezone': p['birth_timezone'],
    };
    final date = (p['birth_date'] ?? '').toString().split('-');
    if (date.length == 3) {
      year.text = date[0];
      month.text = date[1];
      day.text = date[2];
    }
    accuracy = p['time_accuracy'] ?? 'exact';
    final time = (p['birth_time_local'] ?? '').toString().split(':');
    if (accuracy != 'unknown' && time.length >= 2) {
      final h = int.tryParse(time[0]) ?? 0;
      pm = h >= 12;
      hour.text = '${h % 12 == 0 ? 12 : h % 12}'.padLeft(2, '0');
      minute.text = time[1];
    }
    fold = p['fold'];
    askFold = fold != null;
  }

  @override
  void dispose() {
    for (final c in [name, day, month, year, hour, minute]) {
      c.dispose();
    }
    for (final f in focus) {
      f.dispose();
    }
    super.dispose();
  }

  /// The entered date as YYYY-MM-DD, or null if it is not a real past date.
  String? isoDate() {
    final d = int.tryParse(day.text), m = int.tryParse(month.text);
    final y = int.tryParse(year.text);
    if (d == null || m == null || y == null || y < 1800) return null;
    final date = DateTime(y, m, d);
    if (date.year != y || date.month != m || date.day != d) return null;
    if (date.isAfter(DateTime.now())) return null;
    return '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
  }

  /// The entered 12-hour time as 24-hour HH:MM:00, or null if invalid.
  String? isoTime() {
    final h = int.tryParse(hour.text), m = int.tryParse(minute.text);
    if (h == null || m == null || h < 1 || h > 12 || m < 0 || m > 59) {
      return null;
    }
    final h24 = (h % 12) + (pm ? 12 : 0);
    return '${h24.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:00';
  }

  Future<void> save() async {
    if (!form.currentState!.validate() || !consent) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.request(
        widget.person == null ? 'POST' : 'PATCH',
        widget.person == null
            ? '/v1/people'
            : '/v1/people/${widget.person!['id']}',
        {
          'display_name': name.text.trim(),
          'birth_place_name': place!['label'],
          'latitude': place!['latitude'],
          'longitude': place!['longitude'],
          'birth_timezone': place!['timezone'],
          'birth_date': isoDate(),
          'time_accuracy': accuracy,
          if (accuracy != 'unknown') 'birth_time_local': isoTime(),
          'fold': fold,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = describeError(e, widget.t);
        // Only places with daylight saving have a repeated hour; ask only when the server says so.
        if (e is ApiException && e.details.contains('Ambiguous DST')) {
          askFold = true;
          fold ??= 0;
          error = t('dstHelp');
        }
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget label(String text) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  );

  /// One numeric box of a DD / MM / YYYY or HH : MM group; moves on when full.
  Widget box(
    TextEditingController controller,
    int index,
    String hint,
    int length, {
    int flex = 2,
  }) => Expanded(
    flex: flex,
    child: TextFormField(
      controller: controller,
      focusNode: focus[index],
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: length,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(fontSize: 18, letterSpacing: 1),
      decoration: InputDecoration(hintText: hint, counterText: ''),
      onChanged: (v) {
        if (v.length == length && index < 4) {
          focus[index + 1].requestFocus();
        }
        setState(() {});
      },
    ),
  );

  Widget separator(String s) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Text(
      s,
      style: const TextStyle(fontSize: 22, color: Colors.black45),
    ),
  );

  Widget placeField() => Autocomplete<Map<String, dynamic>>(
    initialValue: TextEditingValue(text: placeText),
    displayStringForOption: placeLabel,
    optionsBuilder: (value) async {
      final q = value.text.trim();
      if (q.length < 2 || q == place?['label']) return const [];
      try {
        return List<Map<String, dynamic>>.from(
          await widget.api.request(
            'GET',
            '/v1/places?q=${Uri.encodeQueryComponent(q)}',
          ),
        );
      } catch (_) {
        return const [];
      }
    },
    onSelected: (p) => setState(() {
      placeText = placeLabel(p);
      place = {
        'label': placeText,
        'latitude': p['latitude'],
        'longitude': p['longitude'],
        'timezone': p['timezone'],
      };
    }),
    fieldViewBuilder: (context, controller, focusNode, submit) =>
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            hintText: t('placeSearchHint'),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: place != null
                ? const Icon(Icons.check_circle, color: Colors.green)
                : null,
          ),
          onChanged: (v) {
            // Typing after a choice means a different place: choose again from the list.
            if (place != null && v != place!['label']) {
              setState(() => place = null);
            }
          },
          validator: (_) => place == null ? t('choosePlace') : null,
        ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(t(widget.person == null ? 'addPerson' : 'editPerson')),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              label(t('name')),
              TextFormField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? t('required') : null,
              ),
              label(t('birthPlace')),
              placeField(),
              label(t('precision')),
              SegmentedButton<String>(
                segments: [
                  for (final v in ['exact', 'approximate', 'unknown'])
                    ButtonSegment(value: v, label: Text(t(v))),
                ],
                selected: {accuracy},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => accuracy = v.first),
              ),
              if (accuracy == 'unknown')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    t('unknownTimeNote'),
                    style: const TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                ),
              label(t('birthDate')),
              FormField<void>(
                validator: (_) => isoDate() == null ? t('invalidDate') : null,
                builder: (state) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        box(day, 0, t('dd'), 2),
                        separator('/'),
                        box(month, 1, t('mm'), 2),
                        separator('/'),
                        box(year, 2, t('yyyy'), 4, flex: 3),
                      ],
                    ),
                    if (state.hasError)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 12),
                        child: Text(
                          state.errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (accuracy != 'unknown') ...[
                label(t('birthTime')),
                FormField<void>(
                  validator: (_) => isoTime() == null ? t('invalidTime') : null,
                  builder: (state) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          box(hour, 3, t('hh'), 2),
                          separator(':'),
                          box(minute, 4, t('min'), 2),
                          const SizedBox(width: 12),
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(value: false, label: Text('AM')),
                              ButtonSegment(value: true, label: Text('PM')),
                            ],
                            selected: {pm},
                            showSelectedIcon: false,
                            onSelectionChanged: (v) =>
                                setState(() => pm = v.first),
                          ),
                        ],
                      ),
                      if (state.hasError)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 12),
                          child: Text(
                            state.errorText!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (askFold) ...[
                label(t('dst')),
                DropdownButtonFormField<int>(
                  initialValue: fold ?? 0,
                  items: [
                    DropdownMenuItem(value: 0, child: Text(t('first'))),
                    DropdownMenuItem(value: 1, child: Text(t('second'))),
                  ],
                  onChanged: (v) => fold = v,
                ),
              ],
              const SizedBox(height: 20),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: consent,
                onChanged: (v) => setState(() => consent = v!),
                title: Text(t('consent')),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: busy || !consent ? null : save,
                child: Text(t('save')),
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
  int pollFailures = 0;
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
      // Local calculations come back ready; a single match opens its summary straight away.
      if (!widget.compare && d['status'] == 'ready') {
        open(d);
      } else if (!settled) {
        pollFailures = 0;
        timer = Timer.periodic(const Duration(seconds: 1), (_) => poll());
      }
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
      final wasRunning = timer?.isActive ?? false;
      pollFailures = 0;
      setState(() => results = widget.compare ? d['results'] : [d]);
      if (settled) {
        timer?.cancel();
        if (wasRunning && !widget.compare && d['status'] == 'ready') open(d);
      }
    } catch (_) {
      // Tolerate brief network drops; give up after several in a row.
      if (++pollFailures >= 5) {
        timer?.cancel();
        if (mounted) setState(() => error = t('error'));
      }
    } finally {
      polling = false;
    }
  }

  bool get settled => results.every(
    (m) => m['status'] == 'ready' || m['status'] == 'failed',
  );

  void open(dynamic m) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MatchDetail(
        api: widget.api,
        t: widget.t,
        locale: widget.locale,
        match: Map<String, dynamic>.from(m),
      ),
    ),
  ).then((_) => poll());

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
                        : m['status'] == 'failed'
                        ? failureText(widget.t, m['failure_code'])
                        : t(m['status']),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => open(m),
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

/// Traditional band for a Guna score; the server uses the same thresholds.
String scoreBand(num score) => score >= 33
    ? 'excellent'
    : score >= 25
    ? 'good'
    : score >= 18
    ? 'average'
    : 'low';

/// Localised reason for a failed match or report, falling back to the generic status.
String failureText(Translate t, String? code) {
  if (code == null) return t('failed');
  final text = t('err_$code');
  return text == 'err_$code' ? '${t('failed')} ($code)' : text;
}

String points(num v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';

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
  Map<String, dynamic>? summary, report;
  String? error, summaryError, reportError;
  bool busy = false, loadingSummary = false, reportBusy = false;
  bool openWhenReady = false;
  int reportFailures = 0;
  Timer? reportTimer;
  String t(String k) => widget.t(k);

  @override
  void initState() {
    super.initState();
    match = widget.match;
    if (match['status'] == 'ready') load();
  }

  @override
  void dispose() {
    reportTimer?.cancel();
    super.dispose();
  }

  /// Summary text (AI or template) plus any existing report for this match and language.
  Future<void> load() async {
    setState(() {
      loadingSummary = true;
      summaryError = null;
    });
    findReport();
    try {
      final s = await widget.api.request(
        'GET',
        '/v1/matches/${match['id']}/summary?locale=${widget.locale}',
      );
      if (mounted) setState(() => summary = Map<String, dynamic>.from(s));
    } catch (e) {
      if (mounted) setState(() => summaryError = describeError(e, widget.t));
    } finally {
      if (mounted) setState(() => loadingSummary = false);
    }
  }

  /// An earlier report for this match and language turns the button into Download.
  Future<void> findReport() async {
    try {
      final reports = await widget.api.request('GET', '/v1/reports');
      final existing = (reports as List).where(
        (r) => r['match_id'] == match['id'] && r['locale'] == widget.locale,
      );
      if (existing.isNotEmpty && mounted && report == null) {
        setState(() => report = Map<String, dynamic>.from(existing.first));
        watchReport();
      }
    } catch (_) {
      // Optional: generating a report still works without this lookup.
    }
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

  Future<void> generateReport() async {
    setState(() {
      reportBusy = true;
      reportError = null;
    });
    try {
      final r = await widget.api.request(
        'POST',
        '/v1/matches/${match['id']}/reports',
        {'locale': widget.locale},
      );
      if (!mounted) return;
      setState(() {
        report = Map<String, dynamic>.from(r);
        openWhenReady = true;
      });
      watchReport();
    } catch (e) {
      if (mounted) setState(() => reportError = describeError(e, widget.t));
    } finally {
      if (mounted) setState(() => reportBusy = false);
    }
  }

  /// Polls a pending report; opens it once ready if the user just asked for it.
  void watchReport() {
    reportTimer?.cancel();
    if (!['pending', 'processing'].contains(report?['status'])) return;
    reportFailures = 0;
    reportTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      try {
        final r = await widget.api.request(
          'GET',
          '/v1/reports/${report!['id']}',
        );
        if (!mounted) return;
        setState(() => report = Map<String, dynamic>.from(r));
        if (r['status'] == 'ready' || r['status'] == 'failed') {
          reportTimer?.cancel();
          if (r['status'] == 'ready' && openWhenReady) {
            openWhenReady = false;
            await download();
          }
        }
      } catch (e) {
        // Tolerate brief network drops; stop after repeated failures.
        if (++reportFailures >= 5) {
          reportTimer?.cancel();
          if (mounted) setState(() => reportError = describeError(e, widget.t));
        }
      }
    });
  }

  Future<void> download() async {
    try {
      final d = await widget.api.request(
        'POST',
        '/v1/reports/${report!['id']}/download-url',
      );
      if (!await launchUrl(
        Uri.parse(d['url']),
        mode: LaunchMode.externalApplication,
      )) {
        throw Exception();
      }
    } catch (e) {
      if (mounted) setState(() => reportError = describeError(e, widget.t));
    }
  }

  Widget section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    ),
  );

  Widget scoreCard(Map facts) {
    final score = facts['score']['earned'] as num;
    final primary = Theme.of(context).colorScheme.primary;
    final doshas = [
      for (final k in facts['score']['kootas'])
        if (['nadi', 'bhakoot', 'gana'].contains(k['key']) && k['earned'] == 0)
          k['key'] as String,
    ];
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Text(t('score'), style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: points(score),
                  style: const TextStyle(fontSize: 52, height: 1),
                ),
                const TextSpan(
                  text: ' / 36',
                  style: TextStyle(fontSize: 22, color: Colors.white70),
                ),
              ],
            ),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t('band_${scoreBand(score)}'),
            style: const TextStyle(
              color: Color(0xfff6dfb6),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (score / 36).clamp(0, 1).toDouble(),
              minHeight: 8,
              backgroundColor: Colors.white24,
              color: const Color(0xffd5b66d),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final d in doshas)
                Chip(
                  label: Text(t('dosha_$d')),
                  backgroundColor: const Color(0xfffde7e3),
                  labelStyle: const TextStyle(color: Color(0xff9b2c1f)),
                  side: BorderSide.none,
                ),
              if (doshas.isEmpty)
                Chip(
                  label: Text(t('noDosha')),
                  backgroundColor: const Color(0xffe6f3e6),
                  side: BorderSide.none,
                ),
              Chip(
                label: Text(t('manglikShort')),
                backgroundColor: Colors.white,
                side: BorderSide.none,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget kootaRow(Map k) {
    final earned = k['earned'] as num, possible = k['possible'] as num;
    final colour = earned == possible
        ? const Color(0xff2e6b34)
        : earned == 0
        ? const Color(0xff9b2c1f)
        : const Color(0xff8a5a00);
    final note = (k['note'] ?? '').toString();
    final people = match['people'] as List;
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t('koota_${k['key']}'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colour.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${points(earned)} / ${points(possible)}',
                    style: TextStyle(
                      color: colour,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (k['area'] != null)
              Text(
                k['area'],
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
            if (k['p1'] != null) ...[
              const SizedBox(height: 6),
              Text(
                '${people[0]['display_name']}: ${k['p1']}   ·   ${people[1]['display_name']}: ${k['p2']}',
                style: const TextStyle(fontSize: 13),
              ),
            ],
            if (note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(note, style: const TextStyle(height: 1.45)),
            ],
          ],
        ),
      ),
    );
  }

  Widget bullets(List items, IconData icon, Color colour) => Column(
    children: [
      for (final s in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: colour),
              const SizedBox(width: 10),
              Expanded(
                child: Text(s.toString(), style: const TextStyle(height: 1.4)),
              ),
            ],
          ),
        ),
    ],
  );

  Widget summaryCard() {
    if (loadingSummary && summary == null) {
      return Card(
        color: Colors.white,
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(t('writingSummary'))),
            ],
          ),
        ),
      );
    }
    if (summary == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(summaryError ?? t('error')),
              TextButton(onPressed: load, child: Text(t('retry'))),
            ],
          ),
        ),
      );
    }
    return Card(
      color: Colors.white,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              summary!['headline'],
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            Text(summary!['overview'], style: const TextStyle(height: 1.55)),
          ],
        ),
      ),
    );
  }

  Widget reportSection() {
    final status = report?['status'];
    final working =
        reportBusy || status == 'pending' || status == 'processing';
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('fullReport'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(t('fullReportBody')),
            const SizedBox(height: 16),
            if (working) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 10),
              Text(t('preparingReport'), textAlign: TextAlign.center),
            ] else if (status == 'ready')
              FilledButton.icon(
                icon: const Icon(Icons.download),
                label: Text(t('download')),
                onPressed: download,
              )
            else
              FilledButton.icon(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(t(status == 'failed' ? 'retry' : 'generateReport')),
                onPressed: generateReport,
              ),
            if (status == 'failed')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(failureText(widget.t, report?['failure_code'])),
              ),
            if (reportError != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  reportError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final facts = match['facts'];
    final kootas = summary?['kootas'] ?? facts?['score']['kootas'] ?? [];
    return Scaffold(
      appBar: AppBar(title: Text(t('results'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '${match['people'][0]['display_name']}  &  ${match['people'][1]['display_name']}',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              if (busy) const LinearProgressIndicator(),
              if (error != null) Text(error!),
              if (facts != null) ...[
                scoreCard(facts),
                if ((facts['warnings'] as List).contains(
                  'independent_validation_pending',
                ))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      t('provisional'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                for (final w in [
                  'birth_time_unknown_noon',
                  'unknown_time_moon_changes_that_day',
                ])
                  if ((facts['warnings'] as List).contains(w))
                    Card(
                      color: const Color(0xfffff4e0),
                      elevation: 0,
                      margin: const EdgeInsets.only(top: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.schedule,
                              size: 20,
                              color: Color(0xff8a5a00),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(t('warn_$w'))),
                          ],
                        ),
                      ),
                    ),
                section(t('summaryTitle'), [summaryCard()]),
                section(t('breakdown'), [for (final k in kootas) kootaRow(k)]),
                if ((summary?['strengths'] as List?)?.isNotEmpty ?? false)
                  section(t('strengths'), [
                    bullets(
                      summary!['strengths'],
                      Icons.check_circle_outline,
                      const Color(0xff2e6b34),
                    ),
                  ]),
                if ((summary?['considerations'] as List?)?.isNotEmpty ?? false)
                  section(t('considerations'), [
                    bullets(
                      summary!['considerations'],
                      Icons.info_outline,
                      const Color(0xff8a5a00),
                    ),
                  ]),
                if (summary != null)
                  section(t('guidance'), [
                    Text(summary!['guidance'], style: const TextStyle(height: 1.5)),
                  ]),
                const SizedBox(height: 16),
                Text(
                  t('noManglik'),
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Text(
                  t('disclaimer'),
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                if (summary?['source'] == 'ai') ...[
                  const SizedBox(height: 8),
                  Text(
                    t('aiNote'),
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
                const SizedBox(height: 20),
                reportSection(),
                const SizedBox(height: 12),
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
                  match['status'] == 'failed'
                      ? (match['failure_code'] == 'calculation_unavailable'
                            ? t('unavailable')
                            : failureText(widget.t, match['failure_code']))
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
                            if (match['status'] == 'ready') load();
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
