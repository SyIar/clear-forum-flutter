import 'book_ui.dart';
import 'books.dart';

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'adaptive.dart';
import 'download_ui.dart';
import 'library.dart';
import 'media_viewer.dart';
import 'models.dart';
import 'parsers.dart';
import 'session.dart';
import 'site.dart';
import 'strings.dart';

class ThreadReader extends StatefulWidget {
  const ThreadReader({
    super.key,
    required this.url,
    required this.session,
    required this.library,
    required this.onLink,
    this.capture,
    this.books,
    this.onSignIn,
  });
  final Uri url;
  final ForumSession session;
  final LibraryStore library;
  final ValueChanged<Uri> onLink;
  final PageCapture? capture;
  final BookLibrary? books;
  final VoidCallback? onSignIn;

  @override
  State<ThreadReader> createState() => _ThreadReaderState();
}

class _ThreadReaderState extends State<ThreadReader> {
  final _scroll = ScrollController();
  final Map<Uri, GlobalKey> _markers = {};
  final List<ForumPage> _pages = [];
  final Set<String> _loaded = {};
  bool _busy = true, _appending = false, _saving = false, _cached = false;
  String? _error;
  Uri? _next;
  int _generation = 0;
  bool _usedCapture = false;
  ForumSite get site => widget.session.site;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_position);
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _pages.clear();
      _loaded.clear();
    });
    try {
      final initial = _usedCapture
          ? null
          : widget.capture ??
                (widget.books?.bookFor(widget.url) != null
                    ? await widget.session.cached(widget.url)
                    : null);
      _usedCapture = true;
      final capture = initial ?? await widget.session.fetch(widget.url);
      final page = PageParser(site).parse(capture.html, capture.url);
      if (!mounted || generation != _generation) return;
      setState(() {
        _pages.add(page);
        _loaded.add('${page.url}');
        _next = widget.books?.adjacent(page.url, 1) ?? page.next;
        _cached = capture.cached;
      });
      await widget.books?.record(page.url);
      await widget.library.visit(
        ForumEntry(
          title: page.title,
          url: page.url,
          subtitle: page.posts.firstOrNull?.author ?? '',
        ),
      );
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () =>
              _error = error is ReaderFailure && error.kind == FailureKind.login
              ? tr('Sign in required')
              : error is ReaderFailure && error.kind == FailureKind.verification
              ? tr('Login or verify in browser')
              : tr('Page unavailable'),
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  void _position() {
    final box = context.findRenderObject();
    if (box is RenderBox && widget.books != null) {
      final line = box.localToGlobal(Offset.zero).dy + box.size.height * .45;
      Uri? visible;
      for (final page in _pages) {
        final marker = _markers[page.url]?.currentContext?.findRenderObject();
        if (marker is RenderBox &&
            marker.localToGlobal(Offset.zero).dy <= line) {
          visible = page.url;
        }
      }
      if (visible != null) unawaited(widget.books!.record(visible));
    }

    if (_scroll.hasClients &&
        _scroll.position.maxScrollExtent > 0 &&
        _scroll.offset >= _scroll.position.maxScrollExtent * .9) {
      unawaited(_append());
    }
  }

  Future<void> _append() async {
    final next = _next;
    if (_busy || _appending || next == null || _loaded.contains('$next')) {
      return;
    }
    final generation = _generation;
    setState(() => _appending = true);
    try {
      final cached = widget.books?.bookFor(next) != null
          ? await widget.session.cached(next)
          : null;
      final capture = cached ?? await widget.session.fetch(next);
      final page = PageParser(site).parse(capture.html, capture.url);
      if (!mounted || generation != _generation) return;
      setState(() {
        _pages.add(page);
        _loaded.add('$next');
        _next = widget.books?.adjacent(page.url, 1) ?? page.next;
        _error = null;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = tr('Page unavailable'));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _appending = false);
      }
    }
  }

  Future<void> _browser() async {
    final capture = await Navigator.push<PageCapture>(
      context,
      MaterialPageRoute(
        builder: (_) => SiteBrowser(session: widget.session, url: widget.url),
      ),
    );
    if (capture != null && mounted) {
      final page = PageParser(site).parse(capture.html, capture.url);
      setState(() {
        _pages.clear();
        _pages.add(page);
        _next = widget.books?.adjacent(page.url, 1) ?? page.next;
        _error = null;
        _busy = false;
      });
    }
  }

  Future<void> _save() async {
    if (_saving || _pages.isEmpty) return;
    setState(() => _saving = true);
    try {
      var url = site.pageUrl(widget.url, 1);
      final visited = <Uri>{};
      var complete = false;
      while (visited.add(url) && visited.length <= 500) {
        final capture = await widget.session.fetch(url);
        if (capture.cached) throw const ReaderFailure(FailureKind.network);
        final page = PageParser(site).parse(capture.html, capture.url);
        if (page.next == null) {
          complete = true;
          break;
        }
        url = page.next!;
      }
      if (!complete) throw const ReaderFailure(FailureKind.network);
      await widget.library.markOffline(
        ForumEntry(title: _pages.first.title, url: site.pageUrl(widget.url, 1)),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('Page unavailable'))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _jump() async {
    final field = TextEditingController(
      text: '${_pages.firstOrNull?.pageNumber ?? 1}',
    );
    final number = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Jump to page')),
        content: TextField(
          controller: field,
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(field.text)),
            child: Text(tr('Open')),
          ),
        ],
      ),
    );
    field.dispose();
    if (number != null && number > 0) {
      widget.onLink(site.pageUrl(widget.url, number));
    }
  }

  Future<void> _copy(ForumPost post) async {
    String collect(List<BodyBlock> blocks) => blocks
        .map(
          (b) => b.kind == BlockKind.image
              ? ''
              : b.runs.map((r) => r.text).join() +
                    collect(b.children) +
                    (b.kind == BlockKind.code ? b.label : ''),
        )
        .join('\n\n');
    final text = collect(post.blocks);
    await tabletSheet(
      context,
      Scaffold(
        appBar: AppBar(
          title: Text(tr('Copy text')),
          automaticallyImplyLeading: false,
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: text)),
              child: Text(tr('Copy all')),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SelectableText(
            text,
            style: const TextStyle(fontSize: 18, height: 1.6),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _pages.firstOrNull?.title ?? tr('Reading');
    final images = [
      for (final page in _pages)
        for (final post in page.posts) ...imageUrls(post.blocks),
    ];
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            bottom: false,
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
                if (widget.books?.bookFor(widget.url) != null)
                  IconButton(
                    tooltip: tr('Chapters'),
                    onPressed: () => tabletSheet(
                      context,
                      ChapterSheet(
                        library: widget.books!,
                        book: widget.books!.bookFor(widget.url)!,
                        onOpen: widget.onLink,
                      ),
                    ),
                    icon: const Icon(Icons.format_list_numbered),
                  ),
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                IconButton(
                  tooltip: tr(
                    widget.library.bookmarked(widget.url)
                        ? 'Remove bookmark'
                        : 'Add bookmark',
                  ),
                  onPressed: _pages.isEmpty
                      ? null
                      : () => widget.library.toggle(
                          ForumEntry(title: title, url: widget.url),
                        ),
                  icon: Icon(
                    widget.library.bookmarked(widget.url)
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: tr('More'),
                  onSelected: (value) {
                    switch (value) {
                      case 'browser':
                        _browser();
                      case 'refresh':
                        _load();
                      case 'save':
                        _save();
                      case 'top':
                        _scroll.animateTo(
                          0,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        );
                      case 'bottom':
                        _scroll.animateTo(
                          _scroll.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        );
                      case 'jump':
                        _jump();
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'browser',
                      child: ListTile(
                        leading: const Icon(Icons.language),
                        title: Text(tr('Browser')),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'refresh',
                      child: ListTile(
                        leading: const Icon(Icons.refresh),
                        title: Text(tr('Refresh')),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'save',
                      child: ListTile(
                        leading: const Icon(
                          Icons.download_for_offline_outlined,
                        ),
                        title: Text(tr('Save thread')),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'jump',
                      child: ListTile(
                        leading: const Icon(Icons.swap_vert),
                        title: Text(tr('Jump to page')),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'top',
                      child: ListTile(
                        leading: const Icon(Icons.vertical_align_top),
                        title: Text(tr('Top')),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'bottom',
                      child: ListTile(
                        leading: const Icon(Icons.vertical_align_bottom),
                        title: Text(tr('Bottom')),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _busy
              ? const Center(child: CircularProgressIndicator())
              : _pages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined, size: 44),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error ?? tr('Page unavailable'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      if (widget.onSignIn != null) ...[
                        FilledButton.icon(
                          onPressed: widget.onSignIn,
                          icon: const Icon(Icons.person_outline),
                          label: Text(tr('Login')),
                        ),
                        const SizedBox(height: 8),
                      ],
                      FilledButton.tonalIcon(
                        onPressed: _browser,
                        icon: const Icon(Icons.language),
                        label: Text(tr('Browser')),
                      ),
                    ],
                  ),
                )
              : ListenableBuilder(
                  listenable: widget.library,
                  builder: (context, _) => ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 20,
                    ),
                    children: [
                      if (_cached)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            tr('Cached copy'),
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                height: 1.4,
                              ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      for (final page in _pages) ...[
                        SizedBox(
                          key: _markers.putIfAbsent(
                            page.url,
                            () => GlobalKey(),
                          ),
                          height: 1,
                        ),
                        if ((widget.books?.adjacent(page.url, -1) ??
                                    page.previous) !=
                                null &&
                            page == _pages.first)
                          TextButton.icon(
                            onPressed: () => widget.onLink(
                              widget.books?.adjacent(page.url, -1) ??
                                  page.previous!,
                            ),
                            icon: const Icon(Icons.arrow_upward),
                            label: Text(tr('Previous')),
                          ),
                        for (final post in page.posts)
                          Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 760),
                              child: Card(
                                margin: const EdgeInsets.only(bottom: 16),
                                elevation: 0,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          if (post.avatar != null) ...[
                                            CircleAvatar(
                                              radius: 17,
                                              backgroundImage:
                                                  CachedNetworkImageProvider(
                                                    '${post.avatar}',
                                                  ),
                                            ),
                                            const SizedBox(width: 10),
                                          ],
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  post.author,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                if (post.date.isNotEmpty)
                                                  Text(
                                                    post.date,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .labelSmall,
                                                  ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            post.number,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium
                                                ?.copyWith(color: site.color),
                                          ),
                                          IconButton(
                                            tooltip: tr('Copy text'),
                                            onPressed: () => _copy(post),
                                            icon: const Icon(
                                              Icons.more_horiz,
                                              size: 20,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      BodyView(
                                        blocks: post.blocks,
                                        images: images,
                                        fontSize:
                                            widget.library.textSize +
                                            (site.module == Module.bookhouse
                                                ? 1
                                                : 0),
                                        onLink: widget.onLink,
                                        page: page.url,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                      if (_appending)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (_error != null)
                        TextButton(
                          onPressed: _append,
                          child: Text(tr('Retry')),
                        ),
                      if (_next == null)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              tr('At end'),
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

List<String> imageUrls(List<BodyBlock> blocks) => [
  for (final b in blocks)
    if (b.kind == BlockKind.image && b.url != null)
      '${b.url}'
    else
      ...imageUrls(b.children),
];

class BodyView extends StatelessWidget {
  const BodyView({
    super.key,
    required this.blocks,
    required this.images,
    required this.fontSize,
    required this.onLink,
    required this.page,
  });
  final List<BodyBlock> blocks;
  final List<String> images;
  final double fontSize;
  final ValueChanged<Uri> onLink;
  final Uri page;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final block in blocks)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: switch (block.kind) {
            BlockKind.paragraph => RichParagraph(
              runs: block.runs,
              fontSize: fontSize,
              onLink: onLink,
            ),
            BlockKind.image =>
              block.url == null
                  ? const SizedBox()
                  : InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => MediaViewer(
                            items: images,
                            headers: {'Referer': '$page'},
                            initialIndex: images
                                .indexOf('${block.url}')
                                .clamp(0, images.length - 1),
                          ),
                        ),
                      ),
                      onLongPress: () =>
                          promptDownload(context, initial: '${block.url}'),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: '${block.url}',
                          httpHeaders: {'Referer': '$page'},
                          fit: BoxFit.contain,
                          memCacheWidth: 1400,
                          placeholder: (_, _) => const SizedBox(
                            height: 160,
                            child: Center(child: CircularProgressIndicator()),
                          ),
                          errorWidget: (_, _, _) => SizedBox(
                            height: 96,
                            child: IconButton(
                              tooltip: tr('Browser'),
                              onPressed: () => onLink(block.url!),
                              icon: const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                      ),
                    ),
            BlockKind.quote => Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: BodyView(
                blocks: block.children,
                images: images,
                fontSize: fontSize * .9,
                onLink: onLink,
                page: page,
              ),
            ),
            BlockKind.spoiler => ExpansionTile(
              title: Text(block.label),
              children: [
                BodyView(
                  blocks: block.children,
                  images: images,
                  fontSize: fontSize,
                  onLink: onLink,
                  page: page,
                ),
              ],
            ),
            BlockKind.code => SelectableText(
              block.label,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            BlockKind.link => TextButton.icon(
              onPressed: block.url == null ? null : () => onLink(block.url!),
              icon: const Icon(Icons.link),
              label: Text(block.label),
            ),
            BlockKind.embeddedMedia => AspectRatio(
              aspectRatio: block.aspectRatio ?? 16 / 9,
              child: InkWell(
                onTap: block.url == null
                    ? null
                    : () => block.directMedia
                          ? Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => MediaViewer(
                                  items: ['${block.url}'],
                                  headers: {'Referer': '$page'},
                                ),
                              ),
                            )
                          : onLink(block.url!),
                child: Stack(
                  alignment: Alignment.center,
                  fit: StackFit.expand,
                  children: [
                    if (block.posterUrl != null)
                      CachedNetworkImage(
                        imageUrl: '${block.posterUrl}',
                        fit: BoxFit.cover,
                      )
                    else
                      ColoredBox(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                    const Center(
                      child: CircleAvatar(
                        radius: 26,
                        child: Icon(Icons.play_arrow, size: 32),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          },
        ),
    ],
  );
}

class RichParagraph extends StatefulWidget {
  const RichParagraph({
    super.key,
    required this.runs,
    required this.fontSize,
    required this.onLink,
  });
  final List<TextRun> runs;
  final double fontSize;
  final ValueChanged<Uri> onLink;
  @override
  State<RichParagraph> createState() => _RichParagraphState();
}

class _RichParagraphState extends State<RichParagraph> {
  final List<TapGestureRecognizer> _recognizers = [];
  void _clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    return SelectableText.rich(
      TextSpan(
        children: [
          for (final r in widget.runs)
            TextSpan(
              text: r.text,
              style: TextStyle(
                fontWeight: r.bold ? FontWeight.w700 : null,
                fontStyle: r.italic ? FontStyle.italic : null,
                color: r.url != null
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              recognizer: r.url == null
                  ? null
                  : (_recognizers..add(
                          TapGestureRecognizer()
                            ..onTap = () => widget.onLink(r.url!),
                        ))
                        .last,
            ),
        ],
      ),
      style: TextStyle(fontSize: widget.fontSize, height: 1.7),
    );
  }
}
