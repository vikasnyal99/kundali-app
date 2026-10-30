import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'theme.dart';

typedef Translate = String Function(String);

/// Localised message for an API error code; unknown codes stay visible for support.
String describeError(Object e, Translate t) {
  if (e is! ApiException) return t('error');
  final key = 'err_${e.code}';
  final text = t(key);
  return text == key ? '${t('error')} (${e.code})' : text;
}

/// Localised reason for a failed match or report, falling back to the generic status.
String failureText(Translate t, String? code) {
  if (code == null) return t('failed');
  final text = t('err_$code');
  return text == 'err_$code' ? '${t('failed')} ($code)' : text;
}

/// Opens a signed PDF link. On the web it replaces the page: browsers block new tabs opened after
/// waiting for the report, and the native shell hands non-app links to the phone's PDF viewer.
Future<bool> openPdf(String url) => launchUrl(
  Uri.parse(url),
  mode: LaunchMode.externalApplication,
  webOnlyWindowName: kIsWeb ? '_self' : null,
);

String points(num v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';

String placeLabel(Map<String, dynamic> p) => [
  p['name'],
  p['region'],
  p['country'],
  p['pincode'],
].where((v) => v != null && v.toString().isNotEmpty).join(', ');

const months = {
  'en': [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ],
  'hi': [
    'जनवरी',
    'फ़रवरी',
    'मार्च',
    'अप्रैल',
    'मई',
    'जून',
    'जुलाई',
    'अगस्त',
    'सितंबर',
    'अक्टूबर',
    'नवंबर',
    'दिसंबर',
  ],
};

/// Stored dates are YYYY-MM-DD; shown as "12 Oct 1995" (or "12 अक्टूबर 1995").
String displayDate(String iso, [String locale = 'en']) {
  final parts = iso.split('-');
  final m = parts.length == 3 ? int.tryParse(parts[1]) : null;
  if (m == null || m < 1 || m > 12) return iso;
  return '${int.parse(parts[2])} ${months[locale]![m - 1]} ${parts[0]}';
}

/// Stored times are 24-hour HH:MM:SS; people read them as h:mm AM/PM.
String displayTime(String value) {
  final parts = value.split(':');
  if (parts.length < 2) return value;
  final h = int.tryParse(parts[0]) ?? 0;
  return '${h % 12 == 0 ? 12 : h % 12}:${parts[1]} ${h < 12 ? 'AM' : 'PM'}';
}

/// "12 Oct 1995, Delhi" as in the design's lists; with the time when [withTime].
String personLine(Map p, Translate t, String locale, {bool withTime = false}) {
  final city = p['birth_place_name'].toString().split(',').first.trim();
  final time = p['time_accuracy'] == 'unknown'
      ? t('unknownTime')
      : displayTime(p['birth_time_local'].toString());
  return [
    displayDate(p['birth_date'].toString(), locale),
    if (withTime) time,
    city,
  ].join(withTime ? ' · ' : ', ');
}

String firstName(Object? name) =>
    name.toString().trim().split(RegExp(r'\s+')).first;

/// A saved person as a card row: avatar, name, date and place, with a trailing control.
class PersonRow extends StatelessWidget {
  final Map person;
  final Translate t;
  final String locale;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected, withTime;
  final Color accent;
  const PersonRow({
    super.key,
    required this.person,
    required this.t,
    required this.locale,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.withTime = false,
    this.accent = Palette.gold,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AppCard(
      onTap: onTap,
      color: !selected
          ? Palette.surface
          : accent == Palette.green
          ? Palette.greenSoft
          : Palette.goldSoft,
      borderColor: selected ? accent : Palette.border,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Avatar(
            person['display_name'].toString(),
            image: person['avatar'] as String?,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person['display_name'].toString(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  personLine(person, t, locale, withTime: withTime),
                  style: const TextStyle(color: Palette.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );
}

/// A report or match as in the design's "Recent Reports": couple, score and verdict chip.
class ReportRow extends StatelessWidget {
  final List names;
  final num? score;
  final String subtitle;
  final String? image;
  final Translate t;
  final Widget? trailing;
  final VoidCallback? onTap;
  const ReportRow({
    super.key,
    required this.names,
    required this.score,
    required this.subtitle,
    required this.t,
    this.image,
    this.trailing,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Avatar(
            names.isEmpty ? '?' : names.last.toString(),
            size: 46,
            image: image,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  names.map(firstName).join(' & '),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: Palette.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          if (score != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${points(score!)}/36',
                  style: heading(15, color: Palette.greenDark),
                ),
                const SizedBox(height: 4),
                BandChip(scoreBand(score!), t('band_${scoreBand(score!)}')),
              ],
            ),
          ?trailing,
        ],
      ),
    ),
  );
}
