import 'book_ui.dart';
import 'books.dart';

import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';

import 'adaptive.dart';
import 'download_ui.dart';
import 'library.dart';
import 'forum_identity.dart';
import 'media_viewer.dart';
import 'models.dart';
import 'offline_threads.dart';
import 'parsers.dart';
import 'session.dart';
import 'site.dart';
import 'south_purchase.dart';
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
    this.offlineStore,
    this.snapshot,
  });
  final Uri url;
  final ForumSession session;
  final LibraryStore library;
  final ValueChanged<Uri> onLink;
  final PageCapture? capture;
  final BookLibrary? books;
  final VoidCallback? onSignIn;
  final OfflineThreads? offlineStore;
  final OfflineThread? snapshot;

  @override
  State<ThreadReader> createState() => _ThreadReaderState();
}

class _ThreadReaderState extends State<ThreadReader> {
  final _scroll = ScrollController();
  final Map<Uri, GlobalKey> _markers = {};
  final Map<String, GlobalKey> _postMarkers = {};
  final Map<String, GlobalKey> _paragraphMarkers = {};
  final Map<Uri, BookSlice> _slices = {};
  Timer? _visibilityTimer;
  bool _prepending = false;
  bool _trimming = false;
  final List<ForumPage> _pages = [];
  @visibleForTesting
  int get retainedPageCount => _pages.length;
  final Set<String> _loaded = {};
  final _purchases = PurchaseService();
  final Set<String> _freeAttempts = {};
  bool _buying = false;
  bool _busy = true, _appending = false, _saving = false, _cached = false;
  String? _error;
  bool _previousFailed = false;
  Uri? _next, _previous;
  int _generation = 0;
  bool _usedCapture = false;
  ForumSite get site => widget.session.site;
  bool get _offline => widget.snapshot != null;
  Map<String, String> get _assets =>
      _offline ? widget.offlineStore!.localAssets(widget.snapshot!) : const {};
  Future<PageCapture> _fetch(Uri url) => _offline
      ? widget.offlineStore!.capture(widget.snapshot!, url)
      : widget.session.fetch(url);
  Uri? _nextPage(ForumPage page) => _offline
      ? (page.pageNumber < widget.snapshot!.totalPages
            ? site.pageUrl(widget.snapshot!.root, page.pageNumber + 1)
            : null)
      : widget.books?.adjacent(page.url, 1) ?? page.next;
  ImageProvider? _avatar(Uri? url) {
    if (url == null) return null;
    if (!_offline) return CachedNetworkImageProvider('$url');
    final path = _assets['$url'];
    return path == null ? null : FileImage(File(path));
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_position);
    widget.library.addListener(_libraryChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    _visibilityTimer?.cancel();
    widget.library.removeListener(_libraryChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _libraryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _pages.clear();
      _loaded.clear();
      _slices.clear();
      _markers.clear();
      _postMarkers.clear();
      _paragraphMarkers.clear();
      _appending = false;
      _prepending = false;
      _trimming = false;
    });
    try {
      final initial = _usedCapture || _offline
          ? null
          : widget.capture ??
                (widget.books?.bookFor(widget.url) != null
                    ? await widget.session.cached(widget.url)
                    : null);
      _usedCapture = true;
      final capture = initial ?? await _fetch(widget.url);
      final page = PageParser(site).parse(capture.html, capture.url);
      if (page.kind != PageKind.posts || page.posts.isEmpty) {
        throw const ReaderFailure(FailureKind.unsupported);
      }
      if (!mounted || generation != _generation) return;
      _slice(page);
      setState(() {
        _pages.add(page);
        _loaded.add('${page.url}');
        _next = _nextPage(page);
        _previous = widget.books?.adjacent(page.url, -1) ?? page.previous;
        _cached = capture.cached;
      });
      await widget.library.observePage(page, live: !capture.cached);
      await widget.library.visit(
        ForumEntry(
          title: page.title,
          url: page.url,
          subtitle: page.posts.firstOrNull?.author ?? '',
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final anchor = widget.url.fragment;
        final publication = widget.books?.publication(page.url);
        int? paragraph = int.tryParse(
          RegExp(r'^novel-p-(\d+)$').firstMatch(anchor)?[1] ?? '',
        );
        final chapter = int.tryParse(
          RegExp(r'^chapter-(\d+)$').firstMatch(anchor)?[1] ?? '',
        );
        if (publication != null && chapter != null && page.posts.isNotEmpty) {
          paragraph = ChapterAnchors(
            page.posts.first.blocks,
            publication,
          ).paragraph(chapter);
          if (paragraph == null && chapter == publication.first) paragraph = 0;
          if (paragraph == null) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(tr('Chapter not found'))));
          }
        }
        final target =
            (paragraph == null
                    ? _postMarkers['${page.url.removeFragment()}:$anchor']
                    : _paragraphMarkers[_paragraphKey(page, paragraph)])
                ?.currentContext;
        if (anchor.isNotEmpty && target != null) {
          Scrollable.ensureVisible(target);
        }
        _recordVisible();
      });
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
      if (mounted && generation == _generation && !_offline) {
        unawaited(_unlockFree());
      }
    }
  }

  void _position() {
    if (_prepending || _trimming) return;
    _visibilityTimer ??= Timer(const Duration(milliseconds: 150), () {
      _visibilityTimer = null;
      _recordVisible();
      unawaited(_trimWindow());
    });
    if (_scroll.hasClients &&
        _scroll.offset < 150 &&
        _scroll.position.userScrollDirection == ScrollDirection.forward) {
      unawaited(_prepend());
    }
    if (_scroll.hasClients &&
        _slices.isEmpty &&
        _scroll.position.maxScrollExtent > 0 &&
        _scroll.offset >= _scroll.position.maxScrollExtent * .9) {
      unawaited(_append());
    }
  }

  void _recordVisible() {
    if (!mounted || _prepending || _trimming || _busy) return;
    final viewport = context.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return;
    final top = viewport.localToGlobal(Offset.zero).dy + 54;
    final bottom =
        viewport.localToGlobal(Offset.zero).dy + viewport.size.height;
    if (widget.books != null) {
      Uri? visiblePosition;
      int? visibleChapter;
      for (final page in _pages) {
        final publication = widget.books!.publication(page.url);
        if (publication == null || page.posts.isEmpty) continue;
        final blocks = page.posts.first.blocks;
        for (var index = 0; index < blocks.length; index++) {
          final box = _paragraphMarkers[_paragraphKey(page, index)]
              ?.currentContext
              ?.findRenderObject();
          if (box is! RenderBox || !box.hasSize) continue;
          final y = box.localToGlobal(Offset.zero).dy;
          if (y + box.size.height > top + 24 && y < bottom - 24) {
            final anchors = ChapterAnchors(blocks, publication);
            visiblePosition ??= page.url.replace(fragment: 'novel-p-$index');
            visibleChapter ??= anchors.chapterAt(index, publication.first);
            final slice = _slices[page.url];
            if (page == _pages.last &&
                slice != null &&
                (index - slice.start + 1) * 10 >=
                    (slice.end - slice.start) * 9) {
              unawaited(_append());
            }
          }
        }
      }
      if (visiblePosition != null) {
        unawaited(
          widget.books!.record(visiblePosition, chapter: visibleChapter),
        );
        return;
      }
    }
    final visible = <(ForumPage, ForumPost)>[];
    for (final page in _pages) {
      for (final post in page.posts) {
        if (widget.library.blocked.containsKey(post.authorID)) continue;
        final box = _postMarkers['${page.url.removeFragment()}:${post.id}']
            ?.currentContext
            ?.findRenderObject();
        if (box is! RenderBox || !box.hasSize) continue;
        final y = box.localToGlobal(Offset.zero).dy;
        if (y < bottom - 24 && y + box.size.height > top + 24) {
          visible.add((page, post));
        }
      }
    }
    final numbered = visible.where((v) => v.$2.floor != null).toList();
    if (numbered.isNotEmpty) {
      final maximum = numbered
          .map((v) => v.$2.floor!)
          .reduce((a, b) => a > b ? a : b);
      unawaited(
        widget.library.recordVisible(
          numbered.first.$1,
          numbered.first.$2,
          visibleMaximum: maximum,
        ),
      );
    }
  }

  Future<void> _prepend() async {
    final previous = _previous;
    if (_busy ||
        _prepending ||
        _appending ||
        previous == null ||
        _loaded.contains('$previous')) {
      return;
    }
    final generation = _generation;
    setState(() => _prepending = true);
    try {
      final capture = await _fetch(previous);
      final page = PageParser(site).parse(capture.html, capture.url);
      _validateAdjacent(previous, page);
      if (!mounted || generation != _generation) return;
      _slice(page, boundary: _pages.first, before: true);
      final oldHeight = _scroll.position.maxScrollExtent;
      final oldOffset = _scroll.offset;
      setState(() {
        _pages.insert(0, page);
        _loaded.add('$previous');
        _previous = widget.books?.adjacent(page.url, -1) ?? page.previous;
        _error = null;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(
        (oldOffset + _scroll.position.maxScrollExtent - oldHeight).clamp(
          0,
          _scroll.position.maxScrollExtent,
        ),
      );
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _previousFailed = true;
          _error = tr('Page unavailable');
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _prepending = false);
        await _trimWindow();
      }
    }
  }

  Future<void> _append() async {
    final next = _next;
    if (_busy ||
        _prepending ||
        _appending ||
        next == null ||
        _loaded.contains('$next')) {
      return;
    }
    final generation = _generation;
    setState(() => _appending = true);
    try {
      final cached = !_offline && widget.books?.bookFor(next) != null
          ? await widget.session.cached(next)
          : null;
      final capture = cached ?? await _fetch(next);
      final page = PageParser(site).parse(capture.html, capture.url);
      _validateAdjacent(next, page);
      if (!mounted || generation != _generation) return;
      _slice(page, boundary: _pages.last);
      setState(() {
        _pages.add(page);
        _loaded.add('$next');
        _next = _nextPage(page);
        _error = null;
      });
      await widget.library.observePage(page, live: !capture.cached);
      await WidgetsBinding.instance.endOfFrame;
      await _trimWindow();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _previousFailed = false;
          _error = tr('Page unavailable');
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _appending = false);
        if (!_offline) unawaited(_unlockFree());
      }
    }
  }

  void _validateAdjacent(Uri requested, ForumPage page) {
    if (page.kind != PageKind.posts ||
        page.pageNumber != site.pageNumber(requested) ||
        !site.sameThread(page.url, requested) ||
        site.filtered(page.url) != site.filtered(requested)) {
      throw const ReaderFailure(FailureKind.unsupported);
    }
  }

  void _slice(ForumPage page, {ForumPage? boundary, bool before = false}) {
    final publication = widget.books?.publication(page.url);
    if (publication == null || page.posts.isEmpty) return;
    var slice = BookSlice(publication, page.posts.first.blocks);
    final existing = _slices[boundary?.url];
    if (existing != null) slice = slice.joined(existing, before: before);
    _slices[page.url] = slice;
  }

  Future<void> _trimWindow() async {
    if (!mounted ||
        _trimming ||
        _prepending ||
        _pages.length <= 5 ||
        !_scroll.hasClients) {
      return;
    }
    final viewport = context.findRenderObject();
    if (viewport is! RenderBox) return;
    final top = viewport.localToGlobal(Offset.zero).dy;
    final bottom = top + viewport.size.height;
    double? marker(ForumPage page) {
      final box = _markers[page.url]?.currentContext?.findRenderObject();
      return box is RenderBox && box.hasSize
          ? box.localToGlobal(Offset.zero).dy
          : null;
    }

    final secondY = marker(_pages[1]);
    final lastY = marker(_pages.last);
    final removeFirst = secondY != null && secondY < top - 160;
    final removeLast = !removeFirst && lastY != null && lastY > bottom + 160;
    if (!removeFirst && !removeLast) return;
    final anchor = removeFirst ? _pages[1] : _pages.first;
    final before = marker(anchor);
    final generation = _generation;
    _trimming = true;
    final removed = removeFirst ? _pages.first : _pages.last;
    setState(() {
      _pages.remove(removed);
      _loaded.removeWhere(
        (u) =>
            site.sameThread(Uri.parse(u), removed.url) &&
            site.pageNumber(Uri.parse(u)) == removed.pageNumber,
      );
      if (removeFirst) _previous = removed.url;
      if (removeLast) _next = removed.url;
      _markers.remove(removed.url);
      _slices.remove(removed.url);
      _paragraphMarkers.removeWhere(
        (key, _) => key.startsWith('${removed.url.removeFragment()}:'),
      );
      for (final post in removed.posts) {
        _postMarkers.remove('${removed.url.removeFragment()}:${post.id}');
      }
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || generation != _generation) {
      _trimming = false;
      return;
    }
    final after = marker(anchor);
    if (before != null && after != null && _scroll.hasClients) {
      _scroll.jumpTo(
        (_scroll.offset + after - before).clamp(
          0,
          _scroll.position.maxScrollExtent,
        ),
      );
    }
    _trimming = false;
    if (_pages.length > 5) await _trimWindow();
  }

  Future<void> _browser([Uri? url]) async {
    final capture = await Navigator.push<PageCapture>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SiteBrowser(session: widget.session, url: url ?? widget.url),
      ),
    );
    if (capture != null && mounted) {
      widget.onLink(capture.url);
      if (capture.url == widget.url) await _load();
    }
  }

  Future<void> _save() async {
    if (_saving || _pages.isEmpty || widget.offlineStore == null) return;
    setState(() => _saving = true);
    try {
      await widget.offlineStore!.enqueue(widget.url, _pages.first.title);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('Queued'))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('Page unavailable'))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _purchase(PurchaseOffer offer, Uri url) async {
    if (_buying || _offline) return;
    if (offer.cents > 0) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('Buy content')),
          content: Text('${offer.price} SP'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Buy')),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    setState(() => _buying = true);
    final generation = _generation;
    try {
      final fresh = await _purchases.buy(
        offer,
        url,
        load: (target) async {
          if (!mounted || generation != _generation) {
            throw const ReaderFailure(FailureKind.unsupported);
          }
          final capture = await widget.session.fetch(target);
          if (capture.cached) throw const ReaderFailure(FailureKind.network);
          return PageParser(site).parse(capture.html, capture.url);
        },
        submit: (current, target) async {
          if (!mounted || generation != _generation) {
            throw const ReaderFailure(FailureKind.unsupported);
          }
          await widget.session.submitPurchase(current, target);
        },
      );
      if (!mounted || generation != _generation) return;
      final index = _pages.indexWhere(
        (p) =>
            site.sameThread(p.url, fresh.url) &&
            p.pageNumber == fresh.pageNumber,
      );
      if (index >= 0) setState(() => _pages[index] = fresh);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                error is PurchaseIssue
                    ? error.message
                    : 'Purchase result uncertain',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  Future<void> _unlockFree() async {
    if (_buying || _busy || _offline || !mounted) return;
    final generation = _generation;
    final offers = [
      for (final page in _pages)
        for (final offer in purchaseOffers(page))
          if (offer.cents == 0) (page.url, offer),
    ];
    for (final (url, offer) in offers.take(20)) {
      if (!mounted || generation != _generation || _buying) return;
      if (!_freeAttempts.add(offer.id)) continue;
      await _purchase(offer, url);
    }
  }

  Future<void> _jump() async {
    final book = widget.books?.bookFor(widget.url);
    if (book != null) {
      await tabletSheet(
        context,
        ChapterSheet(library: widget.books!, book: book, onOpen: widget.onLink),
      );
      return;
    }
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

  String _paragraphKey(ForumPage page, int index) =>
      '${page.url.removeFragment()}:p$index';
  Widget _body(ForumPage page, ForumPost post, List<String> images) {
    Widget content(List<BodyBlock> blocks) => BodyView(
      blocks: blocks,
      images: images,
      fontSize:
          widget.library.textSize + (site.module == Module.bookhouse ? 1 : 0),
      onLink: widget.onLink,
      page: page.url,
      offline: _offline,
      localAssets: _assets,
      onPurchase: _offline || _buying
          ? null
          : (offer) => _purchase(offer, page.url),
    );
    if (widget.books?.publication(page.url) == null) {
      return content(post.blocks);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (
          var i = _slices[page.url]?.start ?? 0;
          i < (_slices[page.url]?.end ?? post.blocks.length);
          i++
        )
          KeyedSubtree(
            key: _paragraphMarkers.putIfAbsent(
              _paragraphKey(page, i),
              GlobalKey.new,
            ),
            child: content([post.blocks[i]]),
          ),
      ],
    );
  }

  Future<void> _postMenu(ForumPage page, ForumPost post) async {
    final hasAuthor = !_offline && site.authorTopics(post.authorID) != null;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(post.author), subtitle: Text(post.number)),
            for (final item in [
              ('copy', Icons.content_copy, 'Copy text'),
              if (hasAuthor) ...[
                ('only', Icons.person_outline, 'Only this author'),
                ('topics', Icons.forum_outlined, 'Author threads'),
                ('profile', Icons.account_box_outlined, 'Author profile'),
                (
                  'follow',
                  Icons.person_add_alt,
                  widget.library.authors.containsKey(post.authorID)
                      ? 'Unfollow author'
                      : 'Follow author',
                ),
                ('block', Icons.block, 'Block author'),
              ],
            ])
              ListTile(
                leading: Icon(item.$2),
                title: Text(tr(item.$3)),
                onTap: () => Navigator.pop(context, item.$1),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'copy':
        await _copy(post);
      case 'only':
        widget.onLink(site.onlyAuthor(page.url, post.authorID)!);
      case 'topics':
        widget.onLink(site.authorTopics(post.authorID)!);
      case 'profile':
        await _browser(site.authorProfile(post.authorID));
      case 'follow':
        if (widget.library.authors.containsKey(post.authorID)) {
          await widget.library.unfollow(post.authorID);
        } else {
          await widget.library.follow(post);
          unawaited(
            widget.library.check((url) async {
              final capture = await widget.session.fetch(url);
              if (capture.cached) {
                throw const ReaderFailure(FailureKind.network);
              }
              return PageParser(site).parse(capture.html, capture.url);
            }, manual: true),
          );
        }
      case 'block':
        await widget.library.block(post.authorID, post.author);
    }
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
                    if (!_offline)
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
                    if (site.module == Module.south &&
                        !_offline &&
                        widget.offlineStore != null)
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
                  builder: (context, _) => SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_cached)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              tr(_offline ? 'Offline snapshot' : 'Cached copy'),
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
                        if (_prepending)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            ),
                          ),
                        if (site.filtered(widget.url))
                          TextButton.icon(
                            onPressed: () =>
                                widget.onLink(site.threadRoot(widget.url)!),
                            icon: const Icon(Icons.people_outline),
                            label: Text(tr('Show all replies')),
                          ),
                        for (final page in _pages) ...[
                          SizedBox(
                            key: _markers.putIfAbsent(
                              page.url,
                              () => GlobalKey(),
                            ),
                            height: 1,
                          ),
                          if (page.poll != null)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      tr('Poll'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    if (page.poll!.participants != null)
                                      Text(
                                        '${tr('Participants')} ${page.poll!.participants}',
                                      ),
                                    for (final option in page.poll!.options)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Text(
                                              '${option.selected ? '[x] ' : ''}${option.title}${option.votes == null ? '' : ' (${option.votes})'}',
                                            ),
                                            if ((page.poll!.total ?? 0) > 0)
                                              LinearProgressIndicator(
                                                value:
                                                    option.votes! /
                                                    page.poll!.total!,
                                              ),
                                          ],
                                        ),
                                      ),
                                    if (page.poll!.notice.isNotEmpty)
                                      Text(page.poll!.notice),
                                    if (!_offline)
                                      TextButton(
                                        onPressed: () => _browser(page.url),
                                        child: Text(tr('Vote in browser')),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          if ((widget.books?.adjacent(page.url, -1) ??
                                      page.previous) !=
                                  null &&
                              page == _pages.first)
                            SizedBox(height: 1),
                          for (final post in page.posts.where(
                            (p) =>
                                !widget.library.blocked.containsKey(p.authorID),
                          ))
                            Align(
                              key: _postMarkers.putIfAbsent(
                                '${page.url.removeFragment()}:${post.id}',
                                GlobalKey.new,
                              ),
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 760,
                                ),
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
                                                backgroundImage: _avatar(
                                                  post.avatar,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                            ],
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text.rich(
                                                    TextSpan(
                                                      children: [
                                                        TextSpan(
                                                          text: post.author,
                                                        ),
                                                        if (post
                                                                .authorID
                                                                .isNotEmpty &&
                                                            post.authorID ==
                                                                page.originalPosterID)
                                                          const WidgetSpan(
                                                            alignment:
                                                                PlaceholderAlignment
                                                                    .middle,
                                                            child: Padding(
                                                              padding:
                                                                  EdgeInsets.only(
                                                                    left: 4,
                                                                  ),
                                                              child: Icon(
                                                                Icons.person,
                                                                size: 15,
                                                                color:
                                                                    Colors.blue,
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
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
                                              tooltip: tr('More'),
                                              onPressed: () =>
                                                  _postMenu(page, post),
                                              icon: const Icon(
                                                Icons.more_horiz,
                                                size: 20,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        _body(page, post, images),
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
                            onPressed: _previousFailed ? _prepend : _append,
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
    this.offline = false,
    this.localAssets = const {},
    this.onPurchase,
  });
  final List<BodyBlock> blocks;
  final List<String> images;
  final double fontSize;
  final ValueChanged<Uri> onLink;
  final Uri page;
  final bool offline;
  final Map<String, String> localAssets;
  final ValueChanged<PurchaseOffer>? onPurchase;
  Widget _image(Uri url, {BoxFit fit = BoxFit.contain}) {
    final path = localAssets['$url'];
    if (offline) {
      return path == null
          ? SizedBox(
              height: 96,
              child: Center(child: Text(tr('Image not cached'))),
            )
          : Image.file(
              File(path),
              fit: fit,
              cacheWidth: 1400,
              errorBuilder: (_, _, _) => const SizedBox(
                height: 96,
                child: Icon(Icons.broken_image_outlined),
              ),
            );
    }
    return CachedNetworkImage(
      imageUrl: '$url',
      httpHeaders: {'Referer': '$page'},
      fit: fit,
      memCacheWidth: 1400,
      placeholder: (_, _) => const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      ),
      errorWidget: (_, _, _) =>
          const SizedBox(height: 96, child: Icon(Icons.broken_image_outlined)),
    );
  }

  void _gallery(BuildContext context, BodyBlock block) {
    final available = images
        .where((url) => !offline || localAssets.containsKey(url))
        .toList();
    if (!available.contains('${block.url}')) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MediaViewer(
          items: available
              .map((url) => offline ? localAssets[url]! : url)
              .toList(),
          headers: {'Referer': '$page'},
          initialIndex: available.indexOf('${block.url}'),
        ),
      ),
    );
  }

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
                      onTap: () => _gallery(context, block),
                      onLongPress: offline
                          ? null
                          : () => promptDownload(
                              context,
                              initial: '${block.url}',
                            ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _image(block.url!),
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
                offline: offline,
                localAssets: localAssets,
                onPurchase: onPurchase,
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
                  offline: offline,
                  localAssets: localAssets,
                  onPurchase: onPurchase,
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
            BlockKind.purchase => Row(
              children: [
                Expanded(child: Text('${block.offer!.price} SP')),
                FilledButton.tonal(
                  onPressed: onPurchase == null
                      ? null
                      : () => onPurchase!(block.offer!),
                  child: Text(tr(block.offer!.cents == 0 ? 'Unlock' : 'Buy')),
                ),
              ],
            ),
            BlockKind.embeddedMedia => AspectRatio(
              aspectRatio: block.aspectRatio ?? 16 / 9,
              child: InkWell(
                onTap: block.url == null || offline
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
                      _image(block.posterUrl!, fit: BoxFit.cover)
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
    return Text.rich(
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
