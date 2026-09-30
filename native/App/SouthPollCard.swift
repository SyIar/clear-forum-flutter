import SwiftUI

struct SouthPollCard: View {
  let poll: SouthPoll
  let busy: Bool
  let openBrowser: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Label(AppText.text("Poll"), systemImage: "chart.bar.xaxis").forumFont(.headline)
        Spacer(minLength: 8)
        if let count = poll.participants {
          Text(AppText.format("%@ participants", String(describing: count.formatted()))).forumFont(.caption).foregroundStyle(.secondary)
        }
        if !information.isEmpty { InfoButton(title: AppText.text("Poll"), message: information) }
      }
      VStack(spacing: 8) {
        ForEach(poll.options) { option in
          VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
              Text("\(option.id + 1)").forumFont(.caption).monospacedDigit().foregroundStyle(.secondary)
                .frame(minWidth: 14)
              Text(option.title).forumFont(.subheadline).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
              if option.selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue).accessibilityLabel(AppText.text("Selected on website")) }
              if let votes = option.votes {
                Text(AppText.format("%@ votes", String(describing: votes.formatted()))).forumFont(.caption).monospacedDigit().foregroundStyle(.secondary)
              } else {
                Image(systemName: "eye.slash").font(.caption).foregroundStyle(.tertiary).accessibilityLabel(AppText.text("Votes hidden"))
              }
            }
            if let share = poll.share(of: option) {
              ProgressView(value: share).tint(.blue)
                .accessibilityLabel(AppText.text("Share of total votes")).accessibilityValue(share.formatted(.percent.precision(.fractionLength(0))))
            }
          }.padding(12).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        }
      }
      if poll.startsAt != nil || poll.endsAt != nil {
        VStack(alignment: .leading, spacing: 4) {
          if let start = poll.startsAt { Text(AppText.format("Started %@", String(describing: start))) }
          if let end = poll.endsAt { Text(AppText.format("Ends %@", String(describing: end))) }
        }.forumFont(.caption).foregroundStyle(.secondary)
      }
      Button(action: openBrowser) {
        Label(poll.canVote ? AppText.text("Vote") : AppText.text("View poll"), systemImage: "globe")
          .forumFont(.subheadline, weight: .medium).frame(maxWidth: .infinity).padding(.vertical, 4)
      }.buttonStyle(.glass).disabled(busy)
    }.padding(16).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
      .accessibilityElement(children: .contain)
  }
  private var information: String {
    var lines: [String] = []
    if let limit = poll.maximumChoices { lines.append(limit == 1 ? AppText.text("Single choice.") : AppText.format("Choose up to %@.", String(describing: limit))) }
    if poll.resultsHidden { lines.append(AppText.text("The website has hidden the vote counts.")) }
    if !poll.notice.isEmpty { lines.append(poll.notice) }
    return lines.joined(separator: "\n\n")
  }
}
