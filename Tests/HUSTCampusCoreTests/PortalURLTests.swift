import XCTest
@testable import HUSTCampusCore

final class PortalURLTests: XCTestCase {
    func testParsePortalURL() throws {
        let url = URL(string: "http://172.18.18.61:8080/eportal/index.jsp?wlanuserip=abc&mac=deadbeef&t=wireless-v2")!
        let parsed = try PortalURL.parse(url)

        XCTAssertEqual(parsed.baseURL.absoluteString, "http://172.18.18.61:8080/eportal")
        XCTAssertEqual(parsed.queryString, "wlanuserip=abc&mac=deadbeef&t=wireless-v2")
        XCTAssertEqual(parsed.mac, "deadbeef")
    }
}
