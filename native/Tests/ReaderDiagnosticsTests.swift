import Foundation
import XCTest
@testable import ForumCore

final class ReaderDiagnosticsTests: XCTestCase {
  func testExportRetainsStructuralEvidenceWithoutCredentialsOrScripts() {
    let source = """
      <script>const cookie = 'script-secret';</script><meta content="meta-secret">
      <div class="tpc_content" id="read_tpc"><p>Example body</p>
      <img src="https://images.example/photo.jpg?token=image-secret" data-src="https://images.example/large.jpg" onload="event-secret" width="100">
      <a href="read.php?tid=20&amp;verify=query-secret">Topic</a>
      <input name="csrf" type="hidden" value="form-secret"><textarea>entered-secret</textarea>
      <div data-token="attribute-secret">Example footer</div></div>
      """
    let result = ReaderDiagnostics.html(source)
    for secret in ["script-secret", "meta-secret", "image-secret", "event-secret", "query-secret", "form-secret", "entered-secret", "attribute-secret"] {
      XCTAssertFalse(result.contains(secret), secret)
    }
    XCTAssertTrue(result.contains("tpc_content"))
    XCTAssertTrue(result.contains("Example body"))
    XCTAssertTrue(result.contains("photo.jpg"))
    XCTAssertTrue(result.contains("data-src"))
    XCTAssertTrue(result.contains("tid=20"))
    XCTAssertFalse(result.contains("onload"))
  }
  func testDiagnosticAddressesRedactSignedParametersAndCredentials() {
    let output = ReaderDiagnostics.address("https://user:secret@example.org/file?tid=20&signature=private#token")
    XCTAssertFalse(output.contains("user"))
    XCTAssertFalse(output.contains("secret"))
    XCTAssertFalse(output.contains("private"))
    XCTAssertFalse(output.contains("#token"))
    XCTAssertTrue(output.contains("tid=20"))
    XCTAssertEqual(ReaderDiagnostics.address("read.php?tid-20-fpage-2.html"), "read.php?tid-20-fpage-2.html")
  }
  func testOversizedCaptureDoesNotEnterTheExportBuffer() {
    XCTAssertEqual(ReaderDiagnostics.html(String(repeating: "x", count: 8 * 1024 * 1024 + 1)), "[source unavailable]")
  }
}
