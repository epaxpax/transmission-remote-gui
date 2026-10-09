# Show remote downloads in Finder

Mount the daemon's download shares on your Mac first (for example, using Finder's
**Go → Connect to Server**). This feature only translates paths; it does not mount
shares, copy/move files, change the daemon's download directories, or launch files.

## Configure each server

Open **Settings → Servers → Edit → Path Mappings**. Add a remote download folder
and the corresponding local folder. **Browse…** selects an existing local folder;
**Paste Mappings…** imports the classic transgui format, one `remote=local` rule per
line. Imports append to existing mappings and reject duplicate remote folders.

For example:

```text
/srv/downloads/movies=/Volumes/Movies
/srv/downloads/电视=/Volumes/电视
```

Paths must be absolute POSIX paths. Spaces and Unicode names are preserved;
trailing slashes are optional. Rules match complete directory components, and the
most specific matching remote folder wins. `/srv/downloads` does not match
`/srv/downloads2`. Repeated remote roots and `.` / `..` components are rejected.
Mappings are stored with that server in the existing Application Support
configuration, outside the app bundle, so replacing the app normally preserves
them. Older configurations without mappings continue to work.

## Reveal a torrent

Right-click a torrent and choose **Show in Finder**. The action selects a single
file or a multi-file torrent's top-level folder in Finder. For torrents with files
directly in the download directory, it selects that directory. Multiple selected
torrents can be revealed together; every target must resolve successfully before
Finder is activated. The displayed torrent name is not used to guess file paths:
the daemon's current file list and download directory are queried instead.

**Double-click behaviour is unchanged.** Download completion is not required, but
the mapped data must already exist. Magnet links without file metadata cannot be
resolved yet. Partially downloaded files with a different on-disk name (such as a
`.part` suffix) are not guessed.

Missing mappings, unmounted `/Volumes` shares, unavailable files, permission
errors and slow shares have distinct messages. Filesystem checks run off the main
thread with an eight-second deadline; late responses never activate Finder.
Symlinks escaping the mapped local root are refused. If macOS mounts a share under
a different name (for example, `/Volumes/Movies-1`), update the local mapping.

This feature sends only a read-only `torrent-get` request. It does not start, stop,
rename, move or delete torrents. A server switch or replaced torrent invalidates
an outstanding reveal request.

## Verification

`swift run KitTests` includes parser, boundary/longest-match, Unicode/literal
filename, content-root, configuration compatibility, context-menu and read-only
filesystem tests. `swift run LocalizationTests` checks all supported UI languages.
`Scripts/uitest/test_path_mappings.py` uses an isolated app identity and a read-only
loopback mock, never the user's saved server configuration or real torrents.
Its automated mode requires the existing UI-test harness's accessibility helper
(`TRGUI UITest Helper.app`). Use `--interactive` to inspect the same fixtures with
native UI automation or manually when that helper is not installed.
