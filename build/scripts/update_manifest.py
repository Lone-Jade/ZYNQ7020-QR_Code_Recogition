"""Regenerate the release inventory after an intentional source/package update."""
import json
from paths import PROJECT
from verify_release import files, sha, is_document, DOCUMENT_SUFFIXES

if __name__ == '__main__':
    inventory = {p.relative_to(PROJECT).as_posix(): sha(p) for p in files() if not is_document(p)}
    manifest = {'algorithm': 'SHA-256',
                'scope': 'non-document source and data files; excludes this manifest',
                'document_exclusions': {'directory': 'report/', 'suffixes': sorted(DOCUMENT_SUFFIXES),
                                        'license_directories': 'LICENSES', 'names': ['LICENSE','COPYING','NOTICE']},
                'sha256': dict(sorted(inventory.items()))}
    target = PROJECT / 'build/MANIFEST.json'
    target.write_text(json.dumps(manifest, indent=2) + '\n')
    print('MANIFEST_UPDATED', len(inventory))
