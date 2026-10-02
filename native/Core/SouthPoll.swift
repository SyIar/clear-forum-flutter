import Foundation
import SwiftSoup

struct SouthPollOption: Identifiable, Equatable, Codable {
  let id: Int
  let title: String
  let votes: Int?
  let selected: Bool
}

// Display metadata only. Form tokens and vote actions are never retained here.
struct SouthPoll: Equatable, Codable {
  let options: [SouthPollOption]
  let participants: Int?
  let maximumChoices: Int?
  let startsAt: String?
  let endsAt: String?
  let notice: String
  let canVote: Bool
  var resultsHidden: Bool { options.contains { $0.votes == nil } }
  var totalVotes: Int? {
    guard !resultsHidden else { return nil }
    return options.reduce(0) { $0 + ($1.votes ?? 0) }
  }
  func share(of option: SouthPollOption) -> Double? {
    guard let total = totalVotes, total > 0, let count = option.votes else { return nil }
    return Double(count) / Double(total)
  }
}

enum SouthPollParser {
  static func parse(_ root: Element, page: URL) -> SouthPoll? {
    guard SouthSitePolicy.isThread(page) else { return nil }
    let forms = (try? root.select("form[name=vote]").array()) ?? []
    for form in forms {
      guard !form.parents().contains(where: { $0.id().hasPrefix("read_") || $0.hasClass("tpc_content") || $0.tagName() == "blockquote" }),
            let action = SouthSitePolicy.resolve(attr(form, "action"), from: page),
            SouthSitePolicy.sameOrigin(action), action.path == "/job.php", action.fragment == nil,
            URLComponents(url: action, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "action", value: "vote")] else { continue }
      if let poll = parseForm(form) { return poll }
    }
    return nil
  }

  private static func parseForm(_ form: Element) -> SouthPoll? {
    let rows = (try? form.select("tr").array()) ?? []
    var options: [SouthPollOption] = []
    var hasEnabledChoice = false
    var hasRadio = false
    for row in rows {
      let cells = row.getChildNodes().compactMap { $0 as? Element }.filter { ["th", "td"].contains($0.tagName()) }
      guard cells.count == 2 else { continue }
      let controls = ((try? cells[0].select("input").array()) ?? []).filter {
        ["voteid[]", "voteid"].contains(attr($0, "name")) && ["checkbox", "radio"].contains(attr($0, "type").lowercased())
      }
      // Results-only rows keep the PHPWind bar image even after inputs disappear.
      let hasResultBar = ((try? cells[1].select("img[src]").array()) ?? []).contains {
        URL(string: attr($0, "src"))?.lastPathComponent == "tab-two.gif"
      }
      guard !controls.isEmpty || hasResultBar else { continue }
      let title = text(cells[0])
      guard !title.isEmpty, title.utf8.count <= 4096, options.count < 100 else { return nil }
      let resultText = text(cells[1])
      let count = capture(resultText, #"^\s*([0-9]+(?:,[0-9]{3})*)\s*\u7968(?:\s|$|[\(\uff08])"#).flatMap(number)
      options.append(SouthPollOption(id: options.count, title: title, votes: count, selected: controls.contains { $0.hasAttr("checked") }))
      hasEnabledChoice = hasEnabledChoice || controls.contains { !$0.hasAttr("disabled") }
      hasRadio = hasRadio || controls.contains { attr($0, "type").lowercased() == "radio" }
    }
    guard !options.isEmpty else { return nil }
    let header = text(try? form.select("th.h,td.h").first())
    let participants = capture(header, #"\u603b\u5171\u6709\s*([0-9]+(?:,[0-9]{3})*)\s*\u4eba\u53c2\u4e0e"#).flatMap(number)
    let allText = text(form)
    let limit = capture(allText, #"\u9650\u9009\u4e2a\u6570\s*[:\uff1a]\s*([0-9]+)"#).flatMap(number)
    let maximum = hasRadio ? 1 : limit.flatMap { (1...options.count).contains($0) ? $0 : nil }
    let datePattern = #"\u53d1\u8d77\u4e8e\s*[:\uff1a]\s*([0-9]{4}-[0-9]{1,2}-[0-9]{1,2}\s+[0-9]{1,2}:[0-9]{2})\s*\u81f3\s*([0-9]{4}-[0-9]{1,2}-[0-9]{1,2}\s+[0-9]{1,2}:[0-9]{2})"#
    let notice = text(try? form.select("th.tr4.s3,td.tr4.s3").first())
    let submit = ((try? form.select("input[type=submit],button[type=submit]").array()) ?? []).contains { !$0.hasAttr("disabled") }
    return SouthPoll(options: options, participants: participants, maximumChoices: maximum,
                     startsAt: capture(header, datePattern), endsAt: capture(header, datePattern, group: 2),
                     notice: String(notice.prefix(2048)), canVote: hasEnabledChoice && submit)
  }
  private static func number(_ value: String) -> Int? {
    guard let value = Int(value.replacingOccurrences(of: ",", with: "")), (0...1_000_000_000).contains(value) else { return nil }
    return value
  }
  private static func attr(_ node: Element, _ name: String) -> String { (try? node.attr(name)) ?? "" }
  private static func text(_ node: Element?) -> String { (try? node?.text()) ?? "" }
  private static func capture(_ text: String, _ pattern: String, group: Int = 1) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: group), in: text) else { return nil }
    return String(text[range])
  }
}
