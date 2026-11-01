"""Regenerate the release inventory after an intentional source/package update."""
import json
from paths import PROJECT
from verify_release import files, sha

if __name__ == '__main__':
    inventory = {p.relative_to(PROJECT).as_posix(): sha(p) for p in files()}
    manifest = {'algorithm': 'SHA-256', 'sha256': dict(sorted(inventory.items()))}
    target = PROJECT / 'build/MANIFEST.json'
    target.write_text(json.dumps(manifest, indent=2) + '\n')
    print('MANIFEST_UPDATED', len(inventory))
