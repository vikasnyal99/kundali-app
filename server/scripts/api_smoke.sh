#!/usr/bin/env bash
# End-to-end API check with curl + jq. Creates a throwaway guest, exercises every endpoint, then deletes it.
#   bash server/scripts/api_smoke.sh                      # default https://kundaliapi.zivantaai.com
#   API=https://your-host bash server/scripts/api_smoke.sh
set -euo pipefail
API=${API:-https://kundaliapi.zivantaai.com}
J='Content-Type: application/json'
step(){ printf '\n== %s\n' "$*"; }
wait_for(){  # wait_for <path> <jq filter that is true when done>
  for _ in $(seq 1 40); do r=$(curl -sf "$API$1" -H "$AUTH"); [ "$(jq -r "$2" <<<"$r")" = true ] && { echo "$r"; return; }; sleep 1.5; done
  echo "timed out waiting for $1" >&2; exit 1; }
person(){  # person <name> <date> <time> <place> <lat> <lon> <accuracy>
  printf '{"display_name":"%s","birth_date":"%s","birth_time_local":"%s","birth_timezone":"Asia/Kolkata","birth_place_name":"%s","latitude":%s,"longitude":%s,"time_accuracy":"%s"}' "$@"; }

step "Health"
curl -sf "$API/health/live"; echo; curl -sf "$API/health/ready"; echo

step "Guest session, refresh, settings"
TOKEN=$(curl -sf -X POST "$API/v1/guest-sessions" | jq -r .token)
AUTH="Authorization: Bearer $TOKEN"
TOKEN=$(curl -sf -X POST "$API/v1/guest-sessions/refresh" -H "$AUTH" | jq -r .token); AUTH="Authorization: Bearer $TOKEN"
curl -sf -X PATCH "$API/v1/me/settings" -H "$AUTH" -H "$J" -d '{"locale":"hi"}' | jq -c .
curl -sf "$API/v1/me/settings" -H "$AUTH" | jq -c .

step "Place search"
curl -sf "$API/v1/places?q=Varan" -H "$AUTH" | jq -c '.[0]'

step "People: create, list, get, edit"
P1=$(curl -sf -X POST "$API/v1/people" -H "$AUTH" -H "$J" -d "$(person Rahul 1995-03-12 10:15:00 Delhi 28.6139 77.209 exact)" | jq -r .id)
P2=$(curl -sf -X POST "$API/v1/people" -H "$AUTH" -H "$J" -d "$(person Priya 1997-09-14 09:30:00 Mumbai 19.076 72.8777 exact)" | jq -r .id)
P3=$(curl -sf -X POST "$API/v1/people" -H "$AUTH" -H "$J" -d "$(person Anita 1996-01-05 18:45:00 Jaipur 26.9124 75.7873 approximate)" | jq -r .id)
curl -sf "$API/v1/people" -H "$AUTH" | jq -c '[.[] | .display_name]'
curl -sf "$API/v1/people/$P1" -H "$AUTH" | jq -c '{display_name, birth_utc, revision}'
curl -sf -X PATCH "$API/v1/people/$P3" -H "$AUTH" -H "$J" -d "$(person Anita 1996-01-05 18:45:00 Jaipur 26.9124 75.7873 exact)" | jq -c '{display_name, time_accuracy, revision}'

step "Match Rahul + Priya"
MATCH=$(curl -sf -X POST "$API/v1/matches" -H "$AUTH" -H "$J" -d "{\"person1_id\":\"$P1\",\"person2_id\":\"$P2\"}" | jq -r .id)
wait_for "/v1/matches/$MATCH" '.status=="ready" or .status=="failed"' \
  | jq '{status, failure_code, total: .facts.score.earned, out_of: .facts.score.possible, kootas: ([.facts.score.kootas[]? | {(.key): .earned}] | add), moon: [.facts.charts[]? | "\(.moon_sign) / \(.nakshatra) pada \(.pada)"], warnings: .facts.warnings}'
curl -sf "$API/v1/matches" -H "$AUTH" | jq -c '[.[] | .status]'

step "Comparison: Rahul vs Priya and Anita (ranked)"
CMP=$(curl -sf -X POST "$API/v1/comparisons" -H "$AUTH" -H "$J" -d "{\"person1_id\":\"$P1\",\"person2_ids\":[\"$P2\",\"$P3\"],\"locale\":\"en\"}" | jq -r .id)
wait_for "/v1/comparisons/$CMP" '[.results[].status] | all(. == "ready" or . == "failed")' \
  | jq -c '[.results[] | {candidate: .people[1].display_name, score: .facts.score.earned, warnings: .facts.warnings}]'

step "PDF report (English) and signed download"
REPORT=$(curl -sf -X POST "$API/v1/matches/$MATCH/reports" -H "$AUTH" -H "$J" -d '{"locale":"en"}' | jq -r .id)
wait_for "/v1/reports/$REPORT" '.status=="ready" or .status=="failed"' | jq -c '{status, failure_code}'
URL=$(curl -sf -X POST "$API/v1/reports/$REPORT/download-url" -H "$AUTH" | jq -r .url)
curl -sf -o kundli-report.pdf "$URL" && ls -l kundli-report.pdf
curl -s -o /dev/null -w 'object without signature -> HTTP %{http_code} (expect 403)\n' "${URL%%\?*}"
curl -sf "$API/v1/reports" -H "$AUTH" | jq -c '[.[] | {locale, status}]'

step "Export, then delete the test account"
curl -sf "$API/v1/me/export" -H "$AUTH" | jq -c '{people: (.people|length), matches: (.matches|length), reports: (.reports|length)}'
curl -s -o /dev/null -w 'DELETE /v1/me -> HTTP %{http_code} (expect 204)\n' -X DELETE "$API/v1/me" -H "$AUTH"
sleep 8
curl -s -o /dev/null -w 'signed URL after delete -> HTTP %{http_code} (expect 403/404)\n' "$URL"
echo; echo "All checks completed. Report saved as kundli-report.pdf"
