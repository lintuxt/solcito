import Foundation
import Darwin
import HIDPP

/// ANSI styling helpers + per-device icons. Output is wrapped in escape
/// codes only when stdout is a TTY — piped/redirected output stays plain
/// so log files and `grep` keep working.
enum Style {
    static let useColor: Bool = isatty(fileno(stdout)) != 0

    // Reset + attributes
    static let reset = "\u{1B}[0m"
    static let bold = "\u{1B}[1m"
    static let dim = "\u{1B}[2m"
    static let italic = "\u{1B}[3m"

    // Foreground colors (8-color + bright)
    static let red = "\u{1B}[31m"
    static let green = "\u{1B}[32m"
    static let yellow = "\u{1B}[33m"
    static let blue = "\u{1B}[34m"
    static let magenta = "\u{1B}[35m"
    static let cyan = "\u{1B}[36m"
    static let gray = "\u{1B}[90m"
    static let brightCyan = "\u{1B}[96m"
    static let brightGreen = "\u{1B}[92m"
    static let brightYellow = "\u{1B}[93m"
    static let brightWhite = "\u{1B}[97m"

    /// Wrap `text` in the given escape codes (only when on a TTY).
    static func wrap(_ text: String, _ codes: String...) -> String {
        guard useColor else { return text }
        return codes.joined() + text + reset
    }
}

// Convenience styled-string builders, named for what they convey rather
// than the underlying ANSI code, so call sites read like prose.
enum Tone {
    static func title(_ s: String) -> String { Style.wrap(s, Style.bold, Style.brightCyan) }
    static func heading(_ s: String) -> String { Style.wrap(s, Style.bold) }
    static func subtle(_ s: String) -> String { Style.wrap(s, Style.dim) }
    static func muted(_ s: String) -> String { Style.wrap(s, Style.gray) }
    static func device(_ s: String) -> String { Style.wrap(s, Style.brightWhite) }
    static func ok(_ s: String) -> String { Style.wrap(s, Style.brightGreen) }
    static func warn(_ s: String) -> String { Style.wrap(s, Style.yellow) }
    static func error(_ s: String) -> String { Style.wrap(s, Style.red) }
    static func receiver(_ s: String) -> String { Style.wrap(s, Style.cyan) }
}

/// Plain monochrome marker for a paired device. The kind is already
/// surfaced by the device label, so we don't differentiate per kind.
func icon(for kind: PairedDeviceKind?) -> String {
    return Icons.device
}

enum Icons {
    static let receiver = Style.wrap("●", Style.cyan)
    static let device = Style.wrap("✓", Style.brightGreen)
}
