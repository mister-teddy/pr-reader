# PR Reader

A Flutter app for reading GitHub pull requests, built to stay smooth on very
large ones (20k–150k changed lines, thousands of files) on phones, foldables,
tablets and desktops.

Version 1 is read-only: conversation, reviews and inline review threads,
commits, and the full diff.

## Features

- **Open anything**: a PR URL, `owner/repo#123`, `owner/repo/pull/123`, or
  `owner/repo` to browse a repository's PRs. With a token, the home screen
  lists PRs waiting on your review and your own open PRs.
- **Diff**: unified or side-by-side (automatic on wide windows), line
  wrapping or horizontal scrolling, syntax colors for ~40 languages,
  word-level change emphasis, sticky file headers, and inline markers for
  review threads.
- **Navigation for giant PRs**: a compact file tree with filtering that
  follows your scroll position, a draggable scrubber that names the file
  under your finger and marks comments and search hits, next/previous file,
  and search across the whole diff.
- **Review workflow**: "Viewed" marks per file (kept per PR and reset when
  the file changes again), collapse/expand all, and auto-collapsed lockfiles,
  generated files and very large diffs.
- **Files GitHub won't diff**: when the API omits a patch because it is too
  large, "Load diff" fetches both versions and computes the diff on-device.
- **Adaptive layout**:
  - Phones get a bottom bar within thumb reach and a file-tree sheet, and the
    header hides while you scroll down the diff.
  - Tablets and desktops get a resizable tree pane and a toolbar.
  - Windows 1600 px and wider add a side panel for comment threads.
  - Book-style foldables put the tree and the diff on either side of the hinge.
- Light and dark themes, adjustable code font size, and keyboard shortcuts
  on desktop (`j`/`k`, `v`, `x`, `t`, `/`, `n`).

## How it handles giant PRs

| Problem | Approach |
| --- | --- |
| The diff endpoint refuses PRs over 20k lines | Files are fetched with `/pulls/{n}/files`, 100 per page, 4 pages at a time. They're parsed on a background isolate and appended in order, so reading starts before loading finishes. |
| 100k+ rows in a scroll view | The whole diff is one flat list of rows in typed arrays (`lib/src/diff/diff_layout.dart`). Each row's height is computed up front from monospace column math, including wrapped lines. |
| Flutter's variable-extent lists are O(n) per child | `SliverPrefixExtentList` (`lib/src/ui/diff/prefix_extent_list.dart`) places children from prefix sums and finds the first visible row with a binary search. Jumping anywhere costs the same as scrolling at the top. |
| Re-layout on resize, rotation, fold or collapse | The layout is rebuilt in milliseconds, and the row at the top of the screen is re-anchored so you keep your place. |
| Syntax highlighting cost | A small line tokenizer runs lazily in 512-line blocks, only for what you look at. |
| Patches GitHub omits | A patience diff with an exact-LCS fallback (`lib/src/diff/line_diff.dart`) runs on an isolate. |

Measured on macOS (profile build) with
[flutter/flutter#171703](https://github.com/flutter/flutter/pull/171703):
1,912 files, 122k diff lines, a 2.5M px scroll extent.

- First files visible after 1.2 s; all files loaded after 2.7 s, without a token.
- 2,446 frames of fast scrolling plus 40 random jumps: build time p50 1.1 ms,
  p99 11.2 ms, max 15.6 ms. No build exceeded the 16 ms frame budget; 3
  raster frames did.

## Running

```sh
flutter pub get
flutter run -d macos     # or chrome, an Android/iOS device, windows, linux
```

Public repositories work without signing in, at GitHub's anonymous limit of
60 requests per hour. A big PR uses roughly 25 of them. For private repos and
5,000 requests per hour, add a personal access token in Settings. A classic
token with `repo` scope works, or a fine-grained token with read access to
pull requests and contents. The token is stored in the system keychain.

## Opening links in the app

The app registers the `pr://` and `reader://` schemes on macOS, iOS and Android. GitHub
PR links map one to one, and `/changes` or `/files` links open the Files tab:

```sh
open "pr://github.com/owner/repo/pull/123/changes"
```

No app can claim `https://github.com` links on macOS, because those always go
to the default browser. To route PR links automatically, use a link router
such as [Finicky](https://github.com/johnste/finicky) as the default browser,
with a `~/.finicky.js` like this:

```js
export default {
  defaultBrowser: "Arc", // your normal browser
  handlers: [{ match: "github.com/*/*/pull/*", browser: "de.reonic.prReader" }],
};
```

On Android, add github.com under App info › Open by default to open PR links
in the app.

## Tests

```sh
flutter test                 # unit tests + widget tests at phone/tablet/foldable/desktop sizes
                             # (screenshots are written to build/screenshots/)

# On-device performance run against a real giant PR:
flutter drive --profile -d macos \
  --driver test_driver/integration_test.dart \
  --target integration_test/giant_pr_test.dart
# results: build/integration/report.json and real_pr.png
```

## Layout

```
lib/
  main.dart                 app, theme mode, routes (/owner/repo/pull/123[/files])
  src/github/               REST client, models, PR reference parsing
  src/diff/                 patch parser, local line diff, row layout, tokenizer
  src/data/                 per-PR session (progressive loading), viewed state
  src/app/                  settings, services
  src/ui/diff/              diff view, custom sliver, rows, file tree, files tab
  src/ui/pr/                PR screen, conversation, commits
  src/ui/home/, settings/   home, repo PR list, settings
```

## Not in v1

Writing (comments, reviews, approvals), expanding unchanged context around
hunks, per-commit diffs, GitHub Enterprise hosts, and OAuth sign-in. OAuth
needs a registered GitHub OAuth app; for now a personal access token is used.
