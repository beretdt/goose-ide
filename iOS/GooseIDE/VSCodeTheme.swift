import SwiftUI
import UIKit

/// The VS Code Dark+ palette and metrics, so the editor looks like the thing
/// people already know. Every colour here is from the default dark theme.
enum VSCode {
    // Surfaces
    static let editorBackground = Color(hex: 0x1E1E1E)
    static let sidebar = Color(hex: 0x252526)
    static let activityBar = Color(hex: 0x333333)
    static let tabActive = Color(hex: 0x1E1E1E)
    static let tabInactive = Color(hex: 0x2D2D2D)
    static let statusBar = Color(hex: 0x007ACC)
    static let titleBar = Color(hex: 0x3C3C3C)
    static let panelBorder = Color(hex: 0x3C3C3C)
    static let gutter = Color(hex: 0x1E1E1E)
    static let gutterText = Color(hex: 0x858585)
    static let highlight = Color(hex: 0x094771)

    // Text
    static let text = Color(hex: 0xD4D4D4)
    static let dimText = Color(hex: 0x9D9D9D)
    static let faintText = Color(hex: 0x6E7681)

    // Syntax, Dark+ exactly
    static let keyword = Color(hex: 0x569CD6)
    static let controlKeyword = Color(hex: 0xC586C0)
    static let string = Color(hex: 0xCE9178)
    static let number = Color(hex: 0xB5CEA8)
    static let comment = Color(hex: 0x6A9955)
    static let type = Color(hex: 0x4EC9B0)
    static let function = Color(hex: 0xDCDCAA)
    static let punctuation = Color(hex: 0xD4D4D4)

    // Status
    static let success = Color(hex: 0x89D185)
    static let error = Color(hex: 0xF14C4C)
    static let warning = Color(hex: 0xCCA700)

    static let codeFont = UIFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
    static let codeFontBold = UIFont.monospacedSystemFont(ofSize: 13.5, weight: .semibold)
    static let gutterFont = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    /// A line height that keeps the caret comfortable on a phone screen.
    static var lineHeight: CGFloat { codeFont.lineHeight + 2 }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// A slim activity-bar icon, the way VS Code shows its rail.
struct ActivityButton: View {
    let systemImage: String
    let label: String
    var isActive = false
    var badge: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(isActive ? Color.white : VSCode.dimText)
                    .background(isActive ? VSCode.highlight : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(VSCode.statusBar)
                        .clipShape(Capsule())
                        .offset(x: 4, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
