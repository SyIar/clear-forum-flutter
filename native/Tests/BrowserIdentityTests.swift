import Foundation
import XCTest
@testable import ForumCore

final class BrowserIdentityTests: XCTestCase {
  private func isolatedDefaults() throws -> (String, UserDefaults) {
    let name = "BrowserIdentityTests.\(UUID())"
    return (name, try XCTUnwrap(UserDefaults(suiteName: name)))
  }

  func testFreshInstallCanMakeGuestRequestWithoutWebKitOrJavaScript() throws {
    let (name, defaults) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    let identity = BrowserIdentity.userAgent(for: .south, defaults: defaults, systemVersion: "27.2", isPad: false)
    let request = try ForumRequest.page(site: .south, url: SouthSitePolicy.start, userAgent: identity, cookies: [])
    XCTAssertTrue(identity.contains("Macintosh"))
    XCTAssertFalse(identity.contains("Mobile"))
    XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), identity)
    XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
  }

  func testIdentitySurvivesRelaunchAndOSUpdate() throws {
    let (name, defaults) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    let first = BrowserIdentity.userAgent(for: .south, defaults: defaults, systemVersion: "27.2", isPad: false)
    let reopened = try XCTUnwrap(UserDefaults(suiteName: name))
    XCTAssertEqual(BrowserIdentity.userAgent(for: .south, defaults: reopened, systemVersion: "28.0", isPad: false), first)
  }

  func testUpgradeReplacesSouthMobileIdentityWithoutTouchingSimp() throws {
    let (name, defaults) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    let prior = "Mozilla/5.0 (iPhone; CPU iPhone OS 27_2 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148"
    defaults.set(prior, forKey: "forum_south_browser_user_agent")
    defaults.set(prior, forKey: "forum_simp_browser_user_agent")
    XCTAssertEqual(BrowserIdentity.userAgent(for: .south, defaults: defaults, systemVersion: "27.2", isPad: false), BrowserIdentity.southDesktop)
    XCTAssertEqual(defaults.string(forKey: "forum_south_browser_user_agent"), BrowserIdentity.southDesktop)
    XCTAssertEqual(BrowserIdentity.userAgent(for: .simp, defaults: defaults, systemVersion: "27.2", isPad: false), prior)
  }

  func testForumsDoNotOverwriteEachOthersIdentity() throws {
    let (name, defaults) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set("Existing-Simp-Identity", forKey: "forum_simp_browser_user_agent")
    let south = BrowserIdentity.userAgent(for: .south, defaults: defaults, systemVersion: "27.2", isPad: false)
    XCTAssertNotEqual(south, "Existing-Simp-Identity")
    XCTAssertEqual(defaults.string(forKey: "forum_simp_browser_user_agent"), "Existing-Simp-Identity")
    XCTAssertEqual(defaults.string(forKey: "forum_south_browser_user_agent"), south)
  }

  func testInvalidStoredIdentityCannotBlockStartupOrInjectHeaders() throws {
    let (name, defaults) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    for invalid in ["", "   ", "Bad\r\nCookie: injected", String(repeating: "x", count: 2049)] {
      defaults.set(invalid, forKey: "forum_south_browser_user_agent")
      let identity = BrowserIdentity.userAgent(for: .south, defaults: defaults, systemVersion: "27.2", isPad: false)
      XCTAssertTrue(identity.hasPrefix("Mozilla/5.0"))
      XCTAssertFalse(identity.contains("\n"))
      XCTAssertNoThrow(try ForumRequest.page(site: .south, url: SouthSitePolicy.start, userAgent: identity, cookies: []))
    }
  }

  func testPadIdentityAndMalformedVersionAreAlwaysUsable() throws {
    let (name, defaults) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    let identity = BrowserIdentity.userAgent(for: .south, defaults: defaults, systemVersion: "unexpected\r\nvalue", isPad: true)
    XCTAssertEqual(identity, BrowserIdentity.southDesktop)
    XCTAssertFalse(identity.contains("\r"))
    XCTAssertFalse(identity.contains("\n"))
    let simp = BrowserIdentity.userAgent(for: .simp, defaults: defaults, systemVersion: "unexpected\r\nvalue", isPad: true)
    XCTAssertTrue(simp.contains("iPad; CPU OS 18_0"))
  }
}

#if os(macOS)
import AppKit
import WebKit

@MainActor
private final class IdentityPageObserver: NSObject, WKNavigationDelegate {
  let completed: XCTestExpectation
  var observedIdentity: String?
  var failure: Error?
  init(completed: XCTestExpectation) { self.completed = completed }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    // Only evaluate after a local document loads; production startup does not evaluate JavaScript.
    webView.evaluateJavaScript("navigator.userAgent") { [self] value, error in
      observedIdentity = value as? String
      failure = error
      completed.fulfill()
    }
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    failure = error; completed.fulfill()
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    failure = error; completed.fulfill()
  }
}

extension BrowserIdentityTests {
  @MainActor func testRealWebKitLoadsLocalPageWithSameIdentityAsReader() async throws {
    _ = NSApplication.shared
    let (name, defaults) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    let identity = BrowserIdentity.userAgent(for: .south, defaults: defaults, systemVersion: "27.2", isPad: false)
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.preferredContentMode = .desktop
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), configuration: configuration)
    webView.customUserAgent = identity
    let loaded = expectation(description: "WebKit loads a local fixture")
    let observer = IdentityPageObserver(completed: loaded)
    webView.navigationDelegate = observer
    webView.loadHTMLString("<!doctype html><html><body>Guest fixture</body></html>", baseURL: nil)
    await fulfillment(of: [loaded], timeout: 20)
    webView.stopLoading()
    XCTAssertNil(observer.failure)
    let request = try ForumRequest.page(site: .south, url: SouthSitePolicy.start, userAgent: identity, cookies: [])
    XCTAssertEqual(observer.observedIdentity, request.value(forHTTPHeaderField: "User-Agent"))
  }
}
#endif
