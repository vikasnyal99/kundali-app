# Engine evaluation — 2026-10-28

The user has no provider and requested engine research. No paid account has been created, and no licensing commitment or production deployment has been made.

## Candidate selected for LOCAL evaluation

[vedic-calc](https://github.com/atolat/vedic-calc), commit `620d54560ee7e108496495eeb17054a52630a0bf`: Python/Pydantic library without GUI dependencies, backed by pyswisseph. It implements all eight Ashtakoota factors. The optional adapter computes genuine Moon positions and rule-based scores; it does not synthesize scores with AI. Install `server/requirements-engine.txt`, then set `ASTROLOGY_MODE=local_experimental` in your local environment.

Upstream compatibility and accuracy suites: 20 tests passed locally. Those astronomy tests compare its wrapper with raw Swiss Ephemeris, not an independent astronomical engine. Compatibility tests cover invariants and some known rules, not comprehensive independently reviewed birth-to-match golden cases. Therefore every result carries `independent_validation_pending` and the UI labels it experimental. Production refuses this mode without an explicit release approval flag. Setting the flag alone is not validation.

Method: Lahiri ayanamsa, whole-sign charts, UTC resolved with Python IANA timezone data. Person 1 occupies the traditional groom-side rule position; Person 2 the bride-side position. This matters because Varna and some other factors can be directional. The UI documents the order. No automatic gender inference. Manglik is unavailable until a specific variant is independently validated. Engine defaults may use Moshier fallback when Swiss data files are absent; this is recorded, not described as a guaranteed JPL dataset.

## Licensing

The [library declares AGPL-3.0-or-later](https://github.com/atolat/vedic-calc/blob/main/pyproject.toml). [Swiss Ephemeris](https://www.astro.com/swisseph/swisseph.htm) offers AGPL or a professional license. Buying a Swiss license alone does not relicense vedic-calc. Before distributing or publicly hosting a combined application, choose a license-compatible release approach or obtain suitable permissions/replace the rules library. No third-party engine code is copied into this repository; the dependency is optional and pinned.

## Alternative reviewed

[PyJHora](https://github.com/naturalstupid/PyJHora) has broader traditional calculations and North/South matching. Its current package also declares AGPL. It has a larger desktop-oriented dependency surface. It remains useful as a secondary comparison reference, but agreement between implementations does not establish domain correctness.

## Remaining acceptance work

- Have a knowledgeable reviewer approve the exact eight-factor rule tables, directional roles, exceptions, and Manglik variant.
- Collect consented/anonymized reference cases with source, input timezone, ayanamsa, expected all-eight scores, and tolerances. Include DST, timezone date rollover and nakshatra boundaries.
- Compare engine results against those fixtures; investigate differences instead of adjusting totals to fit.
- Decide the public-release licensing approach; then configure the deployment image to include the selected engine.
- Pin ephemeris data distribution and checksum if requiring Swiss data rather than the documented Moshier fallback.

## Adapter fix and review findings (2026-10-28, later session)

The adapter now reads the pinned Pydantic models correctly (`PlanetPosition.nakshatra_info.nakshatra/.pada`;
`NakshatraInfo` is a frozen model, not a mapping). Charts are built from the stored UTC instant with a zero offset,
so the library never re-applies a local offset or rolls the date. Tests check this against a local-time chart and raw
Swiss Ephemeris Lahiri output. Local results now go through the same `validate_facts` checks as provider results:
eight named rows, per-row maxima, total = sum, total possible 36, pinned version/ruleset, and Manglik forced to
`unavailable`. Results add `moon_near_boundary_time_sensitive` when an approximate birth time puts the Moon within
0.65° (about ±1 h of lunar motion) of a nakshatra or sign boundary.

**Deviations found in upstream rules** (pinned by `test_known_upstream_graha_maitri_deviations_are_pinned`):

| Pair (Moon sign lords) | Commonly published Graha Maitri | Upstream |
|---|---|---|
| Mars ↔ Saturn (Scorpio/Capricorn) | 0.5 (Mars sees Saturn as neutral, Saturn sees Mars as enemy) | 0 (Mars→Saturn coded as enemy) |
| Venus ↔ Moon (Taurus/Cancer) | 0.5 (Venus sees the Moon as enemy) | 3 (Venus→Moon coded as neutral) |
| Moon ↔ Mercury (Cancer/Gemini) | 1 (friend + enemy) | 3 (scores are summed, so friend+enemy collides with neutral+neutral) |

Also needing a reviewer's decision (these are variants rather than outright errors):
- Yoni scores the same animal with the same gender as 3/4; many tables give 4.
- Gana (groom-side, bride-side) asymmetry.
- The Vashya table includes 0.5 values and treats signs as whole (no Sagittarius/Capricorn half split).
- Bhakoot and Nadi have no exception/cancellation rules (e.g. same or friendly sign lords).
- The Tara method counts both directions.

These findings are why the engine must remain experimental. Fixing them means either patching upstream (with
the AGPL consequences) or implementing reviewed rule tables in this repository with golden fixtures.
