# Screen Specification / Figma Handoff

1. Splash: logo, star chart motif, tasteful premium gradient; no unverified claims.
2. Language: language cards "English" / "हिन्दी", continue CTA; selection persistent.
3. Home: welcome, four primary tiles (Match Kundlis / कुंडली मिलान; Compare Matches / तुलना करें; Saved People / सहेजे गए व्यक्ति; My Reports / मेरी रिपोर्ट).
4. Person Editor: birth details card; name, DOB, local time, location autocomplete, lat/lon, timezone, precision checkbox; save action.
5. Pair Selection: two cards Person 1 and Person 2 with swap button, status and main Generate button.
6. Computing: asynchronous progress text and cancel/return action; no fictional percentage.
7. Summary: top Guna total /36, algorithm version/setting link, key observations, "View Detailed Match", "Download PDF".
8. Breakdown: eight traditional Koota rows with individual achieved/max points; Manglik/other notes only if supported; explanation and caution.
9. Compare Setup: fixed Person 1 persistent sticky card at top; checkbox multi-select Person 2 people, add new button, Compare action.
10. Compare Results: fixed Person 1 in header; candidate cards with score /36, sub-score chips, caution icons, view details; sort by total score, ties stable; enable replacing/removing Person 2 without erasing fixed Person 1.
11. Reports: pending/ready/failed states; signed-download action.
12. Settings: language, app info, method/disclaimer, export/delete data, optional sign-in.

## Localization
Keep all strings in ARB files (`app_en.arb`, `app_hi.arb`), not inline. Ensure Hindi font supports Devanagari, dates formatted with locale, digits remain readable. Accessibility semantic labels required.

## Visual direction
English: contemporary ivory/sage/gold; Hindi: warm saffron/maroon/gold. Same spacing, component hierarchy, UX and semantics for both locales. Avoid depicting spiritual validity as proven fact.
