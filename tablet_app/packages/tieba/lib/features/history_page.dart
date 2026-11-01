import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../widgets/common.dart';
import '../widgets/content_cards.dart';
import 'main_shell.dart';
import 'thread_page.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final local = app.local;
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: GlassAppBar(
            title: Text(context.l10n.history),
            bottom: TabBar(
              tabs: [
                Tab(text: context.l10n.posts),
                Tab(text: context.l10n.forums),
              ],
            ),
            actions: [
              IconButton(
                tooltip: context.l10n.clearHistory,
                icon: const Icon(Icons.clear_all_rounded),
                onPressed:
                    local.histories.isEmpty && local.forumHistories.isEmpty
                    ? null
                    : () async {
                        final forums =
                            DefaultTabController.of(context).index == 1;
                        if (!await confirmAction(
                              context,
                              context.l10n.clearHistory,
                              context.l10n.clearConfirm,
                            ) ||
                            !context.mounted) {
                          return;
                        }
                        await performAction(
                          context,
                          forums ? local.clearForumHistory : local.clearHistory,
                          requiresLogin: false,
                        );
                      },
              ),
            ],
          ),
          body: TabBarView(
            children: [
              local.histories.isEmpty
                  ? const EmptyPanel(icon: Icons.history_rounded)
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: local.histories.length,
                      itemBuilder: (context, index) {
                        final item = local.histories[index];
                        final restore = app.settings.getBool(
                          'restoreReading',
                          fallback: true,
                        );
                        return SurfaceCard(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 8,
                            ),
                            leading: Icon(
                              Icons.article_outlined,
                              color: context.colors.primary,
                            ),
                            title: Text(
                              item.title.isEmpty ? item.threadId : item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                '${item.forumName} · ${shortDate(context, item.visitedAt)}',
                              ),
                            ),
                            trailing: _removeButton(
                              context,
                              () => local.removeHistory(item.threadId),
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => ThreadPage(
                                  threadId: item.threadId,
                                  initialPage: restore ? item.page : 1,
                                  anchorPostId:
                                      restore && item.lastPostId.isNotEmpty
                                      ? item.lastPostId
                                      : null,
                                  initialOnlyAuthor: restore
                                      ? item.onlyAuthor
                                      : null,
                                  initialThread: ThreadSummary(
                                    id: item.threadId,
                                    title: item.title,
                                    forum: Forum(name: item.forumName),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
              local.forumHistories.isEmpty
                  ? const EmptyPanel(icon: Icons.history_rounded)
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: local.forumHistories.length,
                      itemBuilder: (context, index) {
                        final item = local.forumHistories[index];
                        return SurfaceCard(
                          child: ForumTile(
                            forum: item.forum,
                            subtitle: shortDate(context, item.visitedAt),
                            trailing: _removeButton(
                              context,
                              () => local.removeForumHistory(item.forum.name),
                            ),
                            onTap: () => openForum(context, item.forum.name),
                          ),
                        );
                      },
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _removeButton(BuildContext context, Future<void> Function() action) =>
      PopupMenuButton<String>(
        onSelected: (_) => performAction(context, action, requiresLogin: false),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'remove',
            child: Text(context.l10n.removeFromHistory),
          ),
        ],
      );
}
