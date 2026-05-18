import XCTest
@testable import HUSTCampusCore

final class RSAEncryptorTests: XCTestCase {
    func testLegacyEncryptMatchesKnownVector() {
        let encrypted = RSAEncryptor.legacyEncrypt(
            password: "123",
            mac: "5ae915bf808f82732e98e01f704f00cd"
        )
        XCTAssertEqual(
            encrypted,
            "91a0e02175f6a0b22ad23dac0d7f599806bc091f9fee1bfdada0d24d011dcdaed418296b7c0ec560f988d92a7bb25dbf7ff51752d9bc6482a8180e56f7b772079ab59844abaae91e6d1c4660dc872717f9218f89acc9b70bb32891f28bf9d8f173d81b0e36c828deac919783e4e909ad1c22f953947b4a7ed7c90ac18fd95aa2"
        )
    }
}
