#!/bin/zsh
set -e
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd -- "$(dirname -- "$0")"
if ! command -v node >/dev/null; then
  echo 'Install Node.js 22.12 or newer, then open this launcher again.'
  read -k 1
  exit 1
fi
if [[ ! -f .env.local && -f .env.example ]]; then cp .env.example .env.local; fi
if [[ ! -d node_modules ]]; then npm ci; fi
npx playwright install chromium
npm run build
node scripts/launch.mjs
