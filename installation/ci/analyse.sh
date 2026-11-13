#!/usr/bin/env bash
# Analyse statique sans échec : publie les avertissements et remarques de
# l'analyseur (warning, info) comme annotations GitHub, par lots de 60 lignes.
# Usage : analyse.sh <nom> <commande d'analyse…>
nom="$1"; shift
journal="$(mktemp)"
"$@" 2>&1 | tee "$journal" || true
encoder() { sed -e 's/%/%25/g' -e 's/\r//g' | sed ':a;N;$!ba;s/\n/%0A/g'; }
lignes="$(mktemp)"
grep -E '^\s*(error|warning|info) [•-] ' "$journal" | sed 's/^ *//' > "$lignes" || true
total=$(wc -l < "$lignes")
printf '::notice title=Analyse %s::%s remarque(s) de l analyseur\n' "$nom" "$total"
split -l 60 -d "$lignes" "$lignes.lot."
n=0
for f in "$lignes".lot.*; do
  [ -s "$f" ] || continue
  n=$((n+1))
  printf '::warning title=Analyse %s (%s)::%s\n' "$nom" "$n" "$(encoder < "$f")"
done
exit 0
