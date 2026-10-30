import Foundation

/// The `--project <path>` development flag. Keeping parsing separate makes the
/// missing-value case explicit instead of silently starting the library.
enum ProjectArgument: Equatable, Sendable {
    case absent
    case missingValue
    case path(String)

    static func parse(_ arguments: [String]) -> ProjectArgument {
        guard let index = arguments.firstIndex(of: "--project") else { return .absent }
        guard arguments.indices.contains(index + 1) else { return .missingValue }

        let value = arguments[index + 1]
        guard !value.hasPrefix("--") else { return .missingValue }
        return .path(value)
    }
}
