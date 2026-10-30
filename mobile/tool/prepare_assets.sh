#!/usr/bin/env bash
# Converts the owner's KundliMilan asset pack into small app images (ImageMagick).
#   bash mobile/tool/prepare_assets.sh <KundliMilan_Separate_App_Assets dir>
# The pack's PNGs are upscaled crops of one composite (see its README), so they are resized to what a
# phone shows and saved as JPEG: the web app downloads each image only when a screen needs it.
set -euo pipefail
SRC=${1:?pass the KundliMilan_Separate_App_Assets directory}
cd "$(dirname "$0")/.."
OUT=assets/images; mkdir -p "$OUT"
# ImageMagick 7 is `magick`; version 6 (e.g. Debian/Ubuntu) is `convert`.
IM=$(command -v magick || command -v convert)
jpg(){ "$IM" "$SRC/$1" ${3:-} -strip -interlace Plane -quality "${4:-80}" "$OUT/$2.jpg"; }

# Backgrounds (portrait screens and banners). Crops skip the white gutters and neighbouring-image slivers
# left from the composite (measured per column).
jpg backgrounds/splash_english.png splash_en "-crop 1074x1920+6+0 +repage -resize 720x"
jpg backgrounds/splash_hindi.png splash_hi "-crop 1068x1920+12+0 +repage -resize 720x"
jpg backgrounds/home_river_sunrise.png home_banner "-crop 1010x760+14+420 +repage -resize 900x"
jpg backgrounds/night_temple_lotus.png report_card "-crop 1080x900+0+300 +repage -resize 900x" 76
jpg backgrounds/night_astrology.png settings_banner "-crop 984x700+0+40 +repage -resize 900x" 76
jpg backgrounds/light_zodiac_pattern.png zodiac_pattern "-crop 1050x1920+0+0 +repage -resize 720x" 72

# Illustrations and empty/processing states (shown on cream with a multiply blend, so white disappears).
for f in lotus zodiac_wheel kundli_scroll sun_moon vedic_still_life; do
  jpg illustrations/$f.png $f "-gravity center -crop 88%x88%+0+0 +repage -resize 420x420"  # drop edge slivers
done
jpg illustrations/wordmark_english.png wordmark_en "-resize 600x"
jpg illustrations/wordmark_hindi.png wordmark_hi "-resize 600x"
for f in no_data no_people no_reports processing report_ready success; do jpg states/$f.png state_$f "-resize 600x"; done

# Portraits: the pack's squares are off-centre, so each is re-cropped around the face.
# avatar_female_2 is cut through the face in the pack and is not used.
jpg avatars/avatar_female_1.png avatar_female_1 "-crop 240x240+272+130 +repage -resize 256x256" 84
jpg avatars/avatar_male_1.png avatar_male_1 "-crop 280x280+187+140 +repage -resize 256x256" 84
jpg avatars/avatar_male_2.png avatar_male_2 "-crop 260x260+252+110 +repage -resize 256x256" 84

# App icon: app_icon_dark without its white rounded margin, for Android launchers and the web.
"$IM" "$SRC/illustrations/app_icon_dark.png" -gravity center -crop 82%x82%+0+0 +repage -resize 512x512 /tmp/kundli_icon.png
for d in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  "$IM" /tmp/kundli_icon.png -resize "${d#*:}x${d#*:}" "android/app/src/main/res/mipmap-${d%%:*}/ic_launcher.png"
done
"$IM" /tmp/kundli_icon.png -resize 192x192 web/icons/Icon-192.png
"$IM" /tmp/kundli_icon.png -resize 512x512 web/icons/Icon-512.png
"$IM" /tmp/kundli_icon.png -resize 192x192 web/icons/Icon-maskable-192.png
"$IM" /tmp/kundli_icon.png -resize 512x512 web/icons/Icon-maskable-512.png
"$IM" /tmp/kundli_icon.png -resize 32x32 web/favicon.png
rm -f /tmp/kundli_icon.png
du -ch "$OUT"/*.jpg | tail -1
