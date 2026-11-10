import 'package:flutter/material.dart';
import 'api.dart';
import 'common.dart';
import 'people.dart';
import 'theme.dart';

/// The match flow's single, two-person picker. Candidate comparison still uses PickPersonPage.
class PairPickerPage extends StatefulWidget {
  final Api api;
  final Translate t;
  final String locale;
  final Future<void> Function(Map first, Map second) onConfirm;
  const PairPickerPage({
    super.key,
    required this.api,
    required this.t,
    required this.locale,
    required this.onConfirm,
  });

  @override
  State<PairPickerPage> createState() => _PairPickerPageState();
}

class _PairPickerPageState extends State<PairPickerPage> {
  List people = [];
  String? firstId, secondId, error;
  bool loading = true, busy = false;
  String t(String key) => widget.t(key);

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await widget.api.request('GET', '/v1/people');
      if (mounted) {
        setState(() {
          people = result;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = describeError(e, widget.t));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Map? selected(String? id) {
    for (final person in people) {
      if (person['id'] == id) return person;
    }
    return null;
  }

  Future<void> addPerson(bool first) async {
    final saved = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PersonEditor(api: widget.api, t: widget.t, locale: widget.locale),
      ),
    );
    if (!mounted) return;
    await load();
    if (saved is Map && mounted) {
      setState(() {
        if (first) {
          firstId = saved['id'];
          if (secondId == firstId) {
            secondId = null;
          }
        } else {
          secondId = saved['id'];
          if (firstId == secondId) {
            firstId = null;
          }
        }
      });
    }
  }

  Future<void> confirm() async {
    final first = selected(firstId), second = selected(secondId);
    if (first == null || second == null || firstId == secondId) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onConfirm(first, second);
    } catch (e) {
      if (mounted) setState(() => error = describeError(e, widget.t));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget choice(bool first) {
    final id = first ? firstId : secondId;
    final person = selected(id);
    final role = t(first ? 'groomSide' : 'brideSide');
    final otherId = first ? secondId : firstId;
    final available = people.where((p) => p['id'] != otherId).toList();
    final gender =
        person?['gender'] ??
        (person?['avatar']?.toString().startsWith('female_') == true
            ? 'female'
            : person?['avatar']?.toString().startsWith('male_') == true
            ? 'male'
            : null);
    final crest = gender == 'female'
        ? 'crest_bride'
        : gender == 'male'
        ? 'crest_groom'
        : first
        ? 'crest_groom'
        : 'crest_bride';
    // Emerald and gold: saturated green paired with a warm champagne gold.
    final titleColor = first
        ? const Color(0xfffff9e9)
        : const Color(0xff24462f);
    final labelColor = first
        ? const Color(0xffe9d297)
        : const Color(0xff806028);
    final detailColor = first
        ? const Color(0xffe6e8d8)
        : const Color(0xff665741);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 12, 9, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: first
                ? const [
                    Color(0xff4a8c63),
                    Color(0xff236244),
                    Color(0xff103e2d),
                  ]
                : const [
                    Color(0xfffff4d9),
                    Color(0xffe9ce91),
                    Color(0xffc99d4e),
                  ],
          ),
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: const Color(0xffc6a35e), width: 1.8),
          boxShadow: [
            BoxShadow(
              color: Palette.shadow.withValues(alpha: .25),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Art(crest, width: 112, height: 112),
            const SizedBox(height: 6),
            Text(
              t(first ? 'firstPerson' : 'secondPerson').toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1,
                fontWeight: FontWeight.bold,
                color: labelColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              role,
              textAlign: TextAlign.center,
              style: heading(16, color: titleColor),
            ),
            const SizedBox(height: 12),
            PopupMenuButton<String>(
              tooltip: t('personDropdownHint'),
              enabled: !busy,
              constraints: const BoxConstraints(
                minWidth: 235,
                maxWidth: 290,
                maxHeight: 360,
              ),
              position: PopupMenuPosition.under,
              onSelected: (value) {
                if (value == '__add__') {
                  addPerson(first);
                  return;
                }
                setState(() {
                  if (first) {
                    firstId = value;
                  } else {
                    secondId = value;
                  }
                });
              },
              itemBuilder: (_) => [
                for (final p in available)
                  PopupMenuItem<String>(
                    value: p['id'].toString(),
                    child: Row(
                      children: [
                        Avatar(
                          p['display_name'].toString(),
                          image: p['avatar'] as String?,
                          size: 35,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p['display_name'].toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                p['birth_place_name'].toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Palette.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: '__add__',
                  child: Row(
                    children: [
                      const Icon(
                        Icons.person_add_alt_1,
                        color: Palette.greenDark,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        t('addNewPerson'),
                        style: const TextStyle(
                          color: Palette.greenDeep,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              child: Container(
                height: 46,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                decoration: BoxDecoration(
                  color: const Color(0xfffffaf0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xffe0bf74)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .12),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    if (person != null)
                      Avatar(
                        person['display_name'].toString(),
                        image: person['avatar'] as String?,
                        size: 30,
                      ),
                    if (person != null) const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        person?['display_name']?.toString() ??
                            t('personDropdownHint'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: person == null ? 11 : 12,
                          fontWeight: FontWeight.w600,
                          color: person == null ? Palette.muted : Palette.ink,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down,
                      color: Palette.greenDark,
                    ),
                  ],
                ),
              ),
            ),
            if (person != null)
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Text(
                  personLine(person, widget.t, widget.locale),
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: detailColor),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        const Positioned.fill(child: PickerBackground()),
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Colors.white, Color(0xffefe6d3)],
                            ),
                            border: Border.all(color: const Color(0xffe2d2ad)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0xffcdb98e),
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const BackButton(),
                        ),
                        Expanded(
                          child: Text(
                            t('match'),
                            textAlign: TextAlign.center,
                            style: heading(17),
                          ),
                        ),
                        const SizedBox(width: 42),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                      children: [
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Palette.greenSoft,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Text(
                              t('appName'),
                              style: heading(12, color: Palette.greenDark),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          t('chooseBothPeople'),
                          textAlign: TextAlign.center,
                          style: heading(27, color: Palette.greenDeep),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          t('chooseBothPeopleBody'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Palette.muted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Align(
                          alignment: Alignment.centerRight,
                          child: Art('lotus', width: 32, height: 29),
                        ),
                        const SizedBox(height: 12),
                        if (loading)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(28),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              choice(true),
                              const SizedBox(width: 10),
                              choice(false),
                            ],
                          ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Palette.greenSoft,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xffd5e2ce)),
                          ),
                          child: Text(
                            t('chooseBothPeopleBody'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Palette.greenDark,
                            ),
                          ),
                        ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(36, 8, 36, 23),
                    child: Column(
                      children: [
                        if (busy)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: LinearProgressIndicator(),
                          ),
                        PrimaryButton(
                          t('match'),
                          onPressed:
                              busy ||
                                  firstId == null ||
                                  secondId == null ||
                                  firstId == secondId
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
        ),
      ],
    ),
  );
}
