import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'api.dart';
import 'art.dart';
import 'common.dart';
import 'people.dart';
import 'theme.dart';

/// "Compare Multiple": Person 1 stays fixed; tick candidates, then see them ranked.
class CompareFlow extends StatefulWidget {
  final Api api;
  final Translate t;
  final String locale;
  const CompareFlow({
    super.key,
    required this.api,
    required this.t,
    required this.locale,
  });
  @override
  State<CompareFlow> createState() => _CompareFlowState();
}

class _CompareFlowState extends State<CompareFlow> {
  List people = [];
  Map? fixed;
  final candidates = <String>{};
  String search = '';
  String? error;
  bool loading = true, busy = false;
  String t(String k) => widget.t(k);

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final p = await widget.api.request('GET', '/v1/people');
      if (mounted) setState(() => people = p);
    } catch (e) {
      if (mounted) setState(() => error = describeError(e, widget.t));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> chooseFixed() async {
    final p = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PickPersonPage(
          api: widget.api,
          t: widget.t,
          locale: widget.locale,
          title: t('choosePerson1'),
          action: t('next'),
          hint: t('person1Hint'),
          selected: fixed?['id'],
        ),
      ),
    );
    await load();
    if (p is Map && mounted) {
      setState(() {
        fixed = p;
        candidates.remove(p['id']);
      });
    }
  }

  Future<void> run() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final d = await widget.api.request('POST', '/v1/comparisons', {
        'person1_id': fixed!['id'],
        'person2_ids': candidates.toList(),
        'locale': widget.locale,
      });
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ComparisonResults(
            api: widget.api,
            t: widget.t,
            locale: widget.locale,
            fixed: fixed!,
            comparison: Map<String, dynamic>.from(d),
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = describeError(e, widget.t));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = search.toLowerCase();
    final shown = people
        .where((p) => p['id'] != fixed?['id'])
        .where(
          (p) =>
              p['display_name'].toString().toLowerCase().contains(q) ||
              p['birth_place_name'].toString().toLowerCase().contains(q),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(t('compareTitle'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  children: [
                    if (fixed == null)
                      AppCard(
                        onTap: chooseFixed,
                        color: Palette.goldSoft,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.person_add_alt_1_outlined,
                              color: Palette.gold,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                t('choosePerson1'),
                                style: heading(16),
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      )
                    else
                      FixedPersonCard(
                        person: fixed!,
                        t: widget.t,
                        locale: widget.locale,
                        onEdit: chooseFixed,
                      ),
                    const SizedBox(height: 20),
                    Text(t('selectCandidates'), style: heading(16)),
                    const SizedBox(height: 10),
                    SearchBox(
                      hint: t('searchHint'),
                      onChanged: (v) => setState(() => search = v),
                    ),
                    const SizedBox(height: 12),
                    if (loading) const LinearProgressIndicator(),
                    for (final p in shown)
                      PersonRow(
                        key: ValueKey('candidate-${p['id']}'),
                        person: p,
                        t: widget.t,
                        locale: widget.locale,
                        selected: candidates.contains(p['id']),
                        onTap: () => setState(
                          () => candidates.contains(p['id'])
                              ? candidates.remove(p['id'])
                              : candidates.add(p['id']),
                        ),
                        trailing: Checkbox(
                          value: candidates.contains(p['id']),
                          onChanged: (v) => setState(
                            () => v!
                                ? candidates.add(p['id'])
                                : candidates.remove(p['id']),
                          ),
                        ),
                      ),
                    TextButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PersonEditor(
                              api: widget.api,
                              t: widget.t,
                              locale: widget.locale,
                            ),
                          ),
                        );
                        await load();
                      },
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: Text(t('addPerson')),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  children: [
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (busy)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: LinearProgressIndicator(),
                      ),
                    PrimaryButton(
                      t(
                        'compareSelected',
                      ).replaceAll('{n}', '${candidates.length}'),
                      onPressed: busy || fixed == null || candidates.length < 2
                          ? null
                          : run,
                    ),
                    if (fixed != null && candidates.length < 2)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          t('selectTwo'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Palette.muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FixedPersonCard extends StatelessWidget {
  final Map person;
  final Translate t;
  final String locale;
  final VoidCallback? onEdit;
  const FixedPersonCard({
    super.key,
    required this.person,
    required this.t,
    required this.locale,
    this.onEdit,
  });
  @override
  Widget build(BuildContext context) => AppCard(
    color: const Color(0xfff1e9da),
    child: Row(
      children: [
        Avatar(person['display_name'].toString(), size: 52),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('person1Fixed'),
                style: const TextStyle(fontSize: 12.5, color: Palette.muted),
              ),
              Text(person['display_name'].toString(), style: heading(17)),
              Text(
                personLine(person, t, locale),
                style: const TextStyle(fontSize: 12.5, color: Palette.muted),
              ),
            ],
          ),
        ),
        if (onEdit != null)
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Palette.greenSoft,
              foregroundColor: Palette.green,
            ),
            onPressed: onEdit,
            child: Text(t('edit')),
          ),
      ],
    ),
  );
}

/// Ranked candidates (server order: score, then name), with verdict chips as in the design.
class ComparisonResults extends StatefulWidget {
  final Api api;
  final Translate t;
  final String locale;
  final Map fixed;
  final Map<String, dynamic> comparison;
  const ComparisonResults({
    super.key,
    required this.api,
    required this.t,
    required this.locale,
    required this.fixed,
    required this.comparison,
  });
  @override
  State<ComparisonResults> createState() => _ComparisonResultsState();
}

class _ComparisonResultsState extends State<ComparisonResults> {
  late List results = widget.comparison['results'];
  Timer? timer;
  int failures = 0;
  String t(String k) => widget.t(k);

  bool get settled =>
      results.every((m) => m['status'] == 'ready' || m['status'] == 'failed');

  @override
  void initState() {
    super.initState();
    // The live server returns ready results; poll only for queued (provider) calculations.
    if (!settled) {
      timer = Timer.periodic(const Duration(seconds: 1), (_) => poll());
    } else {
      poll();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> poll() async {
    try {
      final d = await widget.api.request(
        'GET',
        '/v1/comparisons/${widget.comparison['id']}',
      );
      failures = 0;
      if (!mounted) return;
      setState(() => results = d['results']);
      if (settled) timer?.cancel();
    } catch (_) {
      if (++failures >= 5) timer?.cancel();
    }
  }

  /// Warnings about this pair (approximate or unknown time, boundary Moon); the engine's standing
  /// "experimental" labels apply to every result and are shown on the report instead.
  Iterable pairWarnings(List warnings) => warnings.where(
    (w) =>
        !['experimental_engine', 'independent_validation_pending'].contains(w),
  );

  /// Equal scores are labelled rather than silently ranked apart.
  bool tied(Map m) => results.any(
    (o) =>
        !identical(o, m) &&
        o['status'] == 'ready' &&
        o['facts']['score']['earned'] == m['facts']['score']['earned'],
  );

  Widget card(int rank, Map m) {
    final p2 = m['people'][1] as Map;
    final ready = m['status'] == 'ready';
    final score = ready ? m['facts']['score']['earned'] as num : null;
    final first = rank == 1 && ready;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        color: first ? Palette.goldSoft : Palette.surface,
        borderColor: first ? Palette.gold : Palette.border,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MatchDetail(
              api: widget.api,
              t: widget.t,
              locale: widget.locale,
              match: Map<String, dynamic>.from(m),
            ),
          ),
        ).then((_) => poll()),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: first
                    ? Palette.gold
                    : ready
                    ? const Color(0xffe9e2d3)
                    : Colors.transparent,
              ),
              child: Text(
                ready ? '$rank' : '–',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: first ? Colors.white : Palette.ink,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Avatar(p2['display_name'].toString()),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p2['display_name'].toString(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15.5,
                    ),
                  ),
                  Text(
                    personLine(p2, widget.t, widget.locale),
                    style: const TextStyle(
                      color: Palette.muted,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (ready)
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        BandChip(
                          scoreBand(score!),
                          t('band_${scoreBand(score)}'),
                        ),
                        if (tied(m))
                          Text(
                            t('tie'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Palette.muted,
                            ),
                          ),
                        if (pairWarnings(m['facts']['warnings']).isNotEmpty)
                          Text(
                            t('hasWarnings'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Palette.muted,
                            ),
                          ),
                      ],
                    )
                  else
                    Text(
                      m['status'] == 'failed'
                          ? failureText(widget.t, m['failure_code'])
                          : t(m['status']),
                      style: const TextStyle(fontSize: 12.5),
                    ),
                ],
              ),
            ),
            if (ready)
              Text(
                '${points(score!)}/36',
                style: heading(17, color: Palette.green),
              ),
            const Icon(Icons.chevron_right, color: Palette.muted),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('compareTitle'))),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            FixedPersonCard(
              person: widget.fixed,
              t: widget.t,
              locale: widget.locale,
            ),
            const SizedBox(height: 20),
            Text(t('compatibilityWith'), style: heading(16)),
            const SizedBox(height: 12),
            for (final (i, m) in results.indexed) card(i + 1, m),
            if (!settled) Text(t('waiting')),
          ],
        ),
      ),
    ),
  );
}

/// The design's "Detailed Report": couple header, Summary / Guna / Doshas / Remedies tabs, and the
/// full PDF report at the end.
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
  int tab = 0, reportFailures = 0, matchFailures = 0;
  Timer? reportTimer, matchTimer;
  String t(String k) => widget.t(k);

  @override
  void initState() {
    super.initState();
    match = widget.match;
    if (match['status'] == 'ready') {
      load();
    } else if (match['status'] != 'failed') {
      matchTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => refreshMatch(),
      );
    }
  }

  @override
  void dispose() {
    reportTimer?.cancel();
    matchTimer?.cancel();
    super.dispose();
  }

  Future<void> refreshMatch() async {
    try {
      final d = await widget.api.request('GET', '/v1/matches/${match['id']}');
      matchFailures = 0;
      if (!mounted) return;
      setState(() => match = Map<String, dynamic>.from(d));
      if (d['status'] == 'ready' || d['status'] == 'failed') {
        matchTimer?.cancel();
        if (d['status'] == 'ready') load();
      }
    } catch (_) {
      if (++matchFailures >= 5) matchTimer?.cancel();
    }
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

  Future<void> retry() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (match['status'] == 'failed') {
        await widget.api.request('POST', '/v1/matches/${match['id']}/retry');
      }
      await refreshMatch();
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
      if (!await openPdf(d['url'])) throw Exception();
    } catch (e) {
      if (mounted) setState(() => reportError = describeError(e, widget.t));
    }
  }

  Widget couple() {
    final people = match['people'] as List;
    Widget one(Map p) => Column(
      children: [
        Avatar(p['display_name'].toString(), size: 60),
        const SizedBox(height: 6),
        Text(
          firstName(p['display_name']),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        one(people[0]),
        const Padding(
          padding: EdgeInsets.fromLTRB(22, 0, 22, 22),
          child: Icon(Icons.favorite, color: Color(0xffe05a4f), size: 26),
        ),
        one(people[1]),
      ],
    );
  }

  Widget tabs() {
    final labels = ['tabSummary', 'tabGuna', 'tabDoshas', 'tabRemedies'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xffefe7d8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final (i, key) in labels.indexed)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: tab == i ? Palette.green : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    t(key),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: tab == i ? Colors.white : Palette.ink,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget listCard(String title, IconData icon, Color colour, List items) =>
      Padding(
        padding: const EdgeInsets.only(top: 14),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: colour.withValues(alpha: 0.15),
                    child: Icon(icon, size: 17, color: colour),
                  ),
                  const SizedBox(width: 10),
                  Text(title, style: heading(16)),
                ],
              ),
              const SizedBox(height: 8),
              for (final s in items)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        icon == Icons.spa_outlined
                            ? Icons.check_circle
                            : Icons.info,
                        size: 19,
                        color: colour,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s.toString(),
                          style: const TextStyle(height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );

  Widget summaryTab(Map facts) {
    final score = facts['score']['earned'] as num;
    final band = scoreBand(score);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        Text(
          t('compatibilityScore'),
          textAlign: TextAlign.center,
          style: heading(18),
        ),
        const SizedBox(height: 12),
        Center(
          child: SizedBox(
            width: 230,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ScoreRing(score: score, caption: t('outOf36')),
                const Positioned(right: 0, top: 18, child: LotusIcon()),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(child: BandChip(band, t('band_$band'))),
        for (final w in [
          'birth_time_unknown_noon',
          'unknown_time_moon_changes_that_day',
        ])
          if ((facts['warnings'] as List).contains(w))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: AppCard(
                color: const Color(0xfffff4e0),
                padding: const EdgeInsets.all(12),
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
        const SizedBox(height: 16),
        if (loadingSummary && summary == null)
          Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(t('writingSummary'))),
            ],
          )
        else if (summary == null)
          Column(
            children: [
              Text(summaryError ?? t('error')),
              TextButton(onPressed: load, child: Text(t('retry'))),
            ],
          )
        else ...[
          Text(summary!['headline'], style: heading(16, color: Palette.green)),
          const SizedBox(height: 6),
          Text(
            summary!['overview'],
            style: const TextStyle(height: 1.55, color: Palette.ink),
          ),
          if ((summary!['strengths'] as List).isNotEmpty)
            listCard(
              t('keyStrengths'),
              Icons.spa_outlined,
              Palette.green,
              summary!['strengths'],
            ),
          if ((summary!['considerations'] as List).isNotEmpty)
            listCard(
              t('considerations'),
              Icons.info_outline,
              const Color(0xff8a5a00),
              summary!['considerations'],
            ),
        ],
        if ((facts['warnings'] as List).contains(
          'independent_validation_pending',
        ))
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              t('provisional'),
              style: const TextStyle(fontSize: 12, color: Palette.muted),
            ),
          ),
      ],
    );
  }

  Widget kootaRow(Map k) {
    final earned = k['earned'] as num, possible = k['possible'] as num;
    final colour = earned == possible
        ? const Color(0xff2e6b34)
        : earned == 0
        ? const Color(0xffa23b2a)
        : const Color(0xff8a5a00);
    final note = (k['note'] ?? '').toString();
    final people = match['people'] as List;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(t('koota_${k['key']}'), style: heading(16)),
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
                style: const TextStyle(color: Palette.muted, fontSize: 13),
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

  Widget gunaTab(Map facts) {
    final kootas = summary?['kootas'] ?? facts['score']['kootas'] ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(t('breakdown'), style: heading(17)),
        const SizedBox(height: 10),
        for (final k in kootas) kootaRow(k),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(t('method')),
          children: [
            SelectableText(
              const JsonEncoder.withIndent('  ').convert(facts['calculation']),
            ),
          ],
        ),
      ],
    );
  }

  Widget doshaTab(Map facts) {
    final rows = {
      for (final k in facts['score']['kootas']) k['key']: k['earned'] as num,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        for (final d in ['nadi', 'bhakoot', 'gana'])
          if (rows.containsKey(d))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(t('dosha_$d'), style: heading(16)),
                        ),
                        BandChip(
                          rows[d] == 0 ? 'low' : 'excellent',
                          t(rows[d] == 0 ? 'doshaPresent' : 'doshaAbsent'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t('doshaInfo_$d'),
                      style: const TextStyle(color: Palette.muted, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
        AppCard(
          child: Row(
            children: [
              const Icon(Icons.help_outline, color: Palette.muted),
              const SizedBox(width: 10),
              Expanded(child: Text(t('noManglik'))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          t('pariharNote'),
          style: const TextStyle(fontSize: 13, color: Palette.muted),
        ),
      ],
    );
  }

  Widget remediesTab() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 16),
      if (summary != null)
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t('remediesTitle'), style: heading(16)),
              const SizedBox(height: 8),
              Text(summary!['guidance'], style: const TextStyle(height: 1.5)),
            ],
          ),
        ),
      const SizedBox(height: 12),
      AppCard(
        color: Palette.goldSoft,
        child: Text(t('remediesNote'), style: const TextStyle(height: 1.45)),
      ),
      const SizedBox(height: 12),
      Text(
        t('disclaimer'),
        style: const TextStyle(fontSize: 12, color: Palette.muted),
      ),
      if (summary?['source'] == 'ai')
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            t('aiNote'),
            style: const TextStyle(fontSize: 12, color: Palette.muted),
          ),
        ),
    ],
  );

  Widget reportSection() {
    final status = report?['status'];
    final working = reportBusy || status == 'pending' || status == 'processing';
    return AppCard(
      color: Palette.greenSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('fullReport'), style: heading(17)),
          const SizedBox(height: 6),
          Text(t('fullReportBody')),
          const SizedBox(height: 16),
          if (working) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 10),
            Text(t('preparingReport'), textAlign: TextAlign.center),
          ] else if (status == 'ready')
            PrimaryButton(
              t('download'),
              arrow: false,
              icon: Icons.download,
              onPressed: download,
            )
          else
            PrimaryButton(
              t(status == 'failed' ? 'retry' : 'generateReport'),
              arrow: false,
              icon: Icons.picture_as_pdf_outlined,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final facts = match['facts'];
    return Scaffold(
      appBar: AppBar(
        title: Text(t('detailedReport')),
        actions: [
          if (facts != null)
            IconButton(
              tooltip: t('download'),
              icon: const Icon(Icons.file_download_outlined),
              onPressed: report?['status'] == 'ready'
                  ? download
                  : generateReport,
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              couple(),
              const SizedBox(height: 16),
              if (busy) const LinearProgressIndicator(),
              if (error != null) Text(error!),
              if (facts != null) ...[
                tabs(),
                [
                  summaryTab(facts),
                  gunaTab(facts),
                  doshaTab(facts),
                  remediesTab(),
                ][tab],
                const SizedBox(height: 20),
                reportSection(),
              ] else ...[
                const SizedBox(height: 30),
                Icon(
                  match['status'] == 'failed'
                      ? Icons.info_outline
                      : Icons.hourglass_top,
                  size: 50,
                  color: Palette.gold,
                ),
                const SizedBox(height: 16),
                Text(
                  match['status'] == 'failed'
                      ? (match['failure_code'] == 'calculation_unavailable'
                            ? t('unavailable')
                            : failureText(widget.t, match['failure_code']))
                      : t(match['status']),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  t(match['status'] == 'failed' ? 'retry' : 'refresh'),
                  arrow: false,
                  onPressed: busy ? null : retry,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
