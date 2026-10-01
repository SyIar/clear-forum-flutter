# Standalone downloader module

## Behavior

- Preserve the first three full-width forum cards on the module selector.
- Put Tieba and Downloader in equal-width cards on the fourth row. The downloader card shows only the existing Pika download icon, with an accessible name.
- Push a standalone downloader page with one URL input and an inline submit icon. The keyboard's Go action submits the same input.
- Reuse the existing Gofile, Bunkr, Pixeldrain, Fileditch, and Filester browsers, including folder navigation, serial downloads, torrent-to-magnet actions, and global download management.
- Accept complete HTTP/HTTPS links, upgrading recognized provider HTTP links to HTTPS. Preserve encoded paths and query tokens. Reject malformed input, embedded credentials, and multiple pasted links.
- Unsupported pages retain the input and offer the in-app browser; they are not queued as files. This does not introduce a generic downloader for arbitrary websites.
- The downloader destination is outside forum-specific session environments and the selector's forced dark appearance. Leaving a file browser retains the shared download manager's existing behavior.

## Verification

- Local Swift grammar, localization, design-system, repository-policy, and diff checks passed. Grammar checking is not compilation or type checking.
- Five new Swift tests cover provider aliases, Gofile direct files, HTTP upgrades, encoded signed links, invalid input, and unsupported routes.
- Apple compiler and test results are recorded after CI completes. No simulator was used; visual acceptance remains on a physical device.
