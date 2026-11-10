#!/usr/bin/env bash
# Exécute une commande. En cas d'échec, publie les lignes d'erreur et la fin du
# journal comme annotations GitHub (lisibles sans accès aux journaux complets).
set -o pipefail
journal="$(mktemp)"
"$@" 2>&1 | tee "$journal"
code=${PIPESTATUS[0]}
encoder() { sed -e 's/%/%25/g' -e 's/\r//g' | sed ':a;N;$!ba;s/\n/%0A/g'; }
if [ "$code" -ne 0 ]; then
  erreurs="$(grep -E -i "error|exception|failed|what went wrong|échec|cannot|undefined|isn't|not found" "$journal" | grep -v "^::" | head -n 40)"
  [ -n "$erreurs" ] && printf '::error title=Erreurs (%s)::%s\n' "$*" "$(printf '%s' "$erreurs" | encoder)"
  printf '::error title=Fin du journal (%s)::%s\n' "$*" "$(tail -n 40 "$journal" | encoder)"
fi
exit "$code"
