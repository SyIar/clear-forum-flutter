import '../tablet_bridge.dart';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../widgets/common.dart';
import '../widgets/content_cards.dart';
import '../widgets/paged_list.dart';
import 'main_shell.dart';
import 'media_page.dart';
import 'search_page.dart';

class ForumPage extends StatefulWidget {
  const ForumPage({super.key, required this.name});
  final String name;
  @override
  State<ForumPage> createState() => _ForumPageState();
}

class _ForumPageState extends State<ForumPage> {
  final _list = GlobalKey<PagedListState<ThreadSummary>>();
  bool _digest = false, _busy = false, _initialized = false;
  int _sort = 0;
  Forum? _forum;
  List<ThreadSummary> _pinnedThreads = [];
  String? _routeAccountId;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final app = AppScope.read(context);
      _routeAccountId = app.session?.userId;
      final settings = app.settings;
      _sort = settings.getInt(
        'forumSort.${Uri.encodeComponent(widget.name)}',
        fallback: settings.getString('defaultSortType') == 'post' ? 1 : 0,
      );
    }
  }

  void _reload() {
    _list.currentState?.reload();
  }

  bool _showThread(ThreadSummary thread) {
    final app = AppScope.read(context);
    return (!app.local.blocksThread(thread) ||
            (!app.settings.getBool('hideBlockedContent') &&
                app.settings.getBool('showBlockTip', fallback: true))) &&
        !(app.settings.blockVideo && thread.videoUrl.isNotEmpty);
  }

  Future<void> _action(
    Future<void> Function() request, {
    VoidCallback? onSuccess,
  }) async {
    final app = AppScope.read(context);
    setState(() => _busy = true);
    final succeeded = await performAction(
      context,
      request,
      success: context.l10n.operationSucceeded,
    );
    if (mounted) {
      final sameAccount =
          !app.changingAccount && app.session?.userId == _routeAccountId;
      setState(() {
        _busy = false;
        if (succeeded && sameAccount) onSuccess?.call();
      });
      if (succeeded && sameAccount) _reload();
    }
  }

  @override
  Widget build(BuildContext context) => TabletThreadHost(builder: _buildMaster);

  Widget _buildMaster(BuildContext context) {
    final app = AppScope.of(context);
    final forum = _forum ?? Forum(name: widget.name);
    final pinned = _pinnedThreads.where(_showThread).toList();
    final fab = app.settings.getString('forumFabFunction', fallback: 'refresh');
    return Scaffold(
      extendBodyBehindAppBar: usesNativeGlass,
      appBar: GlassAppBar(
        title: Text(widget.name),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => SearchPage(forumName: widget.name),
              ),
            ),
            icon: const Icon(Icons.search_rounded),
            tooltip: context.l10n.searchInForum,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'pin':
                  app.local.togglePinnedForum(forum);
                case 'share':
                  shareLink(
                    context,
                    'https://tieba.baidu.com/f?kw=${Uri.encodeComponent(widget.name)}',
                    title: widget.name,
                  );
                case 'info':
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ForumInfoPage(forum: forum),
                    ),
                  );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'pin',
                child: Text(
                  app.local.pinnedForumNames.contains(widget.name)
                      ? context.l10n.unpin
                      : context.l10n.pin,
                ),
              ),
              PopupMenuItem(value: 'share', child: Text(context.l10n.share)),
              PopupMenuItem(value: 'info', child: Text(context.l10n.forumInfo)),
            ],
          ),
        ],
      ),
      body: PagedList<ThreadSummary>(
        key: _list,
        padding: const EdgeInsets.only(bottom: 90),
        itemKey: (thread) => thread.id,
        load: (page) => app.api.forumThreads(
          widget.name,
          page: page,
          sort: _sort,
          digest: _digest,
        ),
        onLoaded: (result) {
          if (mounted) {
            setState(() {
              _forum = result.forum ?? _forum;
              final pins = {
                if (result.page > 1)
                  for (final thread in _pinnedThreads) thread.id: thread,
              };
              for (final thread in result.items) {
                if (thread.isPinned) {
                  pins[thread.id] = thread;
                } else {
                  pins.remove(thread.id);
                }
              }
              _pinnedThreads = pins.values.toList();
            });
            if (result.forum != null &&
                !app.changingAccount &&
                app.session?.userId == _routeAccountId) {
              app.local.recordForum(result.forum!);
            }
          }
        },
        filter: (thread) => !thread.isPinned && _showThread(thread),
        headerBuilder: (context, result) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      UserAvatar(
                        url: forum.avatar,
                        name: forum.name,
                        radius: 34,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              forum.name,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            if (!app.settings.getBool('hideForumIntroAndStat'))
                              Text(
                                '${context.l10n.members} ${forum.memberCount == null ? '—' : compactCount(forum.memberCount!)}  ·  ${context.l10n.posts} ${compactCount(forum.threadCount)}',
                                style: TextStyle(
                                  color: context.colors.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (forum.description.isNotEmpty &&
                      !app.settings.getBool('hideForumIntroAndStat')) ...[
                    const SizedBox(height: 14),
                    Text(
                      forum.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.onSurfaceVariant,
                        height: 1.55,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _busy || forum.id.isEmpty
                            ? null
                            : () => _action(() async {
                                await app.api.followForum(
                                  forum,
                                  follow: !forum.isFollowing,
                                );
                              }),
                        icon: Icon(
                          forum.isFollowing
                              ? Icons.check_rounded
                              : Icons.add_rounded,
                          size: 18,
                        ),
                        label: Text(
                          forum.isFollowing
                              ? context.l10n.followed
                              : context.l10n.follow,
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _busy || forum.isSigned || forum.id.isEmpty
                            ? null
                            : () => _action(
                                () => app.api.signForum(forum),
                                onSuccess: () =>
                                    _forum = forum.copyWith(isSigned: true),
                              ),
                        icon: const Icon(Icons.task_alt_rounded, size: 18),
                        label: Text(
                          forum.isSigned
                              ? context.l10n.checkedIn
                              : context.l10n.checkIn,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 12, 10),
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text(context.l10n.general),
                    selected: !_digest,
                    onSelected: (_) {
                      setState(() => _digest = false);
                      _reload();
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(context.l10n.digest),
                    selected: _digest,
                    onSelected: (_) {
                      setState(() => _digest = true);
                      _reload();
                    },
                  ),
                  const Spacer(),
                  PopupMenuButton<int>(
                    initialValue: _sort,
                    onSelected: (value) {
                      setState(() => _sort = value);
                      app.settings.setInt(
                        'forumSort.${Uri.encodeComponent(widget.name)}',
                        value,
                      );
                      _reload();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 0,
                        child: Text(context.l10n.latestReply),
                      ),
                      PopupMenuItem(
                        value: 1,
                        child: Text(context.l10n.latestPost),
                      ),
                    ],
                    icon: const Icon(Icons.sort_rounded),
                    tooltip: context.l10n.sort,
                  ),
                ],
              ),
            ),
            if (pinned.isNotEmpty)
              PinnedThreadList(
                threads: pinned,
                onTap: (thread) => openThread(context, thread),
              ),
          ],
        ),
        itemBuilder: (context, thread, _) => ThreadCard(
          thread: thread,
          onTap: () => openThread(context, thread),
          onAuthorTap: () => openUser(context, thread.author),
        ),
      ),
      floatingActionButton: fab == 'hide' || fab == 'post'
          ? null
          : GlassFloatingButton.small(
              tooltip: fab == 'back_to_top'
                  ? context.l10n.backToTop
                  : context.l10n.refresh,
              onPressed: () async {
                await _list.currentState?.scrollToTop();
                if (mounted && fab != 'back_to_top') _reload();
              },
              child: Icon(
                fab == 'back_to_top'
                    ? Icons.vertical_align_top_rounded
                    : Icons.refresh_rounded,
              ),
            ),
    );
  }
}

class ForumInfoPage extends StatefulWidget {
  const ForumInfoPage({super.key, required this.forum});
  final Forum forum;
  @override
  State<ForumInfoPage> createState() => _ForumInfoPageState();
}

class _ForumInfoPageState extends State<ForumInfoPage> {
  Future<Forum>? _detail;
  Future<List<ForumRule>>? _rules;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  void _load() {
    final api = AppScope.read(context).api;
    _detail ??= widget.forum.id.isEmpty
        ? Future.value(widget.forum)
        : api.forumDetail(widget.forum.id);
    _rules ??= widget.forum.id.isEmpty
        ? Future.value([])
        : api.forumRules(widget.forum.id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: GlassAppBar(title: Text(context.l10n.forumInfo)),
    body: ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        FutureBuilder<Forum>(
          future: _detail,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ErrorPanel(
                error: snapshot.error!,
                onRetry: () => setState(() {
                  _detail = null;
                  _load();
                }),
              );
            }
            final forum = snapshot.data ?? widget.forum;
            return SurfaceCard(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UserAvatar(url: forum.avatar, name: forum.name, radius: 34),
                    const SizedBox(height: 16),
                    Text(
                      forum.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      forum.description,
                      style: const TextStyle(height: 1.65),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '${context.l10n.members}  ${forum.memberCount == null ? '—' : compactCount(forum.memberCount!)}\n${context.l10n.posts}  ${compactCount(forum.threadCount)}',
                      style: const TextStyle(height: 1.8),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        SectionTitle(context.l10n.forumRules),
        FutureBuilder<List<ForumRule>>(
          future: _rules,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ErrorPanel(
                error: snapshot.error!,
                onRetry: () => setState(() {
                  _rules = null;
                  _load();
                }),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator.adaptive());
            }
            if (snapshot.data!.isEmpty) return const EmptyPanel();
            return Column(
              children: snapshot.data!
                  .map(
                    (rule) => SurfaceCard(
                      child: ExpansionTile(
                        title: Text(rule.title),
                        subtitle: rule.author.isEmpty
                            ? null
                            : Text(rule.author),
                        childrenPadding: const EdgeInsets.all(18),
                        children: [
                          rule.parts.isNotEmpty
                              ? PostContent(content: rule.parts)
                              : SelectableText(
                                  rule.content,
                                  style: const TextStyle(height: 1.65),
                                ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    ),
  );
}
