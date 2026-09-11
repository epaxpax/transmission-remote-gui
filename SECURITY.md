# Security Policy

## Reporting a vulnerability

Please report security issues **privately** through GitHub's
[private vulnerability reporting](https://github.com/epaxpax/transmission-remote-gui/security/advisories/new)
rather than opening a public issue.

This is a small, single-maintainer project, so please allow a few days for a first
response. If a report is valid, the fix ships in the next release and you are credited
in the advisory unless you ask otherwise.

## Supported versions

Only the latest release receives fixes. There are no maintenance branches.

## Scope

The app is a remote control client — it holds credentials and talks to a server you
configure, so the areas most worth scrutiny are:

- **Stored credentials.** Transmission RPC passwords go into the macOS Keychain; server
  definitions (host, port, path, username) are stored as JSON in Application Support.
- **Client certificates.** An optional `.p12` may be configured per server for mTLS
  against a reverse proxy.
- **Transport.** RPC runs over HTTP or HTTPS to a host you specify, with Basic
  authentication and Transmission's `X-Transmission-Session-Id` handshake.
- **Server-controlled input.** Torrent names, tracker URLs, error strings and file paths
  all come from the daemon and are rendered in the UI.

## Not vulnerabilities

- **The app is ad-hoc signed, not notarized.** macOS Gatekeeper will warn on first
  launch, and `spctl` rejects the bundle. This is a known consequence of shipping
  without a paid Apple Developer account; it is documented in the README and the
  Homebrew cask's caveats.
- **Plain HTTP to a Transmission daemon** when the user configures it that way. Use
  HTTPS, or a reverse proxy, if the connection crosses an untrusted network.
- **The BitTorrent protocol itself**, and anything the Transmission daemon does. Report
  those to [transmission/transmission](https://github.com/transmission/transmission).
