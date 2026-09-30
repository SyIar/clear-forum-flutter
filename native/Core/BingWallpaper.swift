import Foundation

struct BingWallpaper: Codable, Equatable, Sendable {
  let id: String
  let day: String
  let title: String
  let credit: String
  let source: URL
  let images: [URL]

  static let archive = URL(string: "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=zh-CN")!

  static func parse(_ data: Data) throws -> Self {
    let response = try JSONDecoder().decode(Archive.self, from: data)
    guard let item = response.images.first, item.wp == true,
          item.enddate.range(of: #"\A[0-9]{8}\z"#, options: .regularExpression) != nil,
          item.urlbase.range(of: #"\A/th\?id=OHR\.[A-Za-z0-9_-]+\z"#, options: .regularExpression) != nil else {
      throw Failure.unavailable
    }
    let images = ["1080x1920", "1920x1080"].compactMap {
      URL(string: "https://www.bing.com" + item.urlbase + "_" + $0 + ".jpg")
    }
    let source = URL(string: item.copyrightlink).flatMap { accepts($0) ? $0 : nil }
      ?? URL(string: "https://www.bing.com")!
    return Self(id: item.urlbase, day: item.enddate, title: String((item.title ?? "").prefix(200)),
                credit: String(item.copyright.prefix(1000)), source: source, images: images)
  }

  static func accepts(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
          url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
    return host == "bing.com" || host.hasSuffix(".bing.com")
  }

  static var localCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .autoupdatingCurrent
    return calendar
  }

  static func dayKey(_ date: Date, calendar: Calendar = localCalendar) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  static func nextMidnight(after date: Date, calendar: Calendar = localCalendar) -> Date {
    calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date.addingTimeInterval(3600)
  }

  enum Failure: Error { case unavailable, invalidResponse, oversizedImage }
  private struct Archive: Decodable { let images: [Item] }
  private struct Item: Decodable {
    let urlbase: String
    let enddate: String
    let title: String?
    let copyright: String
    let copyrightlink: String
    let wp: Bool?
  }
}

struct BingWallpaperSnapshot: Codable, Sendable {
  let wallpaper: BingWallpaper
  let image: Data
  let checkedDay: String

  func isCurrent(at date: Date, calendar: Calendar = BingWallpaper.localCalendar) -> Bool {
    let today = BingWallpaper.dayKey(date, calendar: calendar)
    return checkedDay == today && wallpaper.day >= today
  }
}
