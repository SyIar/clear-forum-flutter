import 'book_ui.dart';
import 'books.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'adaptive.dart';
import 'account.dart';
import 'login.dart';
import 'download_ui.dart';
import 'diagnostics_ui.dart';
import 'downloads.dart';
import 'library.dart';
import 'forum_identity.dart';
import 'forum_search.dart';

import 'package:html/parser.dart' as html;

import 'models.dart';
import 'offline_threads.dart';
import 'offline_ui.dart';
import 'parsers.dart';
import 'reader.dart';
import 'session.dart';
import 'site.dart';
import 'strings.dart';

class ForumTabletApp extends StatelessWidget {
  const ForumTabletApp({super.key, required this.site, required this.library});
  final ForumSite site;
  final LibraryStore library;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: tr(site.name),
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh'),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('en'), Locale('zh')],
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: site.color),
      scaffoldBackgroundColor: const Color(0xFFF6F8FA),
      appBarTheme: const AppBarThemeData(centerTitle: false),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: site.color,
        brightness: Brightness.dark,
      ),
      appBarTheme: const AppBarThemeData(centerTitle: false),
    ),
    home: ForumShell(site: site, library: library),
  );
}

class ForumShell extends StatefulWidget {
  const ForumShell({
    super.key,
    required this.site,
    required this.library,
    this.session,
  });
  final ForumSite site;
  final LibraryStore library;
  final ForumSession? session;
  @override
  State<ForumShell> createState() => _ForumShellState();
}

class _ForumShellState extends State<ForumShell> {
  late final _session = widget.session ?? ForumSession(widget.site);
  late final _books = BookLibrary(widget.library.preferences, _session);
  late final _offline = OfflineThreads(_session);
  OfflineThread? _selectedOffline;
  final _masterScroll = ScrollController();
  final _readerKey = GlobalKey();
  final _masterKey = GlobalKey();
  final List<ForumPage> _stack = [];
  final List<ForumEntry> _entries = [];
  final Set<Uri> _loaded = {};
  ForumPage? _page;
  Uri? _selected, _next, _listTarget;
  PageCapture? _selectedCapture;
  bool _busy = false, _more = false, _directory = false;
  int _request = 0, _tab = 0, _authGeneration = 0;
  String? _error;
  @override
  void initState() {
    super.initState();
    _masterScroll.addListener(_onScroll);
    if (widget.site.module == Module.south) unawaited(_offline.resume());
    unawaited(
      _openList(widget.site.home).then((_) {
        if (mounted) unawaited(_checkUpdates());
      }),
    );
  }

  Future<void> _checkUpdates({bool manual = false}) async {
    if (widget.site.module == Module.bookhouse) {
      await _books.updateAll(manual: manual);
    } else {
      await widget.library.check((url) async {
        final capture = await _session.fetch(url);
        if (capture.cached) throw const ReaderFailure(FailureKind.network);
        return PageParser(widget.site).parse(capture.html, capture.url);
      }, manual: manual);
    }
  }

  @override
  void dispose() {
    _books.dispose();
    _offline.dispose();
    _request++;
    _masterScroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_masterScroll.hasClients && _masterScroll.position.extentAfter < 500) {
      unawaited(_loadMore());
    }
  }

  Future<void> _openList(Uri url, {bool remember = false}) async {
    final request = ++_request;
    if (remember && _page != null) _stack.add(_page!);
    setState(() {
      _busy = true;
      _error = null;
      _listTarget = url;
      if (url != widget.site.home) _directory = true;
    });
    try {
      final capture = await _session.fetch(url);
      final page = PageParser(widget.site).parse(capture.html, capture.url);
      if (!mounted || request != _request) return;
      if (page.kind == PageKind.posts) {
        setState(() {
          _selectedOffline = null;
          _selected = page.url;
          _selectedCapture = capture;
          _busy = false;
        });
        return;
      }
      setState(() {
        _page = page;
        _entries.clear();
        _entries.addAll(page.entries);
        _next = page.next;
        _loaded.clear();
        _loaded.add(page.url);
      });
      if (_masterScroll.hasClients) _masterScroll.jumpTo(0);
    } catch (error) {
      if (mounted && request == _request) {
        setState(
          () => _error = tr(
            error is ReaderFailure && error.kind == FailureKind.login
                ? 'Sign in required'
                : 'Page unavailable',
          ),
        );
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Future<void> _loadMore() async {
    final next = _next;
    if (_busy || _more || next == null || _loaded.contains(next)) return;
    final request = _request;
    setState(() => _more = true);
    try {
      final capture = await _session.fetch(next);
      final page = PageParser(widget.site).parse(capture.html, capture.url);
      if (!mounted || request != _request) return;
      setState(() {
        final seen = _entries.map((e) => e.url).toSet();
        _entries.addAll(page.entries.where((e) => seen.add(e.url)));
        _next = page.next;
        _loaded.add(next);
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _error = tr('Page unavailable'));
      }
    } finally {
      if (mounted && request == _request) setState(() => _more = false);
    }
  }

  Future<void> _link(Uri link) async {
    _selectedOffline = null;
    final url = widget.site.canonical(link);
    if (widget.site.readable(url)) {
      final thread = widget.site.module == Module.simp
          ? url.path.startsWith('/threads/') || url.path.startsWith('/posts/')
          : widget.site.module == Module.south
          ? url.path == '/read.php'
          : url.queryParameters['act'] == 'threadview';
      if (thread) {
        final book = _books.bookFor(url);
        if (book != null && book.cachePending) unawaited(_books.cacheAll(book));
        setState(() {
          _selected = url;
          _selectedCapture = null;
          _tab = _tab == 2 ? 0 : _tab;
        });
      } else {
        await _openList(url, remember: true);
      }
      return;
    }
    if (widget.site.module == Module.south &&
        widget.site.sameOrigin(url) &&
        url.path == '/job.php' &&
        (url.query.startsWith('action-download-') ||
            url.queryParameters['action'] == 'download')) {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri('$url'),
      );
      await DownloadManager.instance.enqueue(
        FileRequest(
          url,
          'attachment',
          referer: '${_selected ?? widget.site.home}',
          cookie: cookies.map((c) => '${c.name}=${c.value}').join('; '),
        ),
      );
      if (mounted) setState(() => _tab = 2);
      return;
    }
    if (!validDownloadUrl(url)) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(tr('Browser')),
              onTap: () => Navigator.pop(context, 'browser'),
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(tr('Download')),
              onTap: () => Navigator.pop(context, 'download'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'browser') await _browser(url);
    if (action == 'download' && mounted) {
      await promptDownload(context, initial: '$url');
    }
  }

  Future<void> _browser([Uri? target]) async {
    final capture = await Navigator.push<PageCapture>(
      context,
      MaterialPageRoute(
        builder: (_) => SiteBrowser(
          session: _session,
          url: target ?? _listTarget ?? _page?.url ?? widget.site.home,
        ),
      ),
    );
    if (capture == null || !mounted) return;
    final page = PageParser(widget.site).parse(capture.html, capture.url);
    setState(() {
      _error = null;
      if (page.kind == PageKind.posts) {
        _selectedOffline = null;
        _selected = page.url;
        _selectedCapture = capture;
      } else {
        _page = page;
        _listTarget = page.url;
        _entries.clear();
        _entries.addAll(page.entries);
        _next = page.next;
      }
    });
  }

  Future<void> _signIn() async {
    final success = await forumSignIn(context, _session);
    if (!mounted || !success) return;
    setState(() {
      _selectedCapture = null;
      _authGeneration++;
    });
    await _openList(_listTarget ?? _page?.url ?? widget.site.home);
  }

  void _account() {
    if (_session.account.value.signedIn) {
      _browser(widget.site.home);
    } else {
      _signIn();
    }
  }

  Widget _accountTile() => ValueListenableBuilder<ForumAccount>(
    valueListenable: _session.account,
    builder: (context, account, _) => ListTile(
      leading: Icon(
        account.signedIn ? Icons.account_circle : Icons.person_outline,
      ),
      title: Text(
        account.signedIn && account.name.isNotEmpty
            ? account.name
            : tr(account.signedIn ? 'Account' : 'Login'),
      ),
      subtitle: Text(
        tr(switch (account.status) {
          AccountStatus.signedIn => 'Signed in',
          AccountStatus.guest => 'Not signed in',
          AccountStatus.unknown => 'Account status unknown',
        }),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: _account,
    ),
  );

  Future<void> _search({bool link = false}) async {
    final field = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(link ? 'Open link' : 'Search')),
        content: SizedBox(
          width: 440,
          child: TextField(
            controller: field,
            autofocus: true,
            keyboardType: link ? TextInputType.url : TextInputType.text,
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
            child: Text(tr('Open')),
          ),
        ],
      ),
    );
    field.dispose();
    if (value == null || value.trim().isEmpty || !mounted) return;
    if (link) {
      final uri = Uri.tryParse(value.trim());
      if (uri != null) await _link(uri);
    } else {
      final url = widget.site.search(value.trim());
      if (widget.site.module == Module.bookhouse) {
        await _openList(url, remember: true);
      } else {
        final request = ++_request;
        if (_page != null) _stack.add(_page!);
        setState(() {
          _directory = true;
          _busy = true;
          _error = null;
          _entries.clear();
          _next = null;
          _listTarget = ForumSearch.formUrl(widget.site);
        });
        try {
          final capture = await _session.search(SearchQuery(value.trim()));
          final page = PageParser(widget.site).parse(capture.html, capture.url);
          if (!mounted || request != _request) return;
          setState(() {
            _page = page;
            _listTarget = page.url;
            _entries.addAll(page.entries);
            _next = page.next;
            _loaded.clear();
            _loaded.add(page.url);
          });
        } catch (error) {
          if (mounted && request == _request) {
            setState(
              () => _error = error is SearchNotice
                  ? error.message
                  : tr(
                      error is ReaderFailure && error.kind == FailureKind.login
                          ? 'Sign in required'
                          : error is ReaderFailure &&
                                error.kind == FailureKind.verification
                          ? 'Login or verify in browser'
                          : 'Search failed',
                    ),
            );
          }
        } finally {
          if (mounted && request == _request) setState(() => _busy = false);
        }
      }
    }
  }

  void _back() {
    if (_stack.isEmpty) {
      setState(() => _directory = false);
      return;
    }
    final old = _stack.removeLast();
    setState(() {
      _request++;
      _busy = false;
      _more = false;
      _error = null;
      _page = old;
      _listTarget = old.url;
      _entries.clear();
      _entries.addAll(old.entries);
      _next = old.next;
      if (old.url == widget.site.home) _directory = false;
    });
  }

  Future<void> _updates() async {
    await tabletSheet(
      context,
      ListenableBuilder(
        listenable: widget.library,
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
                    if (widget.library.checking)
                      LinearProgressIndicator(
                        value: widget.library.totalChecks == 0
                            ? null
                            : widget.library.completedChecks /
                                  widget.library.totalChecks,
                      ),
                    if (widget.library.currentCheck != null)
                      ListTile(title: Text(widget.library.currentCheck!)),
                    for (final author in widget.library.authors.values)
                      ListTile(
                        title: Text(author.name),
                        subtitle: Text(
                          tr(
                            widget
                                    .library
                                    .updateStatus['author:${author.id}'] ??
                                'Pending',
                          ),
                        ),
                      ),
                    for (final entry in [
                      ...widget.library.bookmarks,
                      ...widget.library.history.take(10),
                    ])
                      ListTile(
                        title: Text(entry.title, maxLines: 2),
                        subtitle: Text(
                          tr(
                            widget.library.updateStatus[widget.site.threadKey(
                                  entry.url,
                                )] ??
                                'Pending',
                          ),
                        ),
                        trailing:
                            widget.library.updateStatus[widget.site.threadKey(
                                  entry.url,
                                )] ==
                                'Loading'
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
                    onPressed: widget.library.checking
                        ? null
                        : () => _checkUpdates(manual: true),
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
  }

  Widget _entry(ForumEntry entry, {bool library = false}) => Material(
    color: _selected == entry.url
        ? Theme.of(context).colorScheme.secondaryContainer
        : Colors.transparent,
    child: InkWell(
      onTap: () => _link(
        library && widget.library.bookmarks.contains(entry)
            ? widget.library.destination(entry)
            : entry.url,
      ),
      onLongPress: () => _entryMenu(entry),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.tags.isNotEmpty) ...[
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final tag in entry.tags)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tag,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 7),
            ],
            if (entry.thumbnail != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    '${entry.thumbnail}',
                    height: 100,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(),
                  ),
                ),
              ),
            Text(
              entry.title,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(height: 1.45),
            ),
            if (library && widget.library.stateFor(entry.url) != null) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  if (widget.library.stateFor(entry.url)!.viewed != null)
                    Text(
                      '${tr('Read floor')} ${widget.library.stateFor(entry.url)!.viewed}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  if (widget.library.stateFor(entry.url)!.latest != null)
                    Text(
                      '${tr('Latest floor')} ${widget.library.stateFor(entry.url)!.latest}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  if (widget.library.stateFor(entry.url)!.updated)
                    Text(
                      tr('Updated'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ],
            if (entry.subtitle.isNotEmpty || entry.date.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  if (entry.date.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        entry.date,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
  Future<void> _entryMenu(ForumEntry entry) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.site.module == Module.bookhouse)
              ListTile(
                leading: const Icon(Icons.auto_stories_outlined),
                title: Text(tr('Follow book')),
                onTap: () {
                  Navigator.pop(context);
                  followBook(this.context, _books, entry);
                },
              ),
            ListTile(title: Text(entry.title, maxLines: 2)),
            if (widget.library.bookmarks.contains(entry))
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(tr('Rename')),
                onTap: () {
                  Navigator.pop(context);
                  _rename(entry);
                },
              ),
            ListTile(
              leading: Icon(
                widget.library.bookmarked(entry.url)
                    ? Icons.bookmark_remove_outlined
                    : Icons.bookmark_add_outlined,
              ),
              title: Text(
                tr(
                  widget.library.bookmarked(entry.url)
                      ? 'Remove bookmark'
                      : 'Add bookmark',
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                widget.library.toggle(entry);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rename(ForumEntry entry) async {
    final field = TextEditingController(text: entry.title);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Rename')),
        content: TextField(controller: field, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: Text(tr('Done')),
          ),
        ],
      ),
    );
    field.dispose();
    if (value != null) await widget.library.rename(entry, value);
  }

  Widget _master() => !_directory
      ? _library()
      : Column(
          children: [
            if (widget.site.supportsLogin) _accountTile(),
            if (widget.site.module == Module.bookhouse)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: SingleChildScrollView(
                  child: BookShelf(library: _books, onOpen: _link),
                ),
              ),
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  if (_directory)
                    IconButton(
                      tooltip: tr('Previous'),
                      onPressed: _back,
                      icon: const Icon(Icons.arrow_back),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Text(
                        _page?.title == 'Search results'
                            ? tr('Search results')
                            : _page?.title ?? tr('Forums'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Refresh'),
                    onPressed: _busy
                        ? null
                        : () => _openList(
                            _listTarget ?? _page?.url ?? widget.site.home,
                          ),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null && _entries.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    if (widget.site.supportsLogin)
                      TextButton(onPressed: _signIn, child: Text(tr('Login'))),
                  ],
                ),
              ),
            Expanded(
              child: _entries.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(widget.site.icon, size: 48),
                            const SizedBox(height: 16),
                            Text(
                              _error ?? tr(_busy ? 'Loading' : 'Nothing here'),
                              textAlign: TextAlign.center,
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              if (widget.site.supportsLogin)
                                FilledButton.icon(
                                  onPressed: _signIn,
                                  icon: const Icon(Icons.person_outline),
                                  label: Text(tr('Login')),
                                ),
                              FilledButton.tonal(
                                onPressed: _browser,
                                child: Text(tr('Browser')),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () =>
                          _openList(_page?.url ?? widget.site.home),
                      child: ListView.separated(
                        controller: _masterScroll,
                        itemCount: _entries.length + 1,
                        itemBuilder: (context, i) => i == _entries.length
                            ? _more
                                  ? const Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    )
                                  : const SizedBox(height: 24)
                            : _entry(_entries[i]),
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 16, endIndent: 16),
                      ),
                    ),
            ),
          ],
        );
  Widget _library() => ListenableBuilder(
    listenable: Listenable.merge([widget.library, _offline]),
    builder: (context, _) => ListView(
      children: [
        if (widget.site.supportsLogin) _accountTile(),
        ListTile(
          leading: Icon(widget.site.icon),
          title: Text(tr('Browse forums')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => setState(() => _directory = true),
        ),
        if (widget.library.readOnly)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(tr('Library recovery required')),
          ),
        if (widget.site.module == Module.bookhouse)
          BookShelf(library: _books, onOpen: _link),
        if (widget.site.module != Module.bookhouse)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Library'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: tr('Update status'),
                  onPressed: _updates,
                  icon: widget.library.checking
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                ),
                IconButton(
                  tooltip: tr('Import bookmarks'),
                  onPressed: _importBookmarks,
                  icon: const Icon(Icons.playlist_add),
                ),
              ],
            ),
          ),
        if (widget.library.authors.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              tr('Followed authors'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final author in widget.library.authors.values) ...[
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(author.name),
              onTap: () => _link(widget.site.authorTopics(author.id)!),
              trailing: IconButton(
                tooltip: tr('Unfollow author'),
                icon: const Icon(Icons.person_remove_outlined),
                onPressed: () => widget.library.unfollow(author.id),
              ),
            ),
            for (final topic in author.topics)
              ListTile(
                title: Text(
                  topic.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: widget.library.isUnread(topic.url)
                    ? Badge(label: Text(tr('New')))
                    : const Icon(Icons.chevron_right),
                onTap: () => _link(topic.url),
              ),
          ],
        ],
        if (widget.site.module == Module.south) ...[
          ListTile(
            title: Text(tr('Offline')),
            trailing: TextButton(
              onPressed: () => tabletSheet(
                context,
                OfflineThreadsPage(store: _offline, onOpen: _openOffline),
              ),
              child: Text(tr('Show all')),
            ),
          ),
          if (_offline.readOnly)
            ListTile(title: Text(tr('Library recovery required'))),
          if (_offline.jobs.isEmpty) ListTile(title: Text(tr('Nothing here'))),
          for (final job in _offline.jobs.take(5))
            OfflineThreadTile(
              store: _offline,
              job: job,
              onOpen: () => _openOffline(job),
            ),
          for (final entry in widget.library.offline.where(
            (entry) => _offline.forUrl(entry.url) == null,
          ))
            ListTile(
              title: Text(entry.title, maxLines: 2),
              subtitle: Text(tr('Legacy text cache')),
              trailing: IconButton(
                tooltip: tr('Save thread'),
                icon: const Icon(Icons.download_outlined),
                onPressed: () => _offline.enqueue(entry.url, entry.title),
              ),
            ),
        ],
        for (final section in [
          if (widget.site.module != Module.bookhouse)
            ('Bookmarks', widget.library.bookmarks),
          ('History', widget.library.history),
        ]) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr(section.$1),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                if (section.$1 == 'History' && section.$2.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(tr('Clear history')),
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
                      if (confirmed == true) {
                        await widget.library.clearHistory();
                      }
                    },
                    child: Text(tr('Clear')),
                  ),
              ],
            ),
          ),
          if (section.$2.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr('Nothing here')),
            ),
          for (final entry
              in (_tab == 0
                  ? section.$2.take(section.$1 == 'Offline' ? 5 : 10)
                  : section.$2))
            if (!widget.library.updatesOnly ||
                widget.library.stateFor(entry.url)?.updated == true)
              _entry(entry, library: true),
          if (_tab == 0 && section.$2.length > 5)
            TextButton(
              onPressed: () => setState(() => _tab = 1),
              child: Text(tr('Show all')),
            ),
        ],
      ],
    ),
  );
  void _openOffline(OfflineThread job) {
    setState(() {
      _selectedOffline = job;
      _selected = job.root;
      _selectedCapture = null;
      _tab = 0;
    });
  }

  void _offlineLink(Uri url) {
    if (_selectedOffline != null &&
        widget.site.sameThread(url, _selectedOffline!.root) &&
        !widget.site.filtered(url)) {
      setState(() {
        _selected = url;
        _selectedCapture = null;
      });
    } else {
      _link(url);
    }
  }

  Future<void> _importBookmarks() async {
    final field = TextEditingController();
    final source = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Import bookmarks')),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: field,
            minLines: 5,
            maxLines: 12,
            decoration: InputDecoration(hintText: tr('Paste bookmarks hint')),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: Text(tr('Import')),
          ),
        ],
      ),
    );
    field.dispose();
    if (source == null || !mounted) return;
    final entries = <ForumEntry>[];
    final seen = <Uri>{};
    for (final a in html.parse(source).querySelectorAll('a[href]')) {
      final url = widget.site.resolve(
        a.attributes['href'],
        widget.site.home,
        internal: true,
      );
      if (url != null && seen.add(url)) {
        entries.add(
          ForumEntry(
            title: a.text.trim().isEmpty ? url.path : a.text.trim(),
            url: url,
          ),
        );
      }
    }
    for (final match in RegExp(r'''https?://[^\s<>"']+''').allMatches(source)) {
      final url = widget.site.resolve(
        match[0],
        widget.site.home,
        internal: true,
      );
      if (url != null && seen.add(url)) {
        entries.add(ForumEntry(title: url.path, url: url));
      }
    }
    try {
      final count = await widget.library.importBookmarks(entries);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${tr('Imported')} $count')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Library recovery required'))),
        );
      }
    }
  }

  Widget _settings() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      if (widget.site.supportsLogin) ...[
        Text(tr('Account'), style: Theme.of(context).textTheme.titleLarge),
        _accountTile(),
        const Divider(),
        const SizedBox(height: 20),
      ],
      Text(tr('Reading'), style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 20),
      ListenableBuilder(
        listenable: widget.library,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${tr('Text size')} ${widget.library.textSize.round()}'),
            Slider(
              value: widget.library.textSize,
              min: 15,
              max: 28,
              divisions: 13,
              onChanged: widget.library.fontSize,
            ),
          ],
        ),
      ),
      ListTile(
        leading: const Icon(Icons.language),
        title: Text(tr('Browser')),
        onTap: () => _browser(widget.site.home),
      ),
      ListTile(
        leading: const Icon(Icons.info_outline),
        title: Text(tr('About')),
        subtitle: Text(tr('Private library')),
      ),
      ListTile(
        leading: const Icon(Icons.block),
        title: Text(tr('Blocked authors')),
        onTap: () => tabletSheet(
          context,
          ListenableBuilder(
            listenable: widget.library,
            builder: (context, _) => ListView(
              children: [
                for (final entry in widget.library.blocked.entries)
                  ListTile(
                    title: Text(entry.value),
                    trailing: TextButton(
                      onPressed: () => widget.library.unblock(entry.key),
                      child: Text(tr('Unblock')),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final rail = TabletLayout.rail(size.maxWidth);
      final split = TabletLayout.split(size.maxWidth - (rail ? 81 : 0));
      final labels = ['Home', 'Library', 'Downloads', 'Settings'];
      final icons = [
        widget.site.icon,
        Icons.bookmarks_outlined,
        Icons.download_outlined,
        Icons.settings_outlined,
      ];
      final master = KeyedSubtree(
        key: _masterKey,
        child: _tab == 1 ? _library() : _master(),
      );
      final detail = KeyedSubtree(
        key: _readerKey,
        child: _selected == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.site.icon,
                      size: 60,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      tr('Select a thread'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              )
            : ThreadReader(
                key: ValueKey(
                  '$_selected:$_authGeneration:${_selectedOffline?.folder}',
                ),
                url: _selected!,
                session: _session,
                library: widget.library,
                onLink: _selectedOffline == null ? _link : _offlineLink,
                onSignIn: widget.site.supportsLogin ? _signIn : null,
                capture: _selectedCapture,
                books: widget.site.module == Module.bookhouse ? _books : null,
                offlineStore: widget.site.module == Module.south
                    ? _offline
                    : null,
                snapshot: _selectedOffline,
              ),
      );
      return PopScope(
        canPop: _selected == null || split,
        onPopInvokedWithResult: (popped, result) {
          if (!popped) setState(() => _selected = null);
        },
        child: Scaffold(
          appBar: _tab == 2
              ? null
              : AppBar(
                  title: Text(tr(widget.site.name)),
                  leading: !split && _selected != null
                      ? BackButton(
                          onPressed: () => setState(() => _selected = null),
                        )
                      : null,
                  actions: [
                    if (widget.site.supportsLogin)
                      ValueListenableBuilder<ForumAccount>(
                        valueListenable: _session.account,
                        builder: (context, account, _) => TextButton.icon(
                          onPressed: _account,
                          icon: Icon(
                            account.signedIn
                                ? Icons.account_circle
                                : Icons.person_outline,
                          ),
                          label: Text(
                            tr(account.signedIn ? 'Account' : 'Login'),
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: tr('Search'),
                      onPressed: _search,
                      icon: const Icon(Icons.search),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'diagnostics') {
                          tabletSheet(
                            context,
                            DiagnosticsPage(session: _session),
                          );
                          return;
                        }
                        if (value == 'browser') {
                          _browser();
                        } else {
                          _search(link: true);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'diagnostics',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.bug_report_outlined),
                            title: Text(tr('Diagnostics')),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'browser',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.language),
                            title: Text(tr('Browser')),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'link',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.link),
                            title: Text(tr('Open link')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
          body: SafeArea(
            top: _tab == 2,
            bottom: false,
            child: Row(
              children: [
                if (rail)
                  NavigationRail(
                    selectedIndex: _tab,
                    onDestinationSelected: (i) => setState(() => _tab = i),
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (var i = 0; i < labels.length; i++)
                        NavigationRailDestination(
                          icon: Icon(icons[i]),
                          label: Text(tr(labels[i])),
                        ),
                    ],
                  ),
                if (rail) const VerticalDivider(width: 1),
                Expanded(
                  child: IndexedStack(
                    index: _tab >= 2 ? _tab - 1 : 0,
                    children: [
                      LayoutBuilder(
                        builder: (context, width) => Row(
                          children: [
                            Offstage(
                              offstage: !split && _selected != null,
                              child: SizedBox(
                                width: split
                                    ? TabletLayout.masterWidth(width.maxWidth)
                                    : width.maxWidth,
                                child: master,
                              ),
                            ),
                            if (split) const VerticalDivider(width: 1),
                            if (split || _selected != null)
                              Expanded(child: detail),
                          ],
                        ),
                      ),
                      const DownloadsPage(),
                      _settings(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: rail
              ? null
              : NavigationBar(
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  destinations: [
                    for (var i = 0; i < labels.length; i++)
                      NavigationDestination(
                        icon: Icon(icons[i]),
                        label: tr(labels[i]),
                      ),
                  ],
                ),
        ),
      );
    },
  );
}
