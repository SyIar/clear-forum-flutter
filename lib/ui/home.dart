import 'package:flutter/material.dart';

import '../core/library.dart';
import '../core/session.dart';
import '../core/site.dart';
import 'reader.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  void _open(BuildContext context, {Uri? url, bool sample = false}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderPage(
          source: sample ? DemoSource() : DeviceSession(),
          url: url,
          demo: sample,
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, ReadingLibrary library) async {
    final entry = await showDialog<SavedPage>(
      context: context,
      builder: (_) => const _BookmarkDialog(),
    );
    if (entry == null || !context.mounted) return;
    if (library.isBookmarked(entry.url)) {
      _message(context, 'This URL is already bookmarked.');
      return;
    }
    try {
      await library.toggleBookmark(entry.url, entry.title);
      if (context.mounted) _message(context, 'Bookmark saved on this device.');
    } catch (_) {
      if (context.mounted) {
        _message(context, 'Could not save the bookmark. Please try again.');
      }
    }
  }

  void _message(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _remove(
    BuildContext context,
    ReadingLibrary library,
    SavedPage entry,
  ) async {
    try {
      await library.toggleBookmark(entry.url, entry.title);
    } catch (_) {
      if (context.mounted) _message(context, 'Could not update bookmarks.');
    }
  }

  Future<void> _clear(BuildContext context, ReadingLibrary library) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear recent reading?'),
        content: const Text('Your bookmarks will stay saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await library.clearRecent();
    } catch (_) {
      if (context.mounted) _message(context, 'Could not clear recent reading.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = LibraryScope.maybeOf(context)!;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'simp lite',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton.filledTonal(
            tooltip: 'Add bookmark',
            onPressed: library.loaded ? () => _add(context, library) : null,
            icon: const Icon(Icons.bookmark_add_outlined),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/branding/app-icon.png',
                        width: 66,
                        height: 66,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pick up where\nyou left off.',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -.5,
                                ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Your links. Your reading space.',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => _open(context, sample: library.sample),
                  icon: const Icon(Icons.explore_outlined),
                  label: Text(
                    library.sample ? 'Explore sample reader' : 'Open forum',
                  ),
                ),
                const SizedBox(height: 12),
                if (library.sample)
                  Text(
                    'Desktop preview uses sample content. Its saved links stay separate from your iPhone library.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (!library.sample)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => _open(context, sample: true),
                      child: const Text('Explore sample reader'),
                    ),
                  ),
                if (!library.loaded && !library.loadFailed)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(),
                  ),
                if (library.loadFailed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Could not load your saved links.'),
                    trailing: TextButton(
                      onPressed: () async {
                        try {
                          await library.load();
                        } catch (_) {}
                      },
                      child: const Text('Retry'),
                    ),
                  ),
                _SectionHeader(
                  title: 'Bookmarks',
                  count: library.bookmarks.length,
                  icon: Icons.bookmark_outline,
                ),
                if (library.bookmarks.isEmpty)
                  const _EmptyCard(
                    icon: Icons.bookmark_add_outlined,
                    title: 'Keep the good ones.',
                    detail: 'Tap the bookmark button on a page, or add a URL from the top right.',
                  ),
                for (final entry in library.bookmarks)
                  _SavedTile(
                    entry: entry,
                    onTap: () =>
                        _open(context, url: entry.url, sample: library.sample),
                    trailing: IconButton(
                      tooltip: 'Remove bookmark',
                      onPressed: () => _remove(context, library, entry),
                      icon: const Icon(Icons.bookmark, size: 21),
                    ),
                  ),
                const SizedBox(height: 12),
                _SectionHeader(
                  title: 'Recent reading',
                  count: library.recent.length,
                  icon: Icons.history,
                  action: library.recent.isEmpty
                      ? null
                      : TextButton(
                          onPressed: () => _clear(context, library),
                          child: const Text('Clear'),
                        ),
                ),
                if (library.recent.isEmpty)
                  const _EmptyCard(
                    icon: Icons.history,
                    title: 'A fresh start.',
                    detail: 'Your last 10 visited forums and threads will appear here.',
                  ),
                for (final entry in library.recent)
                  _SavedTile(
                    entry: entry,
                    onTap: () =>
                        _open(context, url: entry.url, sample: library.sample),
                    trailing: const Icon(Icons.arrow_upward_rounded, size: 18),
                  ),
                const SizedBox(height: 22),
                Text(
                  'Saved locally on this device.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.icon,
    this.action,
  });
  final String title;
  final int count;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Icon(icon, size: 19),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        if (count > 0)
          Text('$count', style: Theme.of(context).textTheme.bodySmall),
        ?action,
      ],
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer
          .withValues(alpha: .5),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(height: 1.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SavedTile extends StatelessWidget {
  const _SavedTile({
    required this.entry,
    required this.onTap,
    required this.trailing,
  });
  final SavedPage entry;
  final VoidCallback onTap;
  final Widget trailing;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        title: Text(
          entry.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          entry.url.path +
              (entry.url.hasFragment ? '#${entry.url.fragment}' : ''),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        onTap: onTap,
        trailing: trailing,
      ),
      const Divider(),
    ],
  );
}

class _BookmarkDialog extends StatefulWidget {
  const _BookmarkDialog();
  @override
  State<_BookmarkDialog> createState() => _BookmarkDialogState();
}

class _BookmarkDialogState extends State<_BookmarkDialog> {
  final _url = TextEditingController();
  final _title = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    super.dispose();
  }

  void _save() {
    final url = ForumSite.resolve(
      _url.text.trim(),
      ForumSite.base,
      internal: true,
    );
    if (url == null) {
      setState(
        () => _error = 'Use an HTTPS forum or thread URL from this site.',
      );
      return;
    }
    Navigator.pop(
      context,
      SavedPage(
        url: url,
        title: _title.text.trim().isEmpty ? url.path : _title.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add bookmark'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _url,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'URL',
              hintText: 'https://simpcity.cr/forums/...',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title (optional)'),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}
