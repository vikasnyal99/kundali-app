# Figma-ready Design System

Mobile baseline: 390x844, 8pt spacing grid. Safe areas, 16px page margins, 44-48dp minimum tap targets. Flutter Material 3 with custom theme extensions.

## English theme
Background #F8F7F2; surface #FFFFFF; primary #355C50; secondary #D5B66D; text #202C28; subtle border #E2E7DF; error #A13D3D.

## Hindi theme
Background #FFF8EF; surface #FFFFFF; primary #9E4F24; secondary #D4A743; text #39251C; subtle border #F1DEC8; error #A13D3D.

Fonts: Inter for English, Noto Sans Devanagari for Hindi (bundle only appropriately licensed assets from chosen distribution); report renderer must support Unicode Devanagari embedding. Headline 28, section 20, card title 16, body 14-16, caption 12, use scalable units.

Core components: AppTopBar, LanguageSwitch, PrimaryButton, TextField, BirthPlacePicker, ProfileCard, FixedPersonCard, CandidatePicker, GunaScoreRing, KootaBreakdownRow, CompatibilityCard, ReportStatusBadge, LoadingSkeleton, ErrorEmptyState.

Accessibility: contrast WCAG AA wherever feasible, scalable fonts, no exclusive reliance on score color, descriptive labels and screen reader order.

Figma build instructions: construct frames for screens 1–12 in both language variants; create components and variants; prototype Home->Pair->Summary->Compare and settings language switch. This ZIP includes screen specifications, not an actual `.fig` file or image mockups.
