import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../platform/baidu_action_page.dart';
import '../widgets/common.dart';
import '../widgets/blocked_content.dart';
import '../widgets/content_cards.dart';
import '../widgets/paged_list.dart';
import 'main_shell.dart';
import 'media_page.dart';
import 'reply_page.dart';

class ThreadPage extends StatefulWidget {
  const ThreadPage({
    super.key,
    required this.threadId,
    this.initialThread,
    this.anchorPostId,
    this.initialPage = 1,
    this.initialOnlyAuthor,
  });
  final String threadId;
  final ThreadSummary? initialThread;
  final String? anchorPostId;
  final int initialPage;
  final bool? initialOnlyAuthor;
  @override
  State<ThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends State<ThreadPage> {
  GlobalKey<PagedListState<Post>> _list = GlobalKey<PagedListState<Post>>();
  ThreadSummary? _thread;
  Forum? _forum;
  Post? _firstPost;
  String? _routeAccountId;
  final _postPages = <String, int>{};
  bool _historyErrorShown = false,
      _useAnchor = true,
      _initialResultApplied = false;
  bool _onlyAuthor = false,
      _reader = false,
      _liked = false,
      _saved = false,
      _busy = false,
      _initialized = false;
  int _sort = 0, _page = 1, _visiblePage = 1;
  @override
  void initState() {
    super.initState();
    _thread = widget.initialThread;
    _forum = widget.initialThread?.forum;
    _liked = _thread?.isLiked ?? false;
    _saved = _thread?.isBookmarked ?? false;
    _page = widget.initialPage;
    _visiblePage = _page;
    _onlyAuthor = widget.initialOnlyAuthor ?? false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final app = AppScope.read(context);
    _routeAccountId = app.session?.userId;
    final settings = app.settings;
    _reader = settings.getBool('readerMode');
    if (_saved) {
      _onlyAuthor =
          widget.initialOnlyAuthor ?? settings.getBool('collectThreadSeeLz');
      _sort = settings.getBool('collectThreadDescSort') ? 1 : 0;
    }
  }

  void _restart({int? page}) => setState(() {
    _page = page ?? 1;
    _visiblePage = _page;
    _useAnchor = false;
    _initialResultApplied = false;
    _postPages.clear();
    _list = GlobalKey<PagedListState<Post>>();
  });

  Future<void> _rememberPost(Post post) async {
    final app = AppScope.read(context);
    if (app.changingAccount || app.session?.userId != _routeAccountId) return;
    final page = _postPages[post.id] ?? _page;
    if (_visiblePage != page) setState(() => _visiblePage = page);
    try {
      await app.local.recordHistory(
        HistoryEntry(
          threadId: widget.threadId,
          title: _thread?.title ?? '',
          forumName: _forum?.name ?? '',
          page: page,
          lastPostId: post.id,
          onlyAuthor: _onlyAuthor,
        ),
      );
    } catch (error) {
      if (mounted && !_historyErrorShown) {
        _historyErrorShown = true;
        notifyUser(context, '${context.l10n.operationFailed}\n$error');
      }
    }
  }

  Future<void> _reply({Post? post, Post? subPost}) async {
    if (!await requireAccount(context) || !mounted) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ReplyPage(
          threadId: widget.threadId,
          forum: _forum ?? const Forum(),
          parentPostId: post?.id,
          subPostId: subPost?.id,
          replyUserId: subPost?.author.id ?? post?.author.id,
          replyUserName: subPost?.author.name ?? post?.author.name ?? '',
        ),
      ),
    );
    if (result == true && mounted) _list.currentState?.reload();
  }

  Future<void> _toggleSaved({String postId = ''}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await performAction(
      context,
      () => AppScope.read(context).api.bookmark(
        threadId: widget.threadId,
        postId: postId,
        remove: postId.isEmpty && _saved,
      ),
    );
    if (mounted) {
      setState(() {
        _busy = false;
        if (ok) _saved = postId.isNotEmpty || !_saved;
      });
    }
  }

  Future<void> _toggleLike() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await performAction(
      context,
      () => AppScope.read(context).api.agree(
        threadId: widget.threadId,
        forumId: _forum?.id ?? '',
        undo: _liked,
      ),
    );
    if (mounted) {
      setState(() {
        _busy = false;
        if (ok) _liked = !_liked;
      });
    }
  }

  Future<void> _jump() async {
    final input = await textPrompt(
      context,
      title: context.l10n.jumpPage,
      value: '$_visiblePage',
      keyboardType: TextInputType.number,
    );
    if (input == null || !mounted) return;
    final page = int.tryParse(input);
    if (page == null || page < 1) {
      notifyUser(context, context.l10n.invalidPage);
      return;
    }
    _restart(page: page);
  }

  Future<void> _deleteThread() async {
    final app = AppScope.read(context);
    if (_thread?.author.id != app.session?.userId || _forum == null) return;
    if (!await confirmAction(
          context,
          context.l10n.deleteThread,
          context.l10n.deleteConfirm,
        ) ||
        !mounted) {
      return;
    }
    final ok = await performAction(
      context,
      () => app.api.deleteThread(forum: _forum!, threadId: widget.threadId),
    );
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final thread = _thread;
    return Scaffold(
      extendBody: usesNativeGlass,
      extendBodyBehindAppBar: usesNativeGlass,
      appBar: GlassAppBar(
        title: GestureDetector(
          onTap: _forum?.name.isNotEmpty == true
              ? () => openForum(context, _forum!.name)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _forum?.name.isNotEmpty == true
                    ? _forum!.name
                    : context.l10n.posts,
                maxLines: 1,
              ),
              Text(
                '${context.l10n.page} $_visiblePage',
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            onPressed: _jump,
            icon: const Icon(Icons.format_list_numbered_rounded),
            tooltip: context.l10n.jumpPage,
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'author':
                  setState(() => _onlyAuthor = !_onlyAuthor);
                  _restart();
                case 'sort':
                  setState(() => _sort = _sort == 0 ? 1 : 0);
                  _restart();
                case 'reader':
                  setState(() => _reader = !_reader);
                  app.settings.setBool('readerMode', _reader);
                case 'share':
                  shareLink(
                    context,
                    'https://tieba.baidu.com/p/${widget.threadId}',
                    title: thread?.title,
                  );
                case 'copy':
                  copyText(
                    context,
                    'https://tieba.baidu.com/p/${widget.threadId}',
                  );
                case 'browser':
                  openExternal(
                    context,
                    'https://tieba.baidu.com/p/${widget.threadId}',
                  );
                case 'refresh':
                  _list.currentState?.reload();
                case 'delete':
                  _deleteThread();
                case 'report':
                  if (_firstPost != null) {
                    reportPost(context, _firstPost!, _forum ?? const Forum());
                  }
              }
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: 'author',
                checked: _onlyAuthor,
                child: Text(context.l10n.onlyAuthor),
              ),
              PopupMenuItem(
                value: 'sort',
                child: Text(
                  _sort == 0
                      ? context.l10n.newestFirst
                      : context.l10n.oldestFirst,
                ),
              ),
              CheckedPopupMenuItem(
                value: 'reader',
                checked: _reader,
                child: Text(context.l10n.readerMode),
              ),
              PopupMenuItem(value: 'share', child: Text(context.l10n.share)),
              PopupMenuItem(value: 'copy', child: Text(context.l10n.copyLink)),
              PopupMenuItem(
                value: 'browser',
                child: Text(context.l10n.openOriginal),
              ),
              PopupMenuItem(
                value: 'refresh',
                child: Text(context.l10n.refresh),
              ),
              if (_firstPost != null)
                PopupMenuItem(
                  value: 'report',
                  child: Text(context.l10n.report),
                ),
              if (app.isLoggedIn && thread?.author.id == app.session?.userId)
                PopupMenuItem(
                  value: 'delete',
                  child: Text(context.l10n.deleteThread),
                ),
            ],
          ),
        ],
      ),
      body: PagedList<Post>(
        key: _list,
        initialPage: _page,
        load: (page) => app.api.threadPosts(
          widget.threadId,
          page: page,
          onlyAuthor: _onlyAuthor,
          sort: _sort,
          anchorPostId:
              _useAnchor &&
                  page == widget.initialPage &&
                  _page == widget.initialPage
              ? widget.anchorPostId
              : null,
        ),
        filter: (post) =>
            (!app.local.blocksPost(post) ||
            !app.settings.getBool('hideBlockedContent')),
        itemKey: (post) => post.id,
        onVisibleItemChanged: _rememberPost,
        onLoaded: (result) {
          if (!mounted) return;
          for (final post in result.items) {
            if (post.floor == 1) _firstPost = post;
            _postPages[post.id] = result.page;
          }
          final firstLoad = _thread == null;
          setState(() {
            if (!_initialResultApplied) {
              _initialResultApplied = true;
              _page = result.page;
              _visiblePage = result.page;
              _useAnchor = false;
            }
            _thread = result.thread ?? _thread;
            _forum = result.forum ?? result.thread?.forum ?? _forum;
            if (firstLoad) {
              _saved = _thread?.isBookmarked ?? false;
              _liked = _thread?.isLiked ?? false;
            }
          });
        },
        headerBuilder: (context, result) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (thread != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                child: Text(
                  thread.title.isEmpty ? context.l10n.noTitle : thread.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            if (app.settings.getBool('showShortcutInThread', fallback: true))
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                child: Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: Text(context.l10n.onlyAuthor),
                      selected: _onlyAuthor,
                      onSelected: (value) {
                        setState(() => _onlyAuthor = value);
                        _restart();
                      },
                    ),
                    ActionChip(
                      label: Text(
                        _sort == 0
                            ? context.l10n.oldestFirst
                            : context.l10n.newestFirst,
                      ),
                      avatar: const Icon(Icons.swap_vert_rounded, size: 17),
                      onPressed: () {
                        setState(() => _sort = _sort == 0 ? 1 : 0);
                        _restart();
                      },
                    ),
                    if (_page > 1)
                      ActionChip(
                        label: Text('${context.l10n.page} ${_page - 1}'),
                        avatar: const Icon(
                          Icons.chevron_left_rounded,
                          size: 17,
                        ),
                        onPressed: () => _restart(page: _page - 1),
                      ),
                  ],
                ),
              ),
          ],
        ),
        itemBuilder: (context, post, _) => PostCard(
          key: ValueKey(post.id),
          post: post,
          forum: _forum ?? const Forum(),
          readerMode: _reader,
          onReply: () => _reply(post: post),
          onBookmark: () => _toggleSaved(postId: post.id),
          onReplies: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) =>
                  FloorRepliesPage(post: post, forum: _forum ?? const Forum()),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _reader
          ? null
          : GlassActionBar(
              actions: [
                NativeGlassAction(
                  id: 'reply',
                  label: context.l10n.reply,
                  symbol: 'square.and.pencil',
                  showLabel: true,
                  onPressed: () => _reply(),
                ),
                NativeGlassAction(
                  id: 'like',
                  label: context.l10n.like,
                  symbol: _liked ? 'hand.thumbsup.fill' : 'hand.thumbsup',
                  selected: _liked,
                  onPressed: _busy ? null : _toggleLike,
                ),
                NativeGlassAction(
                  id: 'save',
                  label: _saved
                      ? context.l10n.unsavePost
                      : context.l10n.savePost,
                  symbol: _saved ? 'bookmark.fill' : 'bookmark',
                  selected: _saved,
                  onPressed: _busy ? null : () => _toggleSaved(),
                ),
              ],
            ),
    );
  }
}

class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.forum,
    this.readerMode = false,
    required this.onReply,
    this.onBookmark,
    this.onReplies,
  });
  final Post post;
  final Forum forum;
  final bool readerMode;
  final VoidCallback onReply;
  final VoidCallback? onBookmark, onReplies;
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late bool _liked;
  bool _busy = false;
  bool _deleted = false;
  @override
  void initState() {
    super.initState();
    _liked = widget.post.isLiked;
  }

  Future<void> _like() async {
    setState(() => _busy = true);
    final ok = await performAction(
      context,
      () => AppScope.read(context).api.agree(
        threadId: widget.post.threadId,
        postId: widget.post.id,
        forumId: widget.forum.id,
        undo: _liked,
      ),
    );
    if (mounted) {
      setState(() {
        _busy = false;
        if (ok) _liked = !_liked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_deleted) return const SizedBox.shrink();
    final post = widget.post;
    final app = AppScope.of(context);
    return BlockedContent(
      blocked: app.local.blocksPost(post),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border(
            bottom: BorderSide(color: context.colors.outlineVariant, width: .5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => openUser(context, post.author),
                    child: UserAvatar(
                      url: post.author.avatar,
                      name: post.author.name,
                      radius: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => openUser(context, post.author),
                          child: Text(
                            displayUserName(context, post.author),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${post.floor > 0 ? '#${post.floor} · ' : ''}${shortDate(context, post.createdAt)}',
                          style: TextStyle(
                            color: context.colors.outline,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      switch (value) {
                        case 'copy':
                          copyText(context, post.plainText);
                        case 'save':
                          widget.onBookmark?.call();
                        case 'block':
                          await app.local.blockUser(post.author);
                          if (context.mounted) {
                            notifyUser(context, context.l10n.blocked);
                          }
                        case 'report':
                          await reportPost(context, post, widget.forum);
                        case 'delete':
                          if (post.author.id != app.session?.userId) return;
                          if (!await confirmAction(
                                context,
                                context.l10n.deletePost,
                                context.l10n.deleteConfirm,
                              ) ||
                              !context.mounted) {
                            return;
                          }
                          final ok = await performAction(
                            context,
                            () => app.api.deletePost(
                              forum: widget.forum,
                              threadId: post.threadId,
                              postId: post.id,
                              subPost: post.parentPostId.isNotEmpty,
                            ),
                          );
                          if (ok && mounted) setState(() => _deleted = true);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'copy',
                        child: Text(context.l10n.copyText),
                      ),
                      if (widget.onBookmark != null)
                        PopupMenuItem(
                          value: 'save',
                          child: Text(context.l10n.savePost),
                        ),
                      if (post.author.id.isNotEmpty &&
                          post.author.id != app.session?.userId)
                        PopupMenuItem(
                          value: 'block',
                          child: Text(context.l10n.blockUser),
                        ),
                      PopupMenuItem(
                        value: 'report',
                        child: Text(context.l10n.report),
                      ),
                      if (app.isLoggedIn &&
                          post.author.id == app.session?.userId &&
                          post.floor != 1)
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(context.l10n.deletePost),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              PostContent(content: post.content),
              if (post.replies.isNotEmpty &&
                  !app.settings.hideReply &&
                  !widget.readerMode) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: widget.onReplies,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainerHighest.withValues(
                        alpha: .7,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...post.replies
                            .where((reply) => !app.local.blocksPost(reply))
                            .take(3)
                            .map(
                              (reply) => Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text:
                                            '${displayUserName(context, reply.author)}: ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: context.colors.primary,
                                        ),
                                      ),
                                      TextSpan(text: reply.plainText),
                                    ],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ),
                        if (post.replyCount > 3)
                          Text(
                            '${context.l10n.viewReplies} (${post.replyCount})',
                            style: TextStyle(
                              color: context.colors.primary,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              if (!widget.readerMode) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    children: [
                      if (post.replyCount > 0 &&
                          post.replies.isEmpty &&
                          widget.onReplies != null)
                        TextButton(
                          onPressed: widget.onReplies,
                          child: Text(
                            '${context.l10n.floorReplies} ${post.replyCount}',
                          ),
                        ),
                      TextButton.icon(
                        onPressed: widget.onReply,
                        icon: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 16,
                        ),
                        label: Text(context.l10n.reply),
                      ),
                      TextButton.icon(
                        onPressed: _busy ? null : _like,
                        icon: Icon(
                          _liked
                              ? Icons.thumb_up_rounded
                              : Icons.thumb_up_outlined,
                          size: 16,
                        ),
                        label: Text(
                          '${post.likeCount + (_liked == post.isLiked
                                  ? 0
                                  : _liked
                                  ? 1
                                  : -1)}',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> reportPost(BuildContext context, Post post, Forum forum) async {
  if (!await requireAccount(context) || !context.mounted) return;
  final app = AppScope.read(context);
  final session = app.session;
  if (session == null) return;
  await performAction(context, () async {
    final data = await app.api.reportContext(
      category: '1',
      threadId: post.threadId,
      postId: post.id,
      forumId: forum.id,
    );
    final nested = objectValue(data['data']);
    final url = stringValue(nested['url'] ?? data['url']);
    final uri = Uri.tryParse(url);
    if (uri == null || !BaiduActionPolicy.accepts(uri, initial: true)) {
      throw StateError('Baidu did not return a valid report page');
    }
    if (!context.mounted || app.session?.userId != session.userId) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => BaiduActionPage(
          url: uri,
          session: session,
          title: context.l10n.report,
          errorLabel: context.l10n.operationFailed,
          retryLabel: context.l10n.retry,
          unsupportedLabel: context.l10n.nativeLoginOnly,
        ),
      ),
    );
  });
}

class FloorRepliesPage extends StatefulWidget {
  const FloorRepliesPage({super.key, required this.post, required this.forum});
  final Post post;
  final Forum forum;
  @override
  State<FloorRepliesPage> createState() => _FloorRepliesPageState();
}

class _FloorRepliesPageState extends State<FloorRepliesPage> {
  final _list = GlobalKey<PagedListState<Post>>();
  Future<void> _reply([Post? target]) async {
    if (!await requireAccount(context) || !mounted) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ReplyPage(
          threadId: widget.post.threadId,
          forum: widget.forum,
          parentPostId: widget.post.id,
          subPostId: target?.id,
          replyUserId: target?.author.id ?? widget.post.author.id,
          replyUserName: target?.author.name ?? widget.post.author.name,
        ),
      ),
    );
    if (mounted && result == true) _list.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      extendBody: usesNativeGlass,
      extendBodyBehindAppBar: usesNativeGlass,
      appBar: GlassAppBar(title: Text(context.l10n.floorReplies)),
      body: PagedList<Post>(
        key: _list,
        load: (page) => app.api.floorReplies(
          threadId: widget.post.threadId,
          postId: widget.post.id,
          forumId: widget.forum.id,
          page: page,
        ),
        filter: (post) =>
            (!app.local.blocksPost(post) ||
            !app.settings.getBool('hideBlockedContent')),
        headerBuilder: (context, _) => PostCard(
          post: widget.post,
          forum: widget.forum,
          readerMode: true,
          onReply: _reply,
        ),
        itemBuilder: (context, post, _) => PostCard(
          key: ValueKey(post.id),
          post: post,
          forum: widget.forum,
          onReply: () => _reply(post),
        ),
      ),
      bottomNavigationBar: GlassActionBar(
        actions: [
          NativeGlassAction(
            id: 'reply',
            label: context.l10n.reply,
            symbol: 'square.and.pencil',
            showLabel: true,
            onPressed: _reply,
          ),
        ],
      ),
    );
  }
}
