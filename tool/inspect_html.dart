import 'dart:convert';
import 'dart:io';

import 'package:clean_forum/core/models.dart';
import 'package:clean_forum/core/parser.dart';
import 'package:html/parser.dart' as html;

// Prints structural counts only. Never commits or prints captured page contents.
void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/inspect_html.dart <local-html> <page-url>',
    );
    exitCode = 64;
    return;
  }
  final source = File(arguments[0]).readAsStringSync();
  final doc = html.parse(source);
  final page = ForumParser().parse(source, Uri.parse(arguments[1]));
  Iterable<BodyBlock> flatten(List<BodyBlock> blocks) sync* {
    for (final block in blocks) {
      yield block;
      yield* flatten(block.children);
    }
  }

  final blocks = page.posts.expand((post) => flatten(post.blocks)).toList();
  stdout.writeln(
    jsonEncode({
      'sourcePosts': doc.querySelectorAll('article.message--post').length,
      'sourceBodyIframes': doc
          .querySelectorAll('.message-body .bbWrapper iframe')
          .length,
      'parsedPosts': page.posts.length,
      'parsedEntries': page.entries.length,
      'embeddedMediaBlocks': blocks
          .where((b) => b.kind == BlockKind.embeddedMedia)
          .length,
      'imageBlocks': blocks.where((b) => b.kind == BlockKind.image).length,
      'emptyPosts': page.posts.where((post) => post.blocks.isEmpty).length,
      'pageNumber': page.pageNumber,
      'hasPrevious': page.previous != null,
      'hasNext': page.next != null,
    }),
  );
}
