import Foundation

public enum FormEncoding {
    public static func encode(_ fields: [String: String]) -> Data {
        fields
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key.formEscaped())=\($0.value.formEscaped())" }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }
}

private extension String {
    func formEscaped() -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+") ?? self
    }
}
