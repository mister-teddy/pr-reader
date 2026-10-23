/// Heuristics for files that reviewers rarely read line by line. Their diffs
/// start collapsed.
library;

const _exactNames = {
  'package-lock.json',
  'npm-shrinkwrap.json',
  'yarn.lock',
  'pnpm-lock.yaml',
  'bun.lockb',
  'bun.lock',
  'pubspec.lock',
  'podfile.lock',
  'gemfile.lock',
  'composer.lock',
  'cargo.lock',
  'go.sum',
  'poetry.lock',
  'pipfile.lock',
  'uv.lock',
  'flake.lock',
  'mix.lock',
  'packages.lock.json',
  'gradle.lockfile',
  'package.resolved',
  'deno.lock',
};

const _suffixes = [
  '.min.js',
  '.min.css',
  '.map',
  '.snap',
  '.g.dart',
  '.freezed.dart',
  '.mocks.dart',
  '.pb.go',
  '.pb.dart',
  '.pbjson.dart',
  '.pbenum.dart',
  '_pb2.py',
  '.pb.h',
  '.pb.cc',
  '.designer.cs',
  '.generated.ts',
  '.generated.js',
  '.lock',
];

const _dirMarkers = ['/vendor/', '/node_modules/', '/__snapshots__/', '/generated/', '/gen/'];

bool isLikelyGenerated(String path) {
  final lower = path.toLowerCase();
  final slash = lower.lastIndexOf('/');
  final name = slash < 0 ? lower : lower.substring(slash + 1);
  if (_exactNames.contains(name)) return true;
  for (final s in _suffixes) {
    if (lower.endsWith(s)) return true;
  }
  final padded = '/$lower';
  for (final d in _dirMarkers) {
    if (padded.contains(d)) return true;
  }
  return false;
}
