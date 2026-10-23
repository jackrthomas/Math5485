#!/usr/bin/env bash
# Render the public and private sites, then publish the public one to GitHub Pages
# (bash version of publish.ps1).
#
#   ./publish.sh               render both, check, publish _book/ to gh-pages
#   ./publish.sh --no-publish  render both and check, but don't publish
#
# Only _book/ (public) is published. _book-private/ is git-ignored and never leaves this machine.
set -euo pipefail
cd "$(dirname "$0")"

step() { local name=$1; shift; echo; echo "== $name"; "$@" || { echo; echo "$name failed; nothing published." >&2; exit 1; }; }

step 'Public render (_book/)'          quarto render
step 'Private render (_book-private/)' quarto render --profile private

# safety net: draft hints/solutions must never reach the public site
echo; echo '== Checking _book/ for draft answers'
if leaks=$(grep -rlE 'exercise-(solution|hint)[^"]*\bdraft\b' _book --include='*.html' --include='*.json'); then
    echo 'Draft answers found in the public site; nothing published:' >&2
    echo "$leaks" | sed 's/^/  /' >&2
    exit 1
fi
echo 'None found.'

if [[ "${1:-}" == --no-publish ]]; then
    echo; echo 'Rendered both sites; skipped publishing (--no-publish).'
    exit 0
fi

step 'Publish _book/ to gh-pages' quarto publish gh-pages --no-render --no-prompt

echo; echo 'Done: public site published, private site in _book-private/.'
