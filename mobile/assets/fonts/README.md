Heading fonts (subsets of Noto Serif SemiBold and Noto Serif Devanagari SemiBold from Debian `fonts-noto-core`),
licensed under the SIL Open Font License 1.1 (https://openfontlicense.org). Subset to Latin/Devanagari with
`pyftsubset` to keep the web download small; regenerate from the same source files if more characters are needed.

Body fonts: Roboto Regular/Medium/Bold (Apache 2.0, from the Flutter SDK's material_fonts) and Noto Sans Devanagari
Regular/SemiBold (OFL, `fonts-noto-core`), subset the same way. Bundled so button labels use real weights instead of
the browser's synthetic bold.
