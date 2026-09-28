import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/library.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/site.dart';
import 'rich_body.dart';
import 'media_widgets.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.source,
    this.url,
    this.initial,
    this.demo = false,
  });
  final PageSource source;
  final Uri? url;
  final ForumPage? initial;
  final bool demo;
  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  ForumPage? _page;
  ReaderFailure? _failure;
  bool _loading = false;
  bool _browserOpen = false;
  bool _mediaOpen = false;
  bool _savingBookmark = false;
  ForumPage? _recordedPage;
  ReadingLibrary? _library;
  int _request = 0;
  late Uri _url;
  final _scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    _url = widget.url ?? widget.initial?.url ?? ForumSite.base;
    _page = widget.initial;
    if (_page == null) _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final library = LibraryScope.maybeOf(context);
    _library = library?.sample == widget.demo ? library : null;
    if (_page != null) _remember(_page!);
  }

  Future<void> _remember(ForumPage page) async {
    final library = _library;
    if (library == null || identical(_recordedPage, page)) return;
    _recordedPage = page;
    try {
      await library.remember(page);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save recent reading.')),
        );
      }
    }
  }

  Future<void> _bookmark() async {
    final library = _library;
    if (library == null || _savingBookmark || _page == null) return;
    setState(() => _savingBookmark = true);
    try {
      await library.toggleBookmark(_url, _page!.title);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save bookmark. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingBookmark = false);
    }
  }

  @override
  void dispose() {
    _request++;
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load([Uri? target]) async {
    final request = ++_request;
    final destination = target ?? _url;
    setState(() {
      _url = destination;
      _loading = true;
      _failure = null;
    });
    try {
      final page = await widget.source.load(destination);
      if (!mounted || request != _request) return;
      setState(() {
        _page = page;
        _url = page.url;
        _loading = false;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _remember(page);
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _failure = error is ReaderFailure
            ? error
            : const ReaderFailure(FailureKind.network);
        _loading = false;
      });
    }
  }

  Future<void> _browser({bool login = false}) async {
    if (_browserOpen || widget.demo) return;
    setState(() => _browserOpen = true);
    try {
      final page = await widget.source.openBrowser(
        login ? ForumSite.base.resolve('/login/') : _url,
      );
      if (!mounted) return;
      if (page != null) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ReaderPage(source: widget.source, url: page.url, initial: page),
          ),
        );
      } else {
        await _load();
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _failure = error is ReaderFailure
              ? error
              : const ReaderFailure(FailureKind.network),
        );
      }
    } finally {
      if (mounted) setState(() => _browserOpen = false);
    }
  }

  void _navigate(Uri url) {
    if (ForumSite.readable(url)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ReaderPage(source: widget.source, url: url, demo: widget.demo),
        ),
      );
    } else {
      _external(url);
    }
  }

  Future<void> _external(Uri url) async {
    if (widget.demo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('External links are disabled in the sample.'),
        ),
      );
      return;
    }
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open link?'),
        content: Text('Open ${url.host} in your browser?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    if (open == true && widget.source is DeviceSession) {
      try {
        await (widget.source as DeviceSession).openExternal(url);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open this link.')),
          );
        }
      }
    }
  }

  Future<void> _openMedia(BodyBlock block) async {
    if (_mediaOpen) return;
    if (!DeviceSession.supported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Video playback is available in the iPhone app.'),
        ),
      );
      return;
    }
    setState(() => _mediaOpen = true);
    try {
      await (widget.source is DeviceSession
              ? widget.source as DeviceSession
              : DeviceSession())
          .playMedia(block);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open this video. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _mediaOpen = false);
    }
  }

  Future<void> _openAddress() async {
    var input = '';
    final address = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open forum link'),
        content: TextField(
          onChanged: (value) => input = value,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'Paste a forum or thread URL',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, input),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    if (!mounted || address == null) return;
    final url = Uri.tryParse(address.trim());
    if (url == null || !ForumSite.readable(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Use an HTTPS forum or thread link from this site.'),
        ),
      );
      return;
    }
    _navigate(url);
  }

  Future<void> _signOut() async {
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear this device session?'),
        content: const Text(
          'This removes the app browser data and closes all open reader pages.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear session'),
          ),
        ],
      ),
    );
    if (clear != true) return;
    ++_request;
    try {
      await widget.source.clearSession();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not clear the session. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Scaffold(
      appBar: AppBar(
        title: Text(page?.kind == PageKind.posts ? 'Thread' : 'Forums'),
        actions: [
          IconButton(
            tooltip: 'Home',
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            icon: const Icon(Icons.home_outlined),
          ),
          if (_library != null)
            IconButton(
              tooltip: _library!.isBookmarked(_url)
                  ? 'Remove bookmark'
                  : 'Bookmark page',
              onPressed:
                  _loading ||
                      _failure != null ||
                      page == null ||
                      _savingBookmark ||
                      !_library!.loaded
                  ? null
                  : _bookmark,
              icon: Icon(
                _library!.isBookmarked(_url)
                    ? Icons.bookmark
                    : Icons.bookmark_border,
              ),
            ),
          IconButton(
            tooltip: 'Open link',
            onPressed: _openAddress,
            icon: const Icon(Icons.link),
          ),
          if (!widget.demo)
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'login':
                    _browser(login: true);
                  case 'site':
                    _browser();
                  case 'clear':
                    _signOut();
                }
              },
              itemBuilder: (_) => [
                if (!widget.demo)
                  const PopupMenuItem(value: 'login', child: Text('Sign in')),
                if (!widget.demo)
                  const PopupMenuItem(
                    value: 'site',
                    child: Text('Open original page'),
                  ),
                if (!widget.demo)
                  const PopupMenuItem(
                    value: 'clear',
                    child: Text('Clear session'),
                  ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (widget.demo)
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.primaryContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: const Text(
                  'SAMPLE CONTENT \u00b7 not connected to your account',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            if (_loading || _browserOpen)
              const LinearProgressIndicator(minHeight: 2),
            if (_failure != null) Expanded(child: _error()),
            if (_failure == null && page != null)
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              page.title,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -.5,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.demo
                                  ? 'Sample reading space'
                                  : page.loggedIn
                                  ? 'Signed in \u00b7 clean view'
                                  : 'Guest \u00b7 sign in for your account',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (page.entries.any((entry) => entry.pinned))
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                          child: Material(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainer,
                            borderRadius: BorderRadius.circular(16),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                for (final entry in page.entries.where(
                                  (e) => e.pinned,
                                ))
                                  ListTile(
                                    dense: true,
                                    minTileHeight: 44,
                                    leading: const Icon(
                                      Icons.push_pin_outlined,
                                      size: 16,
                                    ),
                                    title: Text(
                                      entry.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () => _navigate(entry.url),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      for (final entry in page.entries.where(
                        (e) => !e.pinned,
                      )) ...[
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 2,
                          ),
                          title: Text(
                            entry.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: entry.subtitle.isEmpty
                              ? null
                              : Text(
                                  entry.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          trailing: const Icon(Icons.chevron_right, size: 19),
                          onTap: () => _navigate(entry.url),
                        ),
                        const Divider(indent: 14, endIndent: 14),
                      ],
                      for (final post in page.posts) ...[
                        Padding(
                          key: ValueKey(post.id),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      post.author.isEmpty
                                          ? 'Member'
                                          : post.author,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    post.number,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                              if (post.date.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 2,
                                    bottom: 8,
                                  ),
                                  child: Text(
                                    _date(post.date),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ),
                              RichBody(
                                blocks: post.blocks,
                                imageProvider: widget.demo
                                    ? sampleImageProvider
                                    : networkImageProvider,
                                onLink: _navigate,
                                onMedia: _openMedia,
                              ),
                            ],
                          ),
                        ),
                        const Divider(),
                      ],
                      if (page.posts.isEmpty && page.entries.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('There are no entries on this page.'),
                        ),
                    ],
                  ),
                ),
              ),
            if (_failure == null && page == null && !_loading)
              const Expanded(child: Center(child: Text('Ready to read.'))),
            if (page != null && _failure == null) _pager(page),
          ],
        ),
      ),
    );
  }

  String _date(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    return date == null
        ? value
        : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _pager(ForumPage page) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer
                .withValues(alpha: .86),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: _loading || page.previous == null
                    ? null
                    : () => _load(page.previous),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                'Page ${page.pageNumber}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              IconButton(
                tooltip: 'Refresh page',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 20),
              ),
              IconButton(
                tooltip: 'Next page',
                onPressed: _loading || page.next == null
                    ? null
                    : () => _load(page.next),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _error() {
    final failure = _failure!;
    final message = switch (failure.kind) {
      FailureKind.login => 'Sign in to continue reading.',
      FailureKind.verification => 'The site needs browser verification. Open the page, finish verification, then choose Read page.',
      FailureKind.forbidden => 'This page is not available to the current session. You can check it in the site browser.',
      FailureKind.rateLimit =>
        'The site is limiting requests. Please wait before trying again.',
      FailureKind.unsupported => 'This page cannot be read in clean view yet. You can open the original page.',
      FailureKind.network =>
        'Could not load the page. Check your connection and try again.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chrome_reader_mode_outlined, size: 40),
            const SizedBox(height: 18),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _loading ? null : _load,
              child: const Text('Try again'),
            ),
            if (!widget.demo)
              TextButton(
                onPressed: _browserOpen
                    ? null
                    : () => _browser(login: failure.kind == FailureKind.login),
                child: const Text('Open site browser'),
              ),
          ],
        ),
      ),
    );
  }
}
