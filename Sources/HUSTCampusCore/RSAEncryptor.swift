import BigInt
import Foundation

public enum RSAEncryptor {
    private static let legacyExponent = BigUInt(65537)
    private static let legacyModulus = BigUInt(
        "94dd2a8675fb779e6b9f7103698634cd400f27a154afa67af6166a43fc26417222a79506d34cacc7641946abda1785b7acf9910ad6a0978c91ec84d40b71d2891379af19ffb333e7517e390bd26ac312fe940c340466b4a5d4af1d65c3b5944078f96a1a51a5a53e4bc302818b7c9f63c4a1b07bd7d874cef1c3d4b2f5eb7871",
        radix: 16
    )!

    public static func legacyEncrypt(password: String, mac: String) -> String {
        let payload = "\(password)>\(mac)"
        let message = BigUInt(Data(payload.utf8))
        let encrypted = message.power(legacyExponent, modulus: legacyModulus)
        return leftPadHex(String(encrypted, radix: 16), length: 256)
    }

    public static func portalEncrypt(
        password: String,
        mac: String,
        exponentHex: String,
        modulusHex: String
    ) throws -> String {
        guard
            let exponent = BigUInt(exponentHex, radix: 16),
            let modulus = BigUInt(modulusHex, radix: 16)
        else {
            throw AutologinError.invalidResponse("RSA 公钥格式无效")
        }

        let payload = "\(password)>\(mac)"
        let chunkSize = 2 * highIndex(of: modulus)
        guard chunkSize > 0 else {
            throw AutologinError.invalidResponse("RSA modulus 过短")
        }

        var values = payload.reversed().map { BigUInt($0.unicodeScalars.first?.value ?? 0) }
        while values.count % chunkSize != 0 {
            values.append(0)
        }

        var chunks: [String] = []
        for start in stride(from: 0, to: values.count, by: chunkSize) {
            var block = BigUInt(0)
            for (offset, value) in values[start ..< min(start + chunkSize, values.count)].enumerated() {
                block += value << (8 * offset)
            }
            let encrypted = block.power(exponent, modulus: modulus)
            chunks.append(padHexToWord(String(encrypted, radix: 16)))
        }
        return chunks.joined(separator: " ")
    }

    private static func highIndex(of value: BigUInt) -> Int {
        var index = 0
        while (value >> (16 * (index + 1))) > 0 {
            index += 1
        }
        return index
    }

    private static func leftPadHex(_ value: String, length: Int) -> String {
        if value.count >= length {
            return value
        }
        return String(repeating: "0", count: length - value.count) + value
    }

    private static func padHexToWord(_ value: String) -> String {
        if value.isEmpty {
            return "0000"
        }
        let padding = (4 - value.count % 4) % 4
        return String(repeating: "0", count: padding) + value
    }
}
