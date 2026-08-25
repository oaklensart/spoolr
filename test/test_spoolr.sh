#!/usr/bin/env bash
# ==============================================================================
# SPOOLR — integration tests
# Drives the real CLI end-to-end against a throwaway fake card + vault, then runs
# adversarial scenarios that must each be caught. The whole promise of this tool
# is that "SAFE TO FORMAT" is never printed when it isn't true — these tests are
# the guardrail on that promise.
#
#   bash test/test_spoolr.sh
# ==============================================================================
set -uo pipefail

ING="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/spoolr"
ROOT="$(mktemp -d)"
export SPOOLR_CONFIG_DIR="$ROOT/config"
export SPOOLR_CARD_GLOB="$ROOT/volumes/*"
STAGING="$ROOT/staging"; export HOME="$ROOT/home"   # isolate default staging
mkdir -p "$HOME/Pictures/Spoolr"

CARD="$ROOT/volumes/ALPHA"; VAULT="$ROOT/vault"
mkdir -p "$CARD/DCIM/100_TEST" "$VAULT"
echo "ALPHA" > "$CARD/.card_id"

mk(){ head -c "$2" /dev/urandom > "$CARD/DCIM/100_TEST/$1"; }
# Includes the formats older versions silently dropped: RAF (Fuji), ORF (Olympus), CR2 (Canon)
mk P1000001.RW2 20000; mk P1000002.RAF 21000; mk P1000003.ORF 22000; mk P1000004.CR2 23000

pass=0; fail=0
say(){ printf '\n== %s ==\n' "$1"; }
ck(){ if eval "$2"; then echo "  PASS: $1"; pass=$((pass+1)); else echo "  FAIL: $1"; fail=$((fail+1)); fi; }
sess(){ ls -dt "$HOME/Pictures/Spoolr"/*_SES-* 2>/dev/null | head -1; }

say "offload stages ALL formats (incl RAF/ORF/CR2)"
"$ING" --today >/dev/null 2>&1
SD="$(sess)"
ck "manifest lists 4 frames" '[ "$(grep -c . "$SD/.spoolr_manifest.tsv")" = 4 ]'
ck "RAF/ORF/CR2 present in manifest" 'grep -q RAF "$SD/.spoolr_manifest.tsv" && grep -q ORF "$SD/.spoolr_manifest.tsv" && grep -q CR2 "$SD/.spoolr_manifest.tsv"'

say "backup is read-back verified"
"$ING" backup "$VAULT" >/dev/null 2>&1
ck "4 frames indexed" '[ "$(grep -c . "$SPOOLR_CONFIG_DIR/backups.tsv")" = 4 ]'

say "HASH BACKEND: digests stay legacy-compatible and every backend agrees"
# The backend swap is a speed change, not a format change: whichever backend is
# active must produce byte-identical digests to /usr/bin/shasum, or every hash
# already in backups.tsv and in every session manifest would be invalidated.
BK_BAD=0; BK_SEEN=0
while IFS=$'\t' read -r _sid _fn _sha _vp _ts; do
  [ -f "$_vp" ] || continue
  BK_SEEN=$((BK_SEEN+1))
  [ "$(/usr/bin/shasum -a 256 "$_vp" | awk '{print $1}')" = "$_sha" ] || BK_BAD=$((BK_BAD+1))
done < "$SPOOLR_CONFIG_DIR/backups.tsv"
ck "checked every archived frame (4)" '[ "$BK_SEEN" = 4 ]'
ck "recorded digests match /usr/bin/shasum exactly" '[ "$BK_BAD" = 0 ]'

# Each fallback in the chain must agree on the same file, in the same
# "<hash>  <file>" shape the awk parse assumes.
BK_F="$(awk -F'\t' 'NR==1{print $4}' "$SPOOLR_CONFIG_DIR/backups.tsv")"
BK_REF="$(/usr/bin/shasum -a 256 "$BK_F" | awk '{print $1}')"
BK_N=0; BK_DIFF=0
for c in /sbin/sha256sum sha256sum; do
  command -v "$c" >/dev/null 2>&1 || continue
  BK_N=$((BK_N+1))
  [ "$("$c" "$BK_F" | awk '{print $1}')" = "$BK_REF" ] || BK_DIFF=$((BK_DIFF+1))
done
ck "native backends agree with the perl fallback" '[ "$BK_DIFF" = 0 ]'
# Not an assertion: a perl-only machine is exactly what the fallback is for, so
# finding no native backend must not turn the suite red. The check above that
# recorded digests match shasum already covers the *active* backend either way.
[ "$BK_N" -ge 1 ] || echo "  NOTE: no native sha256sum here; only the perl path was exercised"
BK_DOC="$("$ING" doctor 2>&1)"
ck "doctor names the active hash backend" 'echo "$BK_DOC" | grep -q "backend:"'

say "reconcile with card present → SAFE (exit 0)"
"$ING" reconcile >/dev/null 2>&1; ck "exit 0" '[ "$?" = 0 ]'

say "reconcile with NO card inserted → still SAFE (verifies staged copies)"
mv "$CARD" "$ROOT/ejected"    # simulate ejected card
"$ING" reconcile >/dev/null 2>&1; ck "card-absent SAFE exit 0" '[ "$?" = 0 ]'
mv "$ROOT/ejected" "$CARD"

say "ADVERSARIAL: corrupt a vault copy → NOT SAFE"
VF="$(awk -F'\t' 'NR==1{print $4}' "$SPOOLR_CONFIG_DIR/backups.tsv")"; echo x >> "$VF"
OUT="$("$ING" reconcile 2>&1)"; rc=$?
ck "blocked (exit 1)" '[ "$rc" = 1 ]'; ck "verdict names NOT SAFE" 'echo "$OUT" | grep -q "NOT SAFE"'
cp "$SD/$(basename "$VF")" "$VF"   # restore

say "ADVERSARIAL: a keeper missing from the vault → NOT SAFE"
DF="$(awk -F'\t' 'NR==2{print $4}' "$SPOOLR_CONFIG_DIR/backups.tsv")"
DN="$(awk -F'\t' 'NR==2{print $2}' "$SPOOLR_CONFIG_DIR/backups.tsv")"
rm -f "$DF"; grep -v "	$DN	" "$SPOOLR_CONFIG_DIR/backups.tsv" > "$SPOOLR_CONFIG_DIR/backups.tsv.t" && mv "$SPOOLR_CONFIG_DIR/backups.tsv.t" "$SPOOLR_CONFIG_DIR/backups.tsv"
OUT="$("$ING" reconcile 2>&1)"; rc=$?
ck "blocked and named 'not in vault'" '[ "$rc" = 1 ] && echo "$OUT" | grep -q "not in vault"'

say "read-only guarantee: status/reconcile never tag a card"
NU="$ROOT/volumes/NONAME"; mkdir -p "$NU/DCIM/100"; head -c 9000 /dev/urandom > "$NU/DCIM/100/IMG_1.CR2"
# make it the only card so detection is unambiguous
mv "$CARD" "$ROOT/hidden"
"$ING" reconcile >/dev/null 2>&1 || true
ck "no .card_id created by reconcile" '[ ! -f "$NU/.card_id" ]'
mv "$ROOT/hidden" "$CARD"; rm -rf "$NU"

say "volumes lists drives as JSON; set-vault persists the vault"
OUT="$("$ING" volumes 2>/dev/null)"
ck "volumes emits a JSON array" 'printf "%s" "$OUT" | python3 -c "import sys,json;assert isinstance(json.load(sys.stdin),list)" 2>/dev/null'
"$ING" set-vault "$ROOT/thevault" >/dev/null 2>&1
ck "set-vault saved to config" 'grep -q "thevault" "$SPOOLR_CONFIG_DIR/config.conf"'
ck "probe reflects the new vault" '"$ING" probe 2>/dev/null | grep -q "thevault"'

say "probe emits valid JSON with live card fields"
OUT="$("$ING" probe 2>/dev/null)"
ck "probe JSON parses & reports the card" 'printf "%s" "$OUT" | python3 -c "import sys,json;d=json.load(sys.stdin);assert d[\"card_present\"];assert \"card_first_run\" in d" 2>/dev/null'

say "name renames the card and carries the watermark"
"$ING" name ZULU >/dev/null 2>&1
ck ".card_id updated to ZULU" '[ "$(cat "$CARD/.card_id")" = ZULU ]'
"$ING" name ALPHA >/dev/null 2>&1   # back to a known name for later steps

say "--fast offload records manifest hashes without source re-read"
# fresh card + baseline so no prompt
NC2="$ROOT/volumes/FASTCARD"; mkdir -p "$NC2/DCIM/1"; echo FASTCARD > "$NC2/.card_id"
mv "$CARD" "$ROOT/parked"
head -c 20000 /dev/urandom > "$NC2/DCIM/1/F1.RW2"
"$ING" --fast --baseline=all >/dev/null 2>&1
FS=$(ls -dt "$HOME/Pictures/Spoolr"/*_SES-* | head -1)
ck "fast pull staged the frame with a manifest hash" '[ -n "$(awk -F"\t" "NR==1&&\$3!=\"\"{print 1}" "$FS/.spoolr_manifest.tsv" 2>/dev/null)" ]'
rm -rf "$NC2" "$FS"; mv "$ROOT/parked" "$CARD"

say "session ids never collide, even past a foreign ledger row"
# `reset` preserves rows this tool did not write. One landing last used to make
# the next id restart at SES-001 — and a duplicate id would hand a restore the
# wrong session's frames out of backups.tsv.
printf '2019-01-01\tForeign\t2019-01-01\t4 frames\n' >> "$SPOOLR_CONFIG_DIR/ledger.tsv"
head -c 7000 /dev/urandom > "$CARD/DCIM/100_TEST/COLLIDE.RW2"
"$ING" >/dev/null 2>&1
ck "every SES id is unique" '[ "$(cut -f2 "$SPOOLR_CONFIG_DIR/ledger.tsv" | grep "^SES-" | sort | uniq -d | wc -l | tr -d " ")" = 0 ]'
ck "foreign row still preserved" 'grep -q Foreign "$SPOOLR_CONFIG_DIR/ledger.tsv"'

# ── RESTORE ───────────────────────────────────────────────────────────────
# The recovery case: the drive holding the originals is gone, but the card was
# never formatted. These run on their own card so the earlier adversarial tests
# (which deliberately damage the vault) can't muddy the result.
say "RESTORE: staging drive lost, card intact → keepers come back"
mv "$CARD" "$ROOT/parked2"                       # RECOV must be the only card
RC="$ROOT/volumes/RECOV"; mkdir -p "$RC/DCIM/101_R"; echo RECOV > "$RC/.card_id"
for n in 1 2 3; do head -c $((10000 + n)) /dev/urandom > "$RC/DCIM/101_R/R00000$n.RW2"; done
"$ING" --baseline=all >/dev/null 2>&1
RS="$(sess)"
RSID="$(awk -F'\t' -v d="$RS" '$6==d{print $2}' "$SPOOLR_CONFIG_DIR/ledger.tsv" | tail -1)"
"$ING" backup "$ROOT/rvault" >/dev/null 2>&1
WM="$SPOOLR_CONFIG_DIR/watermarks/RECOV.watermark"
WM_BEFORE="$(stat -f%m "$WM" 2>/dev/null || echo none)"
rm -rf "$RS" "$ROOT/rvault"                      # the disaster: staging AND vault gone
ck "backup index survived the disaster" '[ "$(grep -c "^$RSID	" "$SPOOLR_CONFIG_DIR/backups.tsv")" = 3 ]'

OUT="$("$ING" restore "$RSID" "$ROOT/newdrive" 2>&1)"
NEWDIR="$(ls -d "$ROOT/newdrive"/*_SES-*_restored-from-* 2>/dev/null | head -1)"
ck "rebuilt the frame list from the backup index" 'echo "$OUT" | grep -q "backup index"'
ck "restored into a new session folder" '[ -n "$NEWDIR" ]'
ck "all 3 keepers restored" '[ "$(ls "$NEWDIR"/*.RW2 2>/dev/null | wc -l | tr -d " ")" = 3 ]'
ck "restored bytes are identical to the card originals" 'cmp -s "$NEWDIR/R000001.RW2" "$RC/DCIM/101_R/R000001.RW2" && cmp -s "$NEWDIR/R000003.RW2" "$RC/DCIM/101_R/R000003.RW2"'
ck "watermark NOT advanced by a restore" '[ "$WM_BEFORE" = "$(stat -f%m "$WM" 2>/dev/null || echo none)" ]'

RROW="$(awk -F'\t' -v d="$NEWDIR" '$6==d{print $0}' "$SPOOLR_CONFIG_DIR/ledger.tsv" | tail -1)"
ck "ledger row is RESTORED, never VERIFIED" '[ "$(printf "%s" "$RROW" | cut -f7)" = RESTORED ]'
ck "ledger row references the session it recovered" '[ "$(printf "%s" "$RROW" | cut -f8)" = "restored_from=$RSID" ]'
ck "restore took a NEW session id" '[ "$(printf "%s" "$RROW" | cut -f2)" != "$RSID" ]'
ck "a restored session is not safe to format" '"$ING" reconcile >/dev/null 2>&1; [ "$?" = 1 ]'

say "RESTORE: a filename the camera reused is refused, not silently returned"
head -c 12345 /dev/urandom > "$RC/DCIM/101_R/R000001.RW2"     # same name, different frame
OUT="$("$ING" restore "$RSID" "$ROOT/nd2" 2>&1)"
ck "names the reused filename" 'echo "$OUT" | grep -q "MISMATCH.*R000001.RW2"'
ck "restores the 2 intact frames only" '[ "$(ls "$ROOT/nd2"/*_SES-*/*.RW2 2>/dev/null | wc -l | tr -d " ")" = 2 ]'
ck "the impostor frame was NOT written" '! cmp -s "$ROOT/nd2"/*_SES-*/R000001.RW2 "$RC/DCIM/101_R/R000001.RW2" 2>/dev/null'

say "RESTORE: a frame no longer on the card is reported gone"
rm -f "$RC/DCIM/101_R/R000002.RW2"
OUT="$("$ING" restore "$RSID" "$ROOT/nd3" 2>&1)"
ck "reports it MISSING" 'echo "$OUT" | grep -q "MISSING.*R000002.RW2"'
ck "restores only what is still there" '[ "$(ls "$ROOT/nd3"/*_SES-*/*.RW2 2>/dev/null | wc -l | tr -d " ")" = 1 ]'

say "RESTORE: --dry-run reports and copies nothing"
OUT="$("$ING" restore "$RSID" "$ROOT/nd4" --dry-run 2>&1)"
ck "says it is a dry run" 'echo "$OUT" | grep -q "Dry run"'
ck "wrote no folder" '[ ! -d "$ROOT/nd4" ]'
ck "wrote no ledger row" '[ "$(grep -c "nd4" "$SPOOLR_CONFIG_DIR/ledger.tsv")" = 0 ]'

say "RESTORE: refuses when no per-file record survives"
for n in 7 8; do head -c $((13000 + n)) /dev/urandom > "$RC/DCIM/101_R/R00000$n.RW2"; done
"$ING" >/dev/null 2>&1                            # rolling pull, never backed up
NS="$(sess)"; NSID="$(awk -F'\t' -v d="$NS" '$6==d{print $2}' "$SPOOLR_CONFIG_DIR/ledger.tsv" | tail -1)"
rm -rf "$NS"                                      # manifest dies with the folder
OUT="$("$ING" restore "$NSID" "$ROOT/nd5" 2>&1)"; rc=$?
ck "refuses (exit 1)" '[ "$rc" = 1 ]'
ck "says no record survives" 'echo "$OUT" | grep -q "No per-file record survives"'
ck "wrote nothing" '[ ! -d "$ROOT/nd5" ]'

say "RESTORE: refuses a session belonging to a different card"
OC="$ROOT/volumes/OTHER"; mkdir -p "$OC/DCIM/1"; echo OTHER > "$OC/.card_id"
head -c 5000 /dev/urandom > "$OC/DCIM/1/O1.RW2"
mv "$RC" "$ROOT/parked3"                          # OTHER is now the only card
OUT="$("$ING" restore "$RSID" "$ROOT/nd6" 2>&1)"; rc=$?
ck "refuses the wrong card (exit 1)" '[ "$rc" = 1 ]'
ck "names the card actually needed" 'echo "$OUT" | grep -q "Insert CARD RECOV"'
mv "$ROOT/parked3" "$RC"; rm -rf "$OC"

rm -rf "$RC"; mv "$ROOT/parked2" "$CARD"          # hand the rig back to ALPHA

say "reset clears tool data but preserves foreign config data"
printf 'my cold storage index\n' > "$SPOOLR_CONFIG_DIR/coldstore.tsv"   # foreign file
printf '2020-01-01\tAlpha\t2020-01-01\t9 frames\n' >> "$SPOOLR_CONFIG_DIR/ledger.tsv"  # foreign row
"$ING" reset --yes >/dev/null 2>&1
ck "foreign coldstore.tsv preserved" '[ -s "$SPOOLR_CONFIG_DIR/coldstore.tsv" ]'
ck "foreign (non-SES) ledger row preserved" 'grep -q Alpha "$SPOOLR_CONFIG_DIR/ledger.tsv"'
ck "our SES- session rows cleared" '[ "$(grep -c "	SES-" "$SPOOLR_CONFIG_DIR/ledger.tsv")" = 0 ]'
ck "backup index cleared" '[ ! -s "$SPOOLR_CONFIG_DIR/backups.tsv" ]'
ck "reset kept staged photos on disk (no --purge)" '[ -n "$(find "$HOME/Pictures/Spoolr" -iname "*.RW2" 2>/dev/null | head -1)" ]'

printf '\nRESULT: %d passed, %d failed\n' "$pass" "$fail"
rm -rf "$ROOT"
exit $fail
