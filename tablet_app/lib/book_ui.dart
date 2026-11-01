import 'dart:async';

import 'package:flutter/material.dart';

import 'adaptive.dart';
import 'books.dart';
import 'forum_identity.dart';
import 'models.dart';
import 'strings.dart';

Future<void> followBook(
  BuildContext context,
  BookLibrary library,
  ForumEntry entry,
) async {
  final title = TextEditingController(text: library.titleFor(entry));
  final author = TextEditingController(text: entry.subtitle);
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Follow book')),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('Book follow hint')),
            const SizedBox(height: 16),
            TextField(
              controller: title,
              decoration: InputDecoration(labelText: tr('Book title')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: author,
              decoration: InputDecoration(labelText: tr('Author')),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(tr('Confirm')),
        ),
      ],
    ),
  );
  if (accepted == true &&
      title.text.trim().isNotEmpty &&
      author.text.trim().isNotEmpty) {
    await library.follow(entry, title.text.trim(), author.text.trim());
  }
  title.dispose();
  author.dispose();
}

class BookShelf extends StatelessWidget {
  const BookShelf({super.key, required this.library, required this.onOpen});
  final BookLibrary library;
  final ValueChanged<Uri> onOpen;

  Future<void> _status(BuildContext context) => tabletSheet(
    context,
    ListenableBuilder(
      listenable: library,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(tr('Update status')),
          automaticallyImplyLeading: false,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(tr('Updates checked hourly')),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final book in library.books)
                    ListTile(
                      title: Text(book.title),
                      subtitle: Text(tr(book.status ?? 'Pending')),
                      trailing: book.status == 'Loading'
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                    ),
                ],
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: library.checking
                      ? null
                      : () => library.updateAll(manual: true),
                  icon: const Icon(Icons.refresh),
                  label: Text(tr('Check updates')),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tr('Following'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: tr('Update status'),
                onPressed: () => _status(context),
                icon: const Icon(Icons.sync),
              ),
            ],
          ),
        ),
        for (final book in library.books)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
            subtitle: Text(
              '${tr('Read to')} ${book.readChapter ?? book.current?.first ?? 0}  |  ${tr('Latest')} ${book.latest}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            onTap: () {
              final url = book.position ?? book.chapters.firstOrNull?.entry.url;
              if (url != null) onOpen(url);
            },
            onLongPress: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              constraints: const BoxConstraints(maxWidth: 560),
              builder: (context) => SafeArea(
                child: ListTile(
                  leading: const Icon(Icons.bookmark_remove_outlined),
                  title: Text(tr('Remove')),
                  onTap: () {
                    Navigator.pop(context);
                    library.remove(book);
                  },
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class ChapterSheet extends StatefulWidget {
  const ChapterSheet({
    super.key,
    required this.library,
    required this.book,
    required this.onOpen,
  });
  final BookLibrary library;
  final FollowedBook book;
  final ValueChanged<Uri> onOpen;
  @override
  State<ChapterSheet> createState() => _ChapterSheetState();
}

class _ChapterSheetState extends State<ChapterSheet> {
  final _search = TextEditingController();
  bool _searching = false;
  double? _index;
  int _request = 0;
  List<(ForumEntry, String)>? _results;
  @override
  void dispose() {
    _request++;
    _search.dispose();
    super.dispose();
  }

  Future<void> _query(String value) async {
    final request = ++_request;
    final results = await widget.library.searchCache(widget.book, value);
    if (mounted && request == _request) setState(() => _results = results);
  }

  void _open(Uri url) {
    Navigator.pop(context);
    widget.onOpen(url);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) {
      final book = widget.book;
      final extraCount = book.chapters
          .where((c) => c.extra)
          .fold(0, (n, c) => c.last > n ? c.last : n);
      final count = (book.latest + extraCount).clamp(1, 200000);
      final current =
          ((book.readChapter ?? book.current?.first ?? 1) +
                  (book.current?.extra == true ? book.latest : 0))
              .clamp(1, count);
      final selected = (_index ?? current.toDouble()).round().clamp(1, count);
      final extra = selected > book.latest;
      final number = extra ? selected - book.latest : selected;
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: tr('Cached search'),
            onPressed: () => setState(() => _searching = !_searching),
            icon: const Icon(Icons.search),
          ),
          title: Text(tr('Chapters')),
          actions: [
            widget.library.caching.contains(book)
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: tr('Cache all chapters'),
                    onPressed: () => unawaited(widget.library.cacheAll(book)),
                    icon: const Icon(Icons.download_for_offline_outlined),
                  ),
          ],
        ),
        body: Column(
          children: [
            if (_searching)
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  onSubmitted: _query,
                  decoration: InputDecoration(
                    hintText: tr('Cached search'),
                    suffixIcon: IconButton(
                      onPressed: () => _query(_search.text),
                      icon: const Icon(Icons.search),
                    ),
                  ),
                ),
              ),
            if (!_searching && book.chapters.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Text(
                      '${tr(extra ? 'Extra' : 'Chapter')} $number',
                      maxLines: 2,
                    ),
                    Slider(
                      value: selected.toDouble(),
                      min: 1,
                      max: count > 1 ? count.toDouble() : 2,
                      divisions: count > 1 ? count - 1 : null,
                      onChanged: count <= 1
                          ? null
                          : (v) => setState(() => _index = v),
                      onChangeEnd: (v) {
                        final isExtra = v.round() > book.latest;
                        final url = widget.library.jumpTo(
                          book,
                          isExtra ? v.round() - book.latest : v.round(),
                          extra: isExtra,
                        );
                        if (url != null) {
                          _open(url);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(tr('Chapter not found'))),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: _searching
                    ? (_results?.length ?? 0)
                    : book.chapters.length,
                itemBuilder: (context, i) {
                  final entry = _searching
                      ? _results![i].$1
                      : book.chapters[i].entry;
                  return ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    selected: widget.library.session.site.sameThread(
                      entry.url,
                      book.position ?? Uri(),
                    ),
                    title: Text(entry.title),
                    subtitle: _searching
                        ? Text(
                            _results![i].$2,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    onTap: () => _open(entry.url),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
