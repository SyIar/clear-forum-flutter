import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../features/media_page.dart';
import 'common.dart';
import 'emoticons.dart';
import 'blocked_content.dart';
import 'policy_image.dart';

class ForumTile extends StatelessWidget {
  const ForumTile({
    super.key,
    required this.forum,
    required this.onTap,
    this.trailing,
    this.subtitle,
  });
  final Forum forum;
  final VoidCallback onTap;
  final Widget? trailing;
  final String? subtitle;
  @override
  Widget build(BuildContext context) {
    final detail =
        subtitle ??
        (forum.description.isNotEmpty
            ? forum.description
            : forum.memberCount != null
            ? '${context.l10n.members} ${compactCount(forum.memberCount!)}'
            : forum.level > 0
            ? 'Lv.${forum.level}'
            : null);
    return ListTile(
      onTap: onTap,
      leading: UserAvatar(url: forum.avatar, name: forum.name, radius: 24),
      title: Text(
        forum.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: detail == null
          ? null
          : Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
    );
  }
}

class UserTile extends StatelessWidget {
  const UserTile({
    super.key,
    required this.user,
    required this.onTap,
    this.trailing,
  });
  final UserProfile user;
  final VoidCallback onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    leading: UserAvatar(url: user.avatar, name: user.name),
    title: Text(
      displayUserName(context, user),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: user.intro.isEmpty
        ? null
        : Text(user.intro, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
  );
}

class PinnedThreadList extends StatelessWidget {
  const PinnedThreadList({
    super.key,
    required this.threads,
    required this.onTap,
  });
  final List<ThreadSummary> threads;
  final ValueChanged<ThreadSummary> onTap;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return SurfaceCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < threads.length; index++) ...[
            if (index > 0) const Divider(height: 1, indent: 14, endIndent: 14),
            BlockedContent(
              key: ValueKey(threads[index].id),
              blocked: app.local.blocksThread(threads[index]),
              child: InkWell(
                onTap: () => onTap(threads[index]),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        threads[index].title.isEmpty
                            ? context.l10n.noTitle
                            : threads[index].title,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ThreadCard extends StatelessWidget {
  const ThreadCard({
    super.key,
    required this.thread,
    required this.onTap,
    this.onForumTap,
    this.onAuthorTap,
  });
  final ThreadSummary thread;
  final VoidCallback onTap;
  final VoidCallback? onForumTap, onAuthorTap;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final compact = app.settings.getBool('compactCards');
    return BlockedContent(
      blocked: app.local.blocksThread(thread),
      child: SurfaceCard(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(compact ? 14 : 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: onAuthorTap,
                      child: UserAvatar(
                        url: thread.author.avatar,
                        name: thread.author.name,
                        radius: 15,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: GestureDetector(
                        onTap: onAuthorTap,
                        child: Text(
                          displayUserName(context, thread.author),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    if (thread.isPinned)
                      Icon(
                        Icons.push_pin_rounded,
                        size: 15,
                        color: context.colors.primary,
                      ),
                    if (thread.isDigest)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.verified_rounded,
                          size: 16,
                          color: context.colors.tertiary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  thread.title.isEmpty ? context.l10n.noTitle : thread.title,
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700, height: 1.4),
                ),
                if (thread.excerpt.isNotEmpty && !compact) ...[
                  const SizedBox(height: 8),
                  Text(
                    thread.excerpt,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.onSurfaceVariant,
                      height: 1.55,
                    ),
                  ),
                ],
                if (thread.images.isNotEmpty && !app.settings.hideMedia) ...[
                  const SizedBox(height: 12),
                  ImageStrip(
                    images: thread.images,
                    thumbnails: thread.imageThumbnails,
                  ),
                ],
                if (thread.videoUrl.isNotEmpty && !app.settings.hideMedia) ...[
                  const SizedBox(height: 10),
                  ActionChip(
                    avatar: const Icon(
                      Icons.play_circle_outline_rounded,
                      size: 18,
                    ),
                    label: Text(context.l10n.video),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => VideoPage(url: thread.videoUrl),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (thread.forum.name.isNotEmpty)
                      Expanded(
                        child: GestureDetector(
                          onTap: onForumTap,
                          child: Text(
                            thread.forum.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.colors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 14,
                      color: context.colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      compactCount(thread.replyCount),
                      style: TextStyle(
                        color: context.colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      shortDate(context, thread.createdAt),
                      style: TextStyle(
                        color: context.colors.outline,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ImageStrip extends StatelessWidget {
  const ImageStrip({
    super.key,
    required this.images,
    this.thumbnails = const [],
  });
  final List<String> images, thumbnails;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: images.length == 1 ? 178 : 100,
    child: Row(
      children: List.generate(
        images.length.clamp(0, 3),
        (index) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index < images.length - 1 ? 5 : 0),
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ImageViewerPage(images: images, initialIndex: index),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PolicyImage(
                      original: images[index],
                      thumbnail: index < thumbnails.length
                          ? thumbnails[index]
                          : '',
                    ),
                    if (index == 2 && images.length > 3)
                      IgnorePointer(
                        child: ColoredBox(
                          color: Colors.black45,
                          child: Center(
                            child: Text(
                              '+${images.length - 3}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class PostContent extends StatelessWidget {
  const PostContent({super.key, required this.content});
  final List<ContentPart> content;
  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final images = content
        .where((part) => part.type == ContentType.image && part.url.isNotEmpty)
        .map((part) => part.url)
        .toList();
    final children = <Widget>[];
    var inline = <ContentPart>[];
    void flush() {
      if (inline.isNotEmpty) {
        children.add(InlinePostText(parts: List.of(inline)));
        inline = [];
      }
    }

    for (final part in content) {
      if ([
        ContentType.text,
        ContentType.link,
        ContentType.mention,
        ContentType.emoji,
      ].contains(part.type)) {
        inline.add(part);
        continue;
      }
      flush();
      switch (part.type) {
        case ContentType.image:
          if (settings.hideMedia || part.url.isEmpty) break;
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ImageViewerPage(
                      images: images,
                      initialIndex: images.indexOf(part.url),
                    ),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: PolicyImage(
                    original: part.url,
                    thumbnail: part.thumbnail,
                    width: double.infinity,
                    fit: BoxFit.fitWidth,
                  ),
                ),
              ),
            ),
          );
        case ContentType.video:
          if (settings.hideMedia || part.url.isEmpty) break;
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: FilledButton.tonalIcon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => VideoPage(url: part.url),
                  ),
                ),
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: Text(context.l10n.video),
              ),
            ),
          );
        case ContentType.audio:
          if (part.url.isNotEmpty) {
            children.add(AudioBubble(url: part.url, label: part.text));
          }
        default:
          children.add(
            part.url.isEmpty
                ? Text(part.text)
                : TextButton(
                    onPressed: () => openExternal(context, part.url),
                    child: Text(context.l10n.unsupportedContent),
                  ),
          );
      }
    }
    flush();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
