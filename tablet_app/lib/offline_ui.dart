import 'package:flutter/material.dart';

import 'offline_threads.dart';
import 'strings.dart';

class OfflineThreadTile extends StatelessWidget {
  const OfflineThreadTile({
    super.key,
    required this.store,
    required this.job,
    required this.onOpen,
  });
  final OfflineThreads store;
  final OfflineThread job;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(
      job.complete ? Icons.offline_pin_outlined : Icons.downloading,
    ),
    title: Text(job.title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${tr(job.status)} · ${tr('Pages')} ${job.pages.length}/${job.totalPages} · ${tr('Images')} ${job.assets.length}/${job.sources.length}',
        ),
        if (job.pending)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: LinearProgressIndicator(value: job.progress),
          ),
        if (job.error != null) Text(tr(job.error!)),
      ],
    ),
    onTap: job.pages.containsKey(1) ? onOpen : null,
    trailing: PopupMenuButton<String>(
      tooltip: tr('More'),
      onSelected: (action) async {
        if (action == 'retry') await store.retry(job);
        if (action == 'pause') await store.pause(job);
        if (action == 'remove' && context.mounted) {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(tr('Remove offline thread')),
              content: Text(job.title),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(tr('Cancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(tr('Remove')),
                ),
              ],
            ),
          );
          if (confirmed == true) await store.remove(job);
        }
      },
      itemBuilder: (_) => [
        if (job.pending)
          PopupMenuItem(
            value: 'pause',
            child: ListTile(
              leading: const Icon(Icons.pause),
              title: Text(tr('Pause')),
            ),
          ),
        if (!job.pending && !job.complete)
          PopupMenuItem(
            value: 'retry',
            child: ListTile(
              leading: const Icon(Icons.refresh),
              title: Text(tr('Retry')),
            ),
          ),
        PopupMenuItem(
          value: 'remove',
          child: ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(tr('Remove')),
          ),
        ),
      ],
    ),
  );
}

class OfflineThreadsPage extends StatelessWidget {
  const OfflineThreadsPage({
    super.key,
    required this.store,
    required this.onOpen,
  });
  final OfflineThreads store;
  final ValueChanged<OfflineThread> onOpen;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Text(tr('Offline')),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        children: [
          if (store.readOnly)
            ListTile(title: Text(tr('Library recovery required'))),
          if (store.jobs.isEmpty) ListTile(title: Text(tr('Nothing here'))),
          for (final job in store.jobs)
            OfflineThreadTile(
              store: store,
              job: job,
              onOpen: () {
                Navigator.pop(context);
                onOpen(job);
              },
            ),
        ],
      ),
    ),
  );
}
