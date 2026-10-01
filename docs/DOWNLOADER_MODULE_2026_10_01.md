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
- CI run [36855927417](https://github.com/SyIar/clear-forum-flutter/actions/runs/36855927417) passed for source commit `12bc880b9eec7139209fd274ba3484a47d267f40`: 353 ForumCore tests, 20 TiebaCore tests, and the Release iPhoneOS build (1065).
- No simulator was used; visual acceptance remains on a physical device.

## Delivery

- Package: `D:\workspace\sideloadly-setup\ForumLite-0.3.0-1065-unsigned.ipa` (56,219,094 bytes).
- SHA-256: `7da40d6e3b8cc4311af7e2eae19b02fa56802a58150ae9d7519047d9964da72a`.
- Verified the CI artifact checksum, archive integrity, source/build metadata, iPhoneOS ARM64 binary, bundled fonts/localization, and ForumUI resources. The package is unsigned and ready for the existing sideload workflow.
