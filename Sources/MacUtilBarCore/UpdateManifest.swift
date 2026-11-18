import Foundation

/// Public release metadata only. Never interpreted as commands or installed automatically.
public struct UpdateManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let product: String
    public let bundleIdentifier: String
    public let version: String
    public let build: Int
    public let minimumSystemVersion: String
    public let releaseURL: URL

    public static let repository = "PanggNOTlovebean/MacUtils-Releases"
    public static let maximumBytes = 65_536

    public static func decode(_ data: Data, product: String, bundleIdentifier: String) throws -> Self {
        guard data.count <= maximumBytes else { throw Failure.invalidManifest }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == 1, value.product == product,
              value.bundleIdentifier == bundleIdentifier, value.build > 0,
              components(value.version, count: 3) != nil,
              components(value.minimumSystemVersion, count: 3) != nil,
              value.releaseURL.absoluteString == "https://github.com/\(repository)/releases/tag/\(product)-v\(value.version)"
        else { throw Failure.invalidManifest }
        return value
    }

    public func isNewer(than build: Int) -> Bool { self.build > build }
    public func supports(_ system: OperatingSystemVersion) -> Bool {
        guard let minimum = Self.components(minimumSystemVersion, count: 3) else { return false }
        let current = [system.majorVersion, system.minorVersion, system.patchVersion]
        return !current.lexicographicallyPrecedes(minimum)
    }

    private static func components(_ string: String, count: Int) -> [Int]? {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == count else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
                  part.count == 1 || part.first != "0", let number = Int(part), number <= 999_999 else { return nil }
            numbers.append(number)
        }
        return numbers
    }

    public enum Failure: Error { case invalidManifest, unavailable }
}
