import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'adaptive.dart';
import 'downloads.dart';
import 'media_viewer.dart';
import 'strings.dart';

Future<void> promptDownload(BuildContext context, {String initial = ''}) async {
  final field = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Add download')),
      content: SizedBox(
        width: 440,
        child: TextField(
          controller: field,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(hintText: tr('Paste an HTTP link')),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, field.text),
          child: Text(tr('Download')),
        ),
      ],
    ),
  );
  field.dispose();
  if (value == null || !context.mounted) return;
  try {
    final url = Uri.parse(value.trim());
    await DownloadManager.instance.resolve(url);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('Download failed'))));
    }
  }
}

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: Text(tr('Downloads')),
        actions: [
          IconButton(
            tooltip: tr('Add download'),
            onPressed: () => promptDownload(context),
            icon: const Icon(Icons.add_link),
          ),
        ],
        bottom: TabBar(
          tabs: [
            Tab(text: tr('Queue')),
            Tab(text: tr('Files')),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: DownloadManager.instance,
        builder: (context, _) {
          final manager = DownloadManager.instance;
          return TabBarView(
            children: [
              Column(
                children: [
                  if (manager.resolving) const LinearProgressIndicator(),
                  Expanded(
                    child: manager.tasks.isEmpty
                        ? Center(child: Text(tr('No downloads')))
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: manager.tasks.length,
                            separatorBuilder: (_, _) => const Divider(),
                            itemBuilder: (context, i) {
                              final item = manager.tasks[i];
                              final active =
                                  item.state == 'downloading' ||
                                  item.state == 'queued';
                              return ListTile(
                                leading: Icon(
                                  item.state == 'complete'
                                      ? Icons.task_alt
                                      : Icons.download_outlined,
                                ),
                                title: Text(
                                  item.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 6),
                                    Text(
                                      '${tr(switch (item.state) {
                                        'complete' => 'Complete',
                                        'queued' => 'Queued',
                                        'downloading' => 'Downloading',
                                        'paused' => 'Paused',
                                        _ => 'Failed',
                                      })}  ${formatBytes(item.received)} / ${formatBytes(item.total)}',
                                    ),
                                    if (active) ...[
                                      const SizedBox(height: 8),
                                      LinearProgressIndicator(
                                        value: item.total > 0
                                            ? (item.received / item.total)
                                                  .clamp(0, 1)
                                            : null,
                                      ),
                                    ],
                                    if (item.error.isNotEmpty)
                                      Text(
                                        item.error,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                                onTap: item.state == 'complete'
                                    ? () => openFile(context, File(item.path), [
                                        File(item.path),
                                      ])
                                    : null,
                                trailing: item.state == 'complete'
                                    ? null
                                    : IconButton(
                                        tooltip: tr(
                                          active ? 'Pause' : 'Resume',
                                        ),
                                        onPressed: () => manager.action(
                                          active ? 'pause' : 'resume',
                                          item.id,
                                        ),
                                        icon: Icon(
                                          active
                                              ? Icons.pause
                                              : Icons.play_arrow,
                                        ),
                                      ),
                              );
                            },
                          ),
                  ),
                ],
              ),
              manager.directory == null
                  ? Center(child: Text(tr('File browser unavailable')))
                  : FilesPane(path: manager.directory!),
            ],
          );
        },
      ),
    ),
  );
}

Future<void> openFile(
  BuildContext context,
  File file,
  List<FileSystemEntity> siblings,
) async {
  if (isImage(file.path) || isVideo(file.path)) {
    final media = siblings
        .whereType<File>()
        .where((f) => isImage(f.path) || isVideo(f.path))
        .map((f) => f.path)
        .toList();
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MediaViewer(
          items: media,
          initialIndex: media.indexOf(file.path).clamp(0, media.length - 1),
        ),
      ),
    );
  } else {
    try {
      await DownloadManager.instance.openExternal(file.path);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('Page unavailable'))));
      }
    }
  }
}

class FilesPane extends StatefulWidget {
  const FilesPane({super.key, required this.path});
  final String path;
  @override
  State<FilesPane> createState() => _FilesPaneState();
}

class _FilesPaneState extends State<FilesPane> {
  late Future<List<FileSystemEntity>> _entries = localFiles(widget.path);
  late String _completed = _completionKey;
  String get _completionKey => DownloadManager.instance.tasks
      .where((task) => task.state == 'complete')
      .map((task) => task.path)
      .join('|');
  @override
  void initState() {
    super.initState();
    DownloadManager.instance.addListener(_downloadsChanged);
  }

  @override
  void dispose() {
    DownloadManager.instance.removeListener(_downloadsChanged);
    super.dispose();
  }

  void _downloadsChanged() {
    final completed = _completionKey;
    if (completed == _completed) return;
    _completed = completed;
    if (mounted) _reload();
  }

  void _reload() => setState(() => _entries = localFiles(widget.path));
  Future<void> _open(
    FileSystemEntity entry,
    List<FileSystemEntity> siblings,
  ) async {
    if (entry is Directory) {
      var target = entry;
      var visited = <String>{};
      while (visited.add(target.path)) {
        final files = await localFiles(target.path);
        if (files.length == 1 && files.single is Directory) {
          target = files.single as Directory;
        } else {
          break;
        }
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: Text(target.path.split(Platform.pathSeparator).last),
            ),
            body: FilesPane(path: target.path),
          ),
        ),
      );
    } else if (entry is File && mounted) {
      await openFile(context, entry, siblings);
    }
    if (mounted) _reload();
  }

  Future<void> _delete(FileSystemEntity entry) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete')),
        content: Text(
          '${tr('Confirm delete')}\n${entry.path.split(Platform.pathSeparator).last}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final root = Directory(DownloadManager.instance.directory!).absolute.path;
    final resolved = await entry.resolveSymbolicLinks();
    if (!resolved.startsWith('$root${Platform.pathSeparator}')) return;
    if (DownloadManager.instance.tasks.any(
      (t) =>
          const ['downloading', 'queued'].contains(t.state) &&
          (t.path == resolved ||
              t.path.startsWith('$resolved${Platform.pathSeparator}')),
    )) {
      return;
    }
    await entry.delete(recursive: entry is Directory);
    if (mounted) _reload();
  }

  Future<void> _menu(FileSystemEntity entry) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                entry.path.split(Platform.pathSeparator).last,
                maxLines: 2,
              ),
            ),
            if (entry is File)
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: Text(tr('Export')),
                onTap: () {
                  Navigator.pop(context);
                  SharePlus.instance.share(
                    ShareParams(files: [XFile(entry.path)]),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(tr('Delete')),
              onTap: () {
                Navigator.pop(context);
                _delete(entry);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _storage() async {
    final files = await Directory(widget.path)
        .list(recursive: true, followLinks: false)
        .where((e) => e is File && !e.path.endsWith('.part'))
        .cast<File>()
        .toList();
    final sizes = <String, int>{};
    for (final f in files) {
      sizes[f.path] = await f.length();
    }
    files.sort((a, b) => sizes[b.path]!.compareTo(sizes[a.path]!));
    if (!mounted) return;
    await tabletSheet(
      context,
      Scaffold(
        appBar: AppBar(
          title: Text(
            '${tr('Storage')} ${formatBytes(sizes.values.fold(0, (a, b) => a + b))}',
          ),
          automaticallyImplyLeading: false,
        ),
        body: ListView.builder(
          itemCount: files.length,
          itemBuilder: (context, i) => ListTile(
            title: Text(files[i].path.substring(widget.path.length + 1)),
            subtitle: Text(formatBytes(sizes[files[i].path]!)),
            trailing: IconButton(
              tooltip: tr('Delete'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                Navigator.pop(context);
                await _delete(files[i]);
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                tr('Newest'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            IconButton(
              tooltip: tr('Storage'),
              onPressed: _storage,
              icon: const Icon(Icons.data_usage_outlined),
            ),
            IconButton(
              tooltip: tr('Refresh'),
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      Expanded(
        child: FutureBuilder<List<FileSystemEntity>>(
          future: _entries,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final entries = snapshot.data!;
            if (entries.isEmpty) return Center(child: Text(tr('Nothing here')));
            return LayoutBuilder(
              builder: (context, size) => GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: (size.maxWidth / 180).floor().clamp(2, 6),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: .9,
                ),
                itemCount: entries.length,
                itemBuilder: (context, i) {
                  final entry = entries[i];
                  final name = entry.path.split(Platform.pathSeparator).last;
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _open(entry, entries),
                      onLongPress: () => _menu(entry),
                      child: Column(
                        children: [
                          Expanded(
                            child: entry is File && isImage(entry.path)
                                ? Image.file(
                                    entry,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    cacheWidth: 360,
                                    errorBuilder: (_, _, _) =>
                                        const Icon(Icons.broken_image_outlined),
                                  )
                                : Center(
                                    child: Icon(
                                      entry is Directory
                                          ? Icons.folder_outlined
                                          : isVideo(entry.path)
                                          ? Icons.movie_outlined
                                          : Icons.insert_drive_file_outlined,
                                      size: 48,
                                    ),
                                  ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    ],
  );
}
