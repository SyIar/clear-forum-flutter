import '../tablet_bridge.dart';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../platform/deep_links.dart';
import '../widgets/common.dart';
import '../widgets/content_cards.dart';
import '../widgets/paged_list.dart';
import 'account_pages.dart';
import 'forum_page.dart';
import 'hot_topics_page.dart';
import 'search_page.dart';
import 'thread_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) {
    final hidden = AppScope.of(context).settings.hideExplore;
    final pages = [
      const HomePage(),
      if (!hidden) const ExplorePage(),
      const NotificationsPage(),
      if (TabletBridge.downloads != null)
        Builder(builder: TabletBridge.downloads!),
      const MePage(),
    ];
    final labels = [
      context.l10n.home,
      if (!hidden) context.l10n.explore,
      context.l10n.notifications,
      if (TabletBridge.downloads != null) TabletBridge.downloadsLabel,
      context.l10n.me,
    ];
    final icons = [
      Icons.home_outlined,
      if (!hidden) Icons.explore_outlined,
      Icons.notifications_none,
      if (TabletBridge.downloads != null) Icons.download_outlined,
      Icons.person_outline,
    ];
    final selected = _tab.clamp(0, pages.length - 1);
    return LayoutBuilder(
      builder: (context, size) {
        final rail = size.maxWidth >= 840;
        final body = IndexedStack(index: selected, children: pages);
        return Scaffold(
          body: Row(
            children: [
              if (rail)
                NavigationRail(
                  selectedIndex: selected,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  destinations: [
                    for (var i = 0; i < pages.length; i++)
                      NavigationRailDestination(
                        icon: Icon(icons[i]),
                        label: Text(labels[i]),
                      ),
                  ],
                ),
              if (rail) const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          ),
          bottomNavigationBar: rail
              ? null
              : NavigationBar(
                  selectedIndex: selected,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  destinations: [
                    for (var i = 0; i < pages.length; i++)
                      NavigationDestination(
                        icon: Icon(icons[i]),
                        label: labels[i],
                      ),
                  ],
                ),
        );
      },
    );
  }
}

Future<void> openForum(BuildContext context, String name) async {
  if (name.trim().isNotEmpty) {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => ForumPage(name: name.trim())),
    );
  }
}

void openThread(BuildContext context, ThreadSummary thread) {
  final app = AppScope.read(context);
  var page = 1;
  String? anchor;
  bool? onlyAuthor;
  if (app.settings.getBool('restoreReading', fallback: true)) {
    for (final entry in app.local.histories) {
      if (entry.threadId == thread.id) {
        page = entry.page;
        anchor = entry.lastPostId.isEmpty ? null : entry.lastPostId;
        onlyAuthor = entry.onlyAuthor;
        break;
      }
    }
  }
  final detail = ThreadPage(
    threadId: thread.id,
    initialThread: thread,
    initialPage: page,
    anchorPostId: anchor,
    initialOnlyAuthor: onlyAuthor,
  );
  final pane = ThreadPaneScope.of(context);
  if (pane != null) {
    pane.open(detail);
    return;
  }
  Navigator.push(context, MaterialPageRoute<void>(builder: (_) => detail));
}

void openUser(BuildContext context, UserProfile user) {
  if (user.id.isNotEmpty) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => UserProfilePage(userId: user.id, initialUser: user),
      ),
    );
  }
}

void openIncomingLink(BuildContext context, TiebaLink link) {
  final Widget page = switch (link.kind) {
    TiebaLinkKind.thread => ThreadPage(
      threadId: link.value,
      initialPage: link.page,
      anchorPostId: link.postId.isEmpty ? null : link.postId,
    ),
    TiebaLinkKind.forum => ForumPage(name: link.value),
    TiebaLinkKind.user => UserProfilePage(userId: link.value),
    TiebaLinkKind.notifications => NotificationsPage(
      initialTab: int.tryParse(link.value) ?? 0,
    ),
    TiebaLinkKind.history => const HistoryPage(),
    TiebaLinkKind.favorites => const FavoritesPage(),
    TiebaLinkKind.search => SearchPage(initialQuery: link.value),
  };
  Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Future<List<Forum>>? _forums;
  String? _account;
  bool _signing = false;
  Future<void> _openForum(String name) async {
    await openForum(context, name);
    if (mounted) await _refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    final account = app.session?.userId ?? '';
    if (_account != account) {
      _account = account;
      _forums = app.isLoggedIn
          ? app.api.followedForums()
          : Future.value(<Forum>[]);
    }
  }

  Future<void> _refresh() async {
    final app = AppScope.read(context);
    final next = app.isLoggedIn
        ? app.api.followedForums()
        : Future.value(<Forum>[]);
    setState(() {
      _forums = next;
    });
    try {
      await next;
    } catch (_) {
      /* FutureBuilder renders the request error. */
    }
  }

  Future<void> _checkIn(List<Forum> forums) async {
    if (!await confirmAction(
      context,
      context.l10n.signAll,
      context.l10n.signAllConfirm,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _signing = true);
    var succeeded = 0;
    var failed = 0;
    final app = AppScope.read(context);
    final accountId = app.session?.userId;
    final pending = forums.where((forum) => !forum.isSigned).toList();
    var signed = <String>{};
    if (app.settings.getBool('oksignUseOfficialOksign', fallback: true) &&
        pending.isNotEmpty) {
      try {
        signed = await app.api.officialBatchSign(pending);
      } catch (_) {
        /* Retry only unconfirmed forums individually. */
      }
      if (!mounted || app.session?.userId != accountId) return;
      succeeded = pending.where((forum) => signed.contains(forum.id)).length;
    }
    for (final forum in pending.where((forum) => !signed.contains(forum.id))) {
      if (!mounted || app.session?.userId != accountId) return;
      try {
        await app.api.signForum(forum);
        succeeded++;
      } catch (_) {
        failed++;
      }
      if (!mounted) return;
      if (app.settings.getBool('signSlowMode', fallback: true)) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    if (mounted) {
      setState(() => _signing = false);
      notifyUser(
        context,
        '${context.l10n.checkInComplete}: $succeeded / ${succeeded + failed}',
      );
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      extendBodyBehindAppBar: usesNativeGlass,
      appBar: GlassAppBar(
        title: Text(context.l10n.appTitle),
        actions: [
          IconButton(
            onPressed: () async {
              final name = await textPrompt(
                context,
                title: context.l10n.openForum,
                hint: context.l10n.enterForum,
              );
              if (context.mounted && name != null && name.isNotEmpty) {
                _openForum(name);
              }
            },
            icon: const Icon(Icons.add_rounded),
            tooltip: context.l10n.openForum,
          ),
          IconButton(
            onPressed: () async {
              final value = await textPrompt(
                context,
                title: context.l10n.openByLink,
                hint: context.l10n.pasteLink,
              );
              if (!context.mounted || value == null || value.isEmpty) return;
              final id = RegExp(r'^\d+$').hasMatch(value)
                  ? value
                  : RegExp(r'/p/(\d+)').firstMatch(value)?.group(1);
              if (id == null) {
                notifyUser(context, context.l10n.invalidLink);
                return;
              }
              openThread(context, ThreadSummary(id: id));
            },
            icon: const Icon(Icons.link_rounded),
            tooltip: context.l10n.openByLink,
          ),
        ],
      ),
      body: FutureBuilder<List<Forum>>(
        future: _forums,
        builder: (context, snapshot) {
          final allForums = snapshot.data ?? <Forum>[];
          final forums =
              app.settings.getBool('showTopForumInNormalList', fallback: true)
              ? allForums
              : allForums
                    .where(
                      (forum) =>
                          !app.local.pinnedForumNames.contains(forum.name),
                    )
                    .toList();
          final pinned = app.local.pinnedForums;
          final recent = app.local.recentForums;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top,
                bottom: 28 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                  child: SearchBar(
                    leading: const Icon(Icons.search_rounded),
                    hintText: context.l10n.searchHint,
                    readOnly: true,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const SearchPage(),
                      ),
                    ),
                  ),
                ),
                if (!app.isLoggedIn)
                  SurfaceCard(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.visitor,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            context.l10n.visitorBody,
                            style: TextStyle(
                              color: context.colors.onSurfaceVariant,
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 18),
                          FilledButton.tonalIcon(
                            onPressed: () => app.login(context),
                            icon: const Icon(Icons.login_rounded),
                            label: Text(context.l10n.signIn),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (pinned.isNotEmpty) ...[
                  SectionTitle(context.l10n.pinnedForums),
                  _forumCollection(pinned),
                ],
                if (recent.isNotEmpty &&
                    app.settings.getBool('homePageShowHistoryForum')) ...[
                  SectionTitle(context.l10n.recentForums),
                  SurfaceCard(
                    child: Column(
                      children: recent
                          .map(
                            (forum) => ForumTile(
                              forum: forum,
                              onTap: () => _openForum(forum.name),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
                SectionTitle(
                  context.l10n.followedForums,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (allForums.isNotEmpty)
                        IconButton(
                          onPressed: _signing
                              ? null
                              : () => _checkIn(allForums),
                          icon: _signing
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.task_alt_rounded),
                          tooltip: context.l10n.signAll,
                        ),
                      IconButton(
                        onPressed: () => app.settings.setBool(
                          'listSingle',
                          !app.settings.getBool('listSingle'),
                        ),
                        icon: Icon(
                          app.settings.getBool('listSingle')
                              ? Icons.grid_view_rounded
                              : Icons.view_agenda_outlined,
                        ),
                        tooltip: context.l10n.listView,
                      ),
                    ],
                  ),
                ),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.all(35),
                    child: Center(child: CircularProgressIndicator.adaptive()),
                  )
                else if (snapshot.hasError)
                  ErrorPanel(error: snapshot.error!, onRetry: _refresh)
                else if (forums.isEmpty)
                  EmptyPanel(
                    message: context.l10n.emptyForums,
                    icon: Icons.forum_outlined,
                  )
                else
                  _forumCollection(forums, showCheckIn: true),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _forumCollection(List<Forum> forums, {bool showCheckIn = false}) {
    final app = AppScope.of(context);
    if (app.settings.getBool('listSingle')) {
      return SurfaceCard(
        child: Column(
          children: forums
              .map(
                (forum) => ForumTile(
                  forum: forum,
                  onTap: () => _openForum(forum.name),
                  subtitle: showCheckIn
                      ? [
                          if (forum.level > 0) 'Lv.${forum.level}',
                          forum.isSigned
                              ? context.l10n.checkedIn
                              : context.l10n.notCheckedIn,
                        ].join(' · ')
                      : null,
                  trailing: _pinButton(forum),
                ),
              )
              .toList(),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) => GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: forums.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: constraints.maxWidth >= 600 ? 4 : 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: 124,
          ),
          itemBuilder: (context, index) {
            final forum = forums[index];
            return Material(
              color: context.colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _openForum(forum.name),
                onLongPress: () => app.local.togglePinnedForum(forum),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      UserAvatar(
                        url: forum.avatar,
                        name: forum.name,
                        radius: 24,
                      ),
                      const SizedBox(height: 9),
                      Text(
                        forum.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (forum.level > 0)
                        Text(
                          'Lv.${forum.level}',
                          style: TextStyle(
                            fontSize: 10,
                            color: context.colors.primary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _pinButton(Forum forum) {
    final local = AppScope.of(context).local;
    final pinned = local.pinnedForumNames.contains(forum.name);
    return IconButton(
      onPressed: () => local.togglePinnedForum(forum),
      icon: Icon(pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined),
      tooltip: pinned ? context.l10n.unpin : context.l10n.pin,
    );
  }
}

class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return DefaultTabController(
      length: 3,
      initialIndex: 1,
      child: Scaffold(
        appBar: GlassAppBar(
          title: Text(context.l10n.explore),
          actions: [
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const SearchPage()),
              ),
              icon: const Icon(Icons.search_rounded),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: context.l10n.concern),
              Tab(text: context.l10n.recommended),
              Tab(text: context.l10n.hot),
            ],
          ),
        ),
        body: TabBarView(
          children: [FeedKind.concern, FeedKind.personalized, FeedKind.hot]
              .map(
                (kind) => kind == FeedKind.hot
                    ? const HotPage()
                    : kind == FeedKind.concern && !app.isLoggedIn
                    ? const LoginPanel()
                    : PagedList<ThreadSummary>(
                        key: ValueKey('${app.session?.userId}:$kind'),
                        load: (page) => app.api.feed(kind: kind, page: page),
                        filter: (thread) =>
                            (!app.local.blocksThread(thread) ||
                                !app.settings.getBool('hideBlockedContent')) &&
                            !(app.settings.blockVideo &&
                                thread.videoUrl.isNotEmpty),
                        itemBuilder: (context, thread, _) => ThreadCard(
                          thread: thread,
                          onTap: () => openThread(context, thread),
                          onForumTap: () =>
                              openForum(context, thread.forum.name),
                          onAuthorTap: () => openUser(context, thread.author),
                        ),
                      ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab.clamp(0, 1),
      child: Scaffold(
        appBar: GlassAppBar(
          title: Text(context.l10n.notifications),
          bottom: TabBar(
            tabs: [
              Tab(text: context.l10n.replyMe),
              Tab(text: context.l10n.mentionMe),
            ],
          ),
        ),
        body: !app.isLoggedIn
            ? const LoginPanel()
            : TabBarView(
                children: [NotificationKind.replies, NotificationKind.mentions]
                    .map(
                      (kind) => PagedList<NotificationItem>(
                        key: ValueKey('${app.session?.userId}:$kind'),
                        load: (page) =>
                            app.api.notifications(kind: kind, page: page),
                        emptyMessage: context.l10n.emptyNotifications,
                        itemBuilder: (context, item, _) => SurfaceCard(
                          child: InkWell(
                            onTap: item.threadId.isEmpty
                                ? null
                                : () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => ThreadPage(
                                        threadId: item.threadId,
                                        anchorPostId: item.postId,
                                      ),
                                    ),
                                  ),
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      UserAvatar(
                                        url: item.author.avatar,
                                        name: item.author.name,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          item.author.name.isEmpty
                                              ? context.l10n.unknownUser
                                              : item.author.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        shortDate(context, item.createdAt),
                                        style: TextStyle(
                                          color: context.colors.outline,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    item.content,
                                    style: const TextStyle(height: 1.6),
                                  ),
                                  if (item.title.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: context
                                            .colors
                                            .surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        item.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color:
                                              context.colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
      ),
    );
  }
}
