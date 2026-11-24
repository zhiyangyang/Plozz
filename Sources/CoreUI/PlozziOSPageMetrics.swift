#if os(iOS)
import SwiftUI

/// Shared page geometry for the iPhone/iPad shells.
///
/// Media rails and grids keep their own density-aware card metrics
/// (`PlozzMetrics`, `PlozziOSMediaRailLayout`). This type answers the other
/// question: where does ordinary page content sit relative to the screen edge
/// and the navigation title?
///
/// Values are deliberately limited to roles that pages actually share. Full
/// bleed media, the Home hero and the player continue to own their geometry.
public enum PlozziOSPageMetrics {
    /// Compact widths occur on iPad in Slide Over, Split View and narrow Stage
    /// Manager windows, not only on phones.
    public static let compactPageInset: CGFloat = 20
    public static let regularPageInset: CGFloat = 32
    /// Matches the desktop media rail's existing outer edge.
    public static let desktopPageInset: CGFloat = DesktopMediaRailLayout.pageInset

    public static let sectionSpacing: CGFloat = 28
    public static let headerSpacing: CGFloat = 12
    public static let rowMinHeight: CGFloat = 52

    /// Settings lists and forms.
    public static let formMaxWidth: CGFloat = 960
    /// Account, auth and long-form reading pages.
    public static let readingMaxWidth: CGFloat = 720
    /// Profile and compact editors.
    public static let editorMaxWidth: CGFloat = 720

    public static func pageInset(
        for sizeClass: UserInterfaceSizeClass?,
        usesDesktopSizing: Bool = false
    ) -> CGFloat {
        if usesDesktopSizing { return desktopPageInset }
        return sizeClass == .compact ? compactPageInset : regularPageInset
    }
}
#endif
