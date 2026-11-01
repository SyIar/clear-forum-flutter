import 'package:html/dom.dart';

import 'site.dart';
import 'strings.dart';

class PollOption {
  const PollOption(this.title, this.votes, this.selected);
  final String title;
  final int? votes;
  final bool selected;
}

// A display-only model. Voting remains in the authenticated website, as in the
// native client; form tokens and action fields never enter persisted metadata.
class SouthPoll {
  const SouthPoll(this.options, this.notice, this.participants);
  final List<PollOption> options;
  final String notice;
  final int? participants;
  int? get total => options.any((o) => o.votes == null)
      ? null
      : options.fold(0, (n, o) => n! + o.votes!);
  static SouthPoll? parse(Document doc, Uri page) {
    const site = ForumSite(Module.south);
    for (final form in doc.querySelectorAll('form[name=vote]')) {
      var parent = form.parent;
      var quoted = false;
      while (parent != null) {
        if (parent.id.startsWith('read_') ||
            parent.classes.contains('tpc_content') ||
            parent.localName == 'blockquote') {
          quoted = true;
        }
        parent = parent.parent;
      }
      final action = site.resolve(form.attributes['action'], page);
      if (quoted ||
          action == null ||
          !site.sameOrigin(action) ||
          action.path != '/job.php' ||
          action.query != 'action=vote' ||
          action.hasFragment) {
        continue;
      }
      final options = <PollOption>[];
      for (final row in form.querySelectorAll('tr')) {
        final cells = row.children
            .where((e) => const ['td', 'th'].contains(e.localName))
            .toList();
        if (cells.length != 2) continue;
        final controls = cells[0]
            .querySelectorAll('input')
            .where(
              (e) =>
                  const ['voteid', 'voteid[]'].contains(e.attributes['name']) &&
                  const ['checkbox', 'radio'].contains(e.attributes['type']),
            );
        if (controls.isEmpty &&
            !cells[1]
                .querySelectorAll('img')
                .any(
                  (e) => (e.attributes['src'] ?? '').endsWith('/tab-two.gif'),
                )) {
          continue;
        }
        final title = cells[0].text.trim();
        if (title.isEmpty || title.length > 4096 || options.length >= 100) {
          return null;
        }
        final count = AppStrings.pattern('pollVotesPattern')
            .firstMatch(cells[1].text)?[1];
        options.add(
          PollOption(
            title,
            int.tryParse(count?.replaceAll(',', '') ?? ''),
            controls.any((e) => e.attributes.containsKey('checked')),
          ),
        );
      }
      if (options.isNotEmpty) {
        return SouthPoll(
          options,
          form.querySelector('.tr4.s3')?.text.trim() ?? '',
          int.tryParse(
            AppStrings.pattern('pollParticipantsPattern')
                    .firstMatch(form.querySelector('.h')?.text ?? '')?[1]
                    ?.replaceAll(',', '') ??
                '',
          ),
        );
      }
    }
    return null;
  }
}
