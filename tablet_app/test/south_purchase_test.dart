import 'package:flutter_test/flutter_test.dart';
import 'package:forum_tablet/models.dart';
import 'package:forum_tablet/parsers.dart';
import 'package:forum_tablet/site.dart';
import 'package:forum_tablet/south_purchase.dart';

const site = ForumSite(Module.south);
final url = site.home.resolve('/read.php?tid=20');
ForumPage page({
  int? price = 5,
  String token = 'token',
}) => PageParser(site).parse(
  '<table class="js-post"><tr><td><div class="tpc_content" id="read_tpc">'
  '${price == null ? 'Unlocked body' : '<h6 class="quote jumbotron"><span class="s3">$price SP</span><input type="button" onclick="location.href=\'job.php?action=buytopic&amp;tid=20&amp;pid=tpc&amp;verify=$token\';"></h6>'}'
  '</div></td></tr></table>',
  url,
);
void main() {
  test(
    'Purchase controls retain price and bind action to this thread and post',
    () {
      final offer = purchaseOffers(page()).single;
      expect(offer.cents, 500);
      expect(offer.price, '5');
      expect(offer.valid(url), isTrue);
      expect(offer.valid(site.home.resolve('/read.php?tid=21')), isFalse);
      expect(
        PurchaseOffer(
          '20',
          'tpc',
          500,
          offer.action.replace(host: 'other.example'),
        ).valid(url),
        isFalse,
      );
    },
  );
  test('A changed price prevents submission', () async {
    var submitted = false;
    await expectLater(
      PurchaseService().buy(
        purchaseOffers(page()).single,
        url,
        load: (_) async => page(price: 6),
        submit: (_, _) async {
          submitted = true;
        },
      ),
      throwsA(isA<PurchaseIssue>()),
    );
    expect(submitted, isFalse);
  });
  test('An uncertain purchase response is checked without replay and uses the fresh token', () async {
    var reads = 0, submissions = 0;
    final result = await PurchaseService().buy(
      purchaseOffers(page()).single,
      url,
      load: (_) async =>
          ++reads == 1 ? page(token: 'fresh') : page(price: null),
      submit: (offer, _) async {
        submissions++;
        expect(offer.action.queryParameters['verify'], 'fresh');
        throw const ReaderFailure(FailureKind.network);
      },
    );
    expect(submissions, 1);
    expect(reads, 2);
    expect(purchaseOffers(result), isEmpty);
  });
}
