import XCTest
@testable import HUSTCampusCore

final class FormEncodingTests: XCTestCase {
    func testFormEncodingEscapesQueryString() {
        let data = FormEncoding.encode([
            "queryString": "wlanuserip=abc&mac=deadbeef",
            "service": ""
        ])
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("queryString=wlanuserip%3Dabc%26mac%3Ddeadbeef"))
        XCTAssertTrue(text.contains("service="))
    }
}
