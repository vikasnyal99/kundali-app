import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'common.dart';
import 'theme.dart';

/// Person form in two steps (Details → Confirm). Order follows the owner's request: name, birthplace
/// (city/town/pincode search), time known?, DD / MM / YYYY, HH : MM AM/PM; coordinates stay hidden.
class PersonEditor extends StatefulWidget {
  final Api api;
  final Translate t;
  final String locale;
  final Map<String, dynamic>? person;
  const PersonEditor({
    super.key,
    required this.api,
    required this.t,
    this.locale = 'en',
    this.person,
  });
  @override
  State<PersonEditor> createState() => _PersonEditorState();
}

class _PersonEditorState extends State<PersonEditor> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final day = TextEditingController(), month = TextEditingController();
  final year = TextEditingController();
  final hour = TextEditingController(), minute = TextEditingController();
  final focus = List.generate(5, (_) => FocusNode());
  Map<String, dynamic>? place;
  String? avatar;
  String placeText = '';
  bool consent = false, busy = false, pm = false, askFold = false;
  bool unknown = false, approximate = false;
  int step = 0;
  int? fold;
  String? error;
  String t(String k) => widget.t(k);
  String get accuracy => unknown
      ? 'unknown'
      : approximate
      ? 'approximate'
      : 'exact';

  @override
  void initState() {
    super.initState();
    final p = widget.person;
    if (p == null) return;
    name.text = p['display_name'] ?? '';
    avatar = p['avatar'];
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
    unknown = p['time_accuracy'] == 'unknown';
    approximate = p['time_accuracy'] == 'approximate';
    final time = (p['birth_time_local'] ?? '').toString().split(':');
    if (!unknown && time.length >= 2) {
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

  void review() {
    if (form.currentState!.validate()) setState(() => step = 1);
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final saved = await widget.api.request(
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
          if (!unknown) 'birth_time_local': isoTime(),
          'fold': fold,
          'avatar': avatar,
        },
      );
      if (mounted) Navigator.pop(context, saved);
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
    child: Text(s, style: const TextStyle(fontSize: 22, color: Palette.muted)),
  );

  Widget errorText(FormFieldState<void> state) => state.hasError
      ? Padding(
          padding: const EdgeInsets.only(top: 6, left: 12),
          child: Text(
            state.errorText!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        )
      : const SizedBox.shrink();

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
    fieldViewBuilder: (context, controller, focusNode, submit) => TextFormField(
      controller: controller,
      focusNode: focusNode,
      decoration: InputDecoration(
        hintText: t('placeSearchHint'),
        prefixIcon: const Icon(Icons.search, color: Palette.muted),
        suffixIcon: place != null
            ? const Icon(Icons.check_circle, color: Palette.green)
            : const Icon(Icons.location_on_outlined, color: Palette.muted),
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

  /// Initials (default) or one of the asset pack's portraits.
  Widget avatarPicker() => Wrap(
    spacing: 12,
    children: [
      for (final choice in [null, ...avatarChoices])
        GestureDetector(
          key: ValueKey('avatar-${choice ?? 'initials'}'),
          onTap: () => setState(() => avatar = choice),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: avatar == choice ? Palette.green : Colors.transparent,
                width: 2.4,
              ),
            ),
            child: Avatar(
              name.text.trim().isEmpty ? '?' : name.text.trim(),
              image: choice,
              size: 50,
            ),
          ),
        ),
    ],
  );

  Widget details() => Form(
    key: form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('basicInfo'), style: heading(17)),
        FieldLabel(t('name')),
        TextFormField(
          controller: name,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          validator: (v) =>
              v == null || v.trim().isEmpty ? t('required') : null,
        ),
        FieldLabel(t('chooseAvatar')),
        avatarPicker(),
        FieldLabel(t('birthPlace')),
        placeField(),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                t('dontKnowTime'),
                style: const TextStyle(color: Palette.muted),
              ),
            ),
            Switch(
              value: unknown,
              onChanged: (v) => setState(() => unknown = v),
            ),
          ],
        ),
        if (unknown)
          Text(
            t('unknownTimeNote'),
            style: const TextStyle(fontSize: 13, color: Palette.muted),
          ),
        FieldLabel(t('birthDate')),
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
              errorText(state),
            ],
          ),
        ),
        if (!unknown) ...[
          FieldLabel(t('birthTime')),
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
                      onSelectionChanged: (v) => setState(() => pm = v.first),
                    ),
                  ],
                ),
                errorText(state),
              ],
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: approximate,
            onChanged: (v) => setState(() => approximate = v!),
            title: Text(t('approximateTime')),
          ),
        ],
        const SizedBox(height: 24),
        PrimaryButton(t('next'), onPressed: review),
      ],
    ),
  );

  Widget confirm() {
    Widget row(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: Palette.gold),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
    final date = isoDate()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Art('kundli_scroll', height: 110),
        const SizedBox(height: 8),
        Text(t('reviewDetails'), style: heading(17)),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Avatar(name.text.trim(), image: avatar),
                  const SizedBox(width: 12),
                  Expanded(child: Text(name.text.trim(), style: heading(18))),
                  TextButton(
                    onPressed: () => setState(() => step = 0),
                    child: Text(t('edit')),
                  ),
                ],
              ),
              row(Icons.location_on_outlined, place!['label'].toString()),
              row(
                Icons.calendar_today_outlined,
                displayDate(date, widget.locale),
              ),
              row(
                Icons.schedule,
                unknown
                    ? t('unknownTime')
                    : '${displayTime(isoTime()!)}${approximate ? ' · ${t('approximate')}' : ''}',
              ),
            ],
          ),
        ),
        if (askFold) ...[
          FieldLabel(t('dst')),
          DropdownButtonFormField<int>(
            initialValue: fold ?? 0,
            items: [
              DropdownMenuItem(value: 0, child: Text(t('first'))),
              DropdownMenuItem(value: 1, child: Text(t('second'))),
            ],
            onChanged: (v) => fold = v,
          ),
        ],
        const SizedBox(height: 12),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: consent,
          onChanged: (v) => setState(() => consent = v!),
          title: Text(t('consent')),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 8),
        PrimaryButton(
          t('save'),
          arrow: false,
          onPressed: busy || !consent ? null : save,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: step == 0,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) setState(() => step = 0);
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(t(widget.person == null ? 'addPerson' : 'editPerson')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              StepIndicator(
                step: step,
                labels: [t('stepDetails'), t('stepConfirm')],
              ),
              const SizedBox(height: 20),
              // Details stay mounted while confirming so going back keeps the entries.
              Offstage(offstage: step != 0, child: details()),
              if (step == 1) confirm(),
            ],
          ),
        ),
      ),
    ),
  );
}

/// "Select Person" list from the design: Saved People / Add New tabs, search, radio selection and a
/// bottom action. Returns the chosen person (or runs [onConfirm] and stays open while it works).
class PickPersonPage extends StatefulWidget {
  final Api api;
  final Translate t;
  final String locale;
  final String title;
  final String action;
  final String? hint, selected, exclude;
  final Future<void> Function(Map person)? onConfirm;
  const PickPersonPage({
    super.key,
    required this.api,
    required this.t,
    required this.locale,
    required this.title,
    required this.action,
    this.hint,
    this.selected,
    this.exclude,
    this.onConfirm,
  });
  @override
  State<PickPersonPage> createState() => _PickPersonPageState();
}

class _PickPersonPageState extends State<PickPersonPage> {
  List people = [];
  String? chosen, error;
  String search = '';
  bool loading = true, busy = false;
  String t(String k) => widget.t(k);

  @override
  void initState() {
    super.initState();
    chosen = widget.selected;
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

  Future<void> addNew() async {
    final saved = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PersonEditor(api: widget.api, t: widget.t, locale: widget.locale),
      ),
    );
    await load();
    if (saved is Map && mounted) setState(() => chosen = saved['id']);
  }

  Future<void> confirm() async {
    final person = people.firstWhere((p) => p['id'] == chosen);
    if (widget.onConfirm == null) return Navigator.pop(context, person);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onConfirm!(person);
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
        .where((p) => p['id'] != widget.exclude)
        .where(
          (p) =>
              p['display_name'].toString().toLowerCase().contains(q) ||
              p['birth_place_name'].toString().toLowerCase().contains(q),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<int>(
                        segments: [
                          ButtonSegment(
                            value: 0,
                            label: Text(t('savedPeopleTab')),
                          ),
                          ButtonSegment(value: 1, label: Text(t('addNewTab'))),
                        ],
                        selected: const {0},
                        showSelectedIcon: false,
                        onSelectionChanged: (v) {
                          if (v.first == 1) addNew();
                        },
                      ),
                    ),
                    if (widget.hint != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          widget.hint!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Palette.muted,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    SearchBox(
                      hint: t('searchHint'),
                      onChanged: (v) => setState(() => search = v),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        children: [
                          if (shown.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  const Art('state_no_people', height: 150),
                                  const SizedBox(height: 8),
                                  Text(
                                    t('noPeopleYet'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Palette.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          for (final p in shown)
                            PersonRow(
                              person: p,
                              t: widget.t,
                              locale: widget.locale,
                              selected: p['id'] == chosen,
                              onTap: () => setState(() => chosen = p['id']),
                              trailing: Icon(
                                p['id'] == chosen
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                color: p['id'] == chosen
                                    ? Palette.green
                                    : Palette.muted,
                              ),
                            ),
                        ],
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
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
                      widget.action,
                      onPressed:
                          busy ||
                              chosen == null ||
                              !shown.any((p) => p['id'] == chosen)
                          ? null
                          : confirm,
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
