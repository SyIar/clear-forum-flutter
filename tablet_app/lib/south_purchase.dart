import 'package:html/dom.dart';

import 'forum_identity.dart';
import 'models.dart';
import 'site.dart';

class PurchaseOffer {
  const PurchaseOffer(this.threadID, this.postID, this.cents, this.action);
  final String threadID, postID;
  final int cents;
  final Uri action;
  String get id => '$threadID:$postID';
  String get price =>
      cents % 100 == 0 ? '${cents ~/ 100}' : (cents / 100).toStringAsFixed(2);
  bool valid(Uri page) {
    const site = ForumSite(Module.south);
    final fields = action.queryParameters;
    return site.threadKey(page) == 'south:$threadID' &&
        site.sameOrigin(action) &&
        action.path == '/job.php' &&
        !action.hasFragment &&
        cents >= 0 &&
        cents <= 9999999900 &&
        (postID == 'tpc' || RegExp(r'^[1-9][0-9]{0,17}$').hasMatch(postID)) &&
        action.queryParametersAll.values.every((v) => v.length == 1) &&
        fields.length == 4 &&
        fields['action'] == 'buytopic' &&
        fields['tid'] == threadID &&
        fields['pid'] == postID &&
        RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(fields['verify'] ?? '');
  }

  static PurchaseOffer? parse(Element node, Uri page) {
    const site = ForumSite(Module.south);
    if (node.localName != 'h6' ||
        !node.classes.contains('quote') ||
        !node.classes.contains('jumbotron')) {
      return null;
    }
    Element? body;
    var parent = node.parent;
    while (parent != null) {
      if (parent.localName == 'blockquote' ||
          parent.classes.contains('blockquote')) {
        return null;
      }
      if (parent.id.startsWith('read_')) body ??= parent;
      parent = parent.parent;
    }
    final thread = site.threadKey(page)?.split(':').last;
    final label = node.querySelector('span.s3')?.text ?? '';
    final prices = RegExp(r'([0-9]{1,8})(?:\.([0-9]{1,2}))?\s*SP')
        .allMatches(label)
        .toList();
    final buttons = node.querySelectorAll('input[type="button"][onclick]');
    if (body == null ||
        thread == null ||
        prices.length != 1 ||
        buttons.length != 1) {
      return null;
    }
    final script = buttons.single.attributes['onclick'] ?? '';
    final address = RegExp(
      r'''^\s*(?:window\.)?location\.href\s*=\s*(['"])([^'"]+)\1\s*;?\s*$''',
    ).firstMatch(script)?[2];
    final action = site.resolve(address, page);
    if (action == null) return null;
    final cents =
        int.parse(prices.single[1]!) * 100 +
        int.parse((prices.single[2] ?? '0').padRight(2, '0'));
    final offer = PurchaseOffer(thread, body.id.substring(5), cents, action);
    return offer.valid(page) ? offer : null;
  }
}

Iterable<PurchaseOffer> purchaseOffers(ForumPage page) sync* {
  Iterable<PurchaseOffer> collect(List<BodyBlock> blocks) sync* {
    for (final block in blocks) {
      if (block.offer != null) yield block.offer!;
      yield* collect(block.children);
    }
  }

  for (final post in page.posts) {
    yield* collect(post.blocks);
  }
}

/// An uncertain response is reconciled by reading the page, never resubmitted.
class PurchaseService {
  bool _busy = false;
  Future<ForumPage> buy(
    PurchaseOffer accepted,
    Uri page, {
    required Future<ForumPage> Function(Uri) load,
    required Future<void> Function(PurchaseOffer, Uri) submit,
  }) async {
    if (_busy || !accepted.valid(page)) {
      throw const ReaderFailure(FailureKind.unsupported);
    }
    _busy = true;
    try {
      ForumPage validate(ForumPage current) {
        if (!const ForumSite(Module.south).sameThread(current.url, page) ||
            !current.posts.any(
              (p) =>
                  p.id == 'read_${accepted.postID}' ||
                  p.id == 'post_${accepted.postID}',
            )) {
          throw const PurchaseIssue('Purchase result uncertain');
        }
        return current;
      }

      final fresh = validate(await load(page));
      final offer = purchaseOffers(fresh)
          .where((o) => o.id == accepted.id)
          .firstOrNull;
      if (offer == null) return fresh;
      if (offer.cents != accepted.cents) {
        throw const PurchaseIssue('Price changed');
      }
      try {
        await submit(offer, fresh.url);
      } catch (_) {
        /* Reconcile below. */
      }
      for (var attempt = 0; attempt < 3; attempt++) {
        final refreshed = validate(await load(fresh.url));
        if (!purchaseOffers(refreshed).any((o) => o.id == offer.id)) {
          return refreshed;
        }
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 600 * (attempt + 1)),
          );
        }
      }
      throw const PurchaseIssue('Purchase result uncertain');
    } finally {
      _busy = false;
    }
  }
}

class PurchaseIssue implements Exception {
  const PurchaseIssue(this.message);
  final String message;
}
