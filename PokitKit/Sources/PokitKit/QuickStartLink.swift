import Foundation

/// The link a complication uses to open the app in a particular mode.
///
/// It lives here because both sides need it: the widget extension builds the URL and the
/// app reads it.
public enum QuickStartLink {
    private static let prefix = "wristmeter://mode/"

    public static func url(for mode: MultimeterMode) -> URL? {
        URL(string: prefix + String(mode.rawValue))
    }

    /// The mode a link asks for, or `nil` if the URL is not such a link. Idle is not a mode
    /// to start in, so it is rejected like any unknown value.
    public static func mode(from url: URL) -> MultimeterMode? {
        let text = url.absoluteString
        guard text.hasPrefix(prefix),
              let raw = UInt8(text.dropFirst(prefix.count)),
              let mode = MultimeterMode(rawValue: raw),
              mode != .idle else {
            return nil
        }
        return mode
    }
}
