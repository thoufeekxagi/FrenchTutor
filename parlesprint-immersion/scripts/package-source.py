"""Create a portable source archive using an explicit allowlist, never local secrets."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
root = Path(__file__).resolve().parents[1]
folders = {'backend', 'entrypoints', 'lib', 'public', 'scripts', 'store', 'tests'}
files = {'README.md', '.gitignore', '.env.example', 'package.json', 'package-lock.json', 'tsconfig.json', 'wxt.config.ts', 'vitest.config.ts', 'playwright.config.ts', 'extension-identity.json', 'Launch ParleSprint.command'}
output = root / 'release' / 'parlesprint-immersion-0.1.0-source.zip'
output.parent.mkdir(exist_ok=True)
with ZipFile(output, 'w', ZIP_DEFLATED) as archive:
    for file in sorted(root.rglob('*')):
        rel = file.relative_to(root)
        if not file.is_file() or not (rel.parts[0] in folders or str(rel) in files):
            continue
        if any(part.startswith('.') for part in rel.parts) and str(rel) not in files:
            continue
        archive.write(file, Path(root.name) / rel)
print(output)
