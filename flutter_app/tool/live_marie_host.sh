#!/usr/bin/env bash
# Host helper for integration_test/v3_marie_live_test.dart: speaks from the Mac
# into the phone when the test prints an E2E_MARK. Usage: live_marie_host.sh run.log
LOG="$1"; VOICE="${VOICE:-Thomas}"
tail -n0 -F "$LOG" | while read -r line; do
  case "$line" in
    *"E2E_MARK"*"SAY_Q1"*) say -v "$VOICE" "Bonjour Marie. Comment dit-on, où sont les toilettes, en français ?" ;;
    *"E2E_MARK"*"SAY_Q2_LONG"*) say -v "$VOICE" "Marie, explique-moi en détail la différence entre tu et vous, avec trois exemples." ;;
    *"E2E_MARK"*"SAY_INTERRUPT"*) say -v "$VOICE" "Stop. Juste dis bonjour, s'il te plaît." ;;
  esac
done
