import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../widgets/common.dart';
import '../widgets/content_cards.dart';
import '../widgets/paged_list.dart';
import '../widgets/policy_image.dart';
import 'main_shell.dart';

class HotPage extends StatefulWidget {
  const HotPage({super.key});
  @override
  State<HotPage> createState() => _HotPageState();
}

class _HotPageState extends State<HotPage> {
  Future<HotOverview>? _overview;
  String _tab = 'all';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _overview ??= AppScope.read(context).api.hotOverview(tabCode: _tab);
  }

  Future<void> _reload() async {
    final future = AppScope.read(context).api.hotOverview(tabCode: _tab);
    setState(() => _overview = future);
    try {
      await future;
    } catch (_) {
      /* The request state is rendered below. */
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return FutureBuilder<HotOverview>(
      future: _overview,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [ErrorPanel(error: snapshot.error!, onRetry: _reload)],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        final data = snapshot.data!;
        final threads = data.threads
            .where(
              (thread) =>
                  (!app.local.blocksThread(thread) ||
                      !app.settings.getBool('hideBlockedContent')) &&
                  !(app.settings.blockVideo && thread.videoUrl.isNotEmpty),
            )
            .toList();
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 30),
            children: [
              SectionTitle(
                context.l10n.hotTopics,
                trailing: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const HotTopicListPage(),
                    ),
                  ),
                  child: Text(context.l10n.more),
                ),
              ),
              if (data.topics.isNotEmpty)
                SurfaceCard(
                  child: Column(
                    children: data.topics
                        .take(6)
                        .indexed
                        .map(
                          (entry) =>
                              _TopicTile(topic: entry.$2, rank: entry.$1 + 1),
                        )
                        .toList(),
                  ),
                ),
              if (data.tabs.isNotEmpty)
                SizedBox(
                  height: 66,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    scrollDirection: Axis.horizontal,
                    itemCount: data.tabs.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final tab = data.tabs[index];
                      return ChoiceChip(
                        label: Text(tab.title),
                        selected: _tab == tab.code,
                        onSelected: (_) {
                          _tab = tab.code;
                          _reload();
                        },
                      );
                    },
                  ),
                ),
              if (snapshot.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator(),
              if (threads.isEmpty) const EmptyPanel(),
              for (final thread in threads)
                ThreadCard(
                  key: ValueKey(thread.id),
                  thread: thread,
                  onTap: () => openThread(context, thread),
                  onAuthorTap: () => openUser(context, thread.author),
                  onForumTap: () => openForum(context, thread.forum.name),
                ),
            ],
          ),
        );
      },
    );
  }
}

class HotTopicListPage extends StatelessWidget {
  const HotTopicListPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: GlassAppBar(title: Text(context.l10n.hotTopics)),
    body: PagedList<HotTopic>(
      load: (_) async =>
          PageResult(items: await AppScope.read(context).api.hotTopics()),
      itemBuilder: (context, topic, index) => SurfaceCard(
        child: _TopicTile(topic: topic, rank: index + 1),
      ),
    ),
  );
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({required this.topic, required this.rank});
  final HotTopic topic;
  final int rank;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: SizedBox(
      width: 24,
      child: Text(
        '$rank',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 19,
          color: rank <= 3 ? context.colors.tertiary : context.colors.outline,
        ),
      ),
    ),
    title: Text(
      topic.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    subtitle: topic.hotCount > 0
        ? Text('${context.l10n.topicHeat} ${compactCount(topic.hotCount)}')
        : null,
    trailing: topic.tag == 2
        ? Icon(
            Icons.local_fire_department_rounded,
            color: context.colors.tertiary,
            size: 20,
          )
        : const Icon(Icons.chevron_right_rounded),
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TopicDiscussionPage(topic: topic),
      ),
    ),
  );
}

class TopicDiscussionPage extends StatelessWidget {
  const TopicDiscussionPage({super.key, required this.topic});
  final HotTopic topic;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: GlassAppBar(title: Text(context.l10n.topicDiscussion)),
      body: PagedList<ThreadSummary>(
        load: (page) =>
            app.api.topicThreads(topic.id, topicName: topic.title, page: page),
        filter: (thread) =>
            !app.local.blocksThread(thread) ||
            !app.settings.getBool('hideBlockedContent'),
        headerBuilder: (context, result) {
          final detail = result?.topic ?? topic;
          return Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (detail.imageUrl.isNotEmpty && !app.settings.hideMedia)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: PolicyImage(
                        original: detail.imageUrl,
                        height: 170,
                        width: double.infinity,
                      ),
                    ),
                  ),
                Text(
                  detail.title,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (detail.excerpt.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      detail.excerpt,
                      style: TextStyle(
                        color: context.colors.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                  ),
                if (detail.hotCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '${context.l10n.topicHeat} ${compactCount(detail.hotCount)}',
                      style: TextStyle(color: context.colors.primary),
                    ),
                  ),
                if (result?.relatedForums.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Wrap(
                      spacing: 8,
                      children: result!.relatedForums
                          .map(
                            (forum) => ActionChip(
                              label: Text(forum.name),
                              avatar: const Icon(
                                Icons.forum_outlined,
                                size: 16,
                              ),
                              onPressed: () => openForum(context, forum.name),
                            ),
                          )
                          .toList(),
                    ),
                  ),
              ],
            ),
          );
        },
        itemBuilder: (context, thread, _) => ThreadCard(
          thread: thread,
          onTap: () => openThread(context, thread),
          onAuthorTap: () => openUser(context, thread.author),
          onForumTap: () => openForum(context, thread.forum.name),
        ),
      ),
    );
  }
}
