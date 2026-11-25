#if canImport(UIKit)
import SwiftUI
import UIKit

/// Keep native edge margins without adding them to the window's safe area.
struct WindowSafeAreaPadding: ViewModifier {
    var isEnabled = true
    var minimumInset: CGFloat = 0
    var minimumHorizontalInset: CGFloat = 0
    var balancesLandscapeMargins = false
    var clearsCameraByRow = false

    @Environment(\.layoutDirection) private var layoutDirection
    @State private var window = WindowSafeArea()

    func body(content: Content) -> some View {
        let insets = isEnabled ? window.insets : .zero
        let minimum = isEnabled ? minimumInset : 0
        let horizontal = isEnabled ? minimumHorizontalInset : 0
        let rtl = layoutDirection == .rightToLeft
        let balance = isEnabled && balancesLandscapeMargins && window.size.width > window.size.height
        let corners = balance && clearsCameraByRow ? window.cameraCorners : []
        let common = corners.isEmpty ? max(insets.left, insets.right) : min(insets.left, insets.right)
        let leading = balance ? common : (rtl ? insets.right : insets.left)
        let trailing = balance ? common : (rtl ? insets.left : insets.right)
        content
            .environment(\.playerCameraCorners, corners)
            .padding(EdgeInsets(
                top: max(minimum, insets.top), leading: max(horizontal, leading),
                bottom: max(minimum, insets.bottom), trailing: max(horizontal, trailing)
            ))
            .ignoresSafeArea()
            .background(WindowSafeAreaReader { window = $0 }.frame(width: 0, height: 0).allowsHitTesting(false))
    }
}

struct WindowSafeArea: Equatable {
    var insets: UIEdgeInsets = .zero
    var size: CGSize = .zero
    var cameraCorners: [CGRect] = []
}

private struct WindowSafeAreaReader: UIViewRepresentable {
    let onChange: (WindowSafeArea) -> Void

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = onChange
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ReaderView, context: Context) {
        view.onChange = onChange
    }

    final class ReaderView: UIView {
        var onChange: ((WindowSafeArea) -> Void)?
        private var reported: WindowSafeArea?
        private var sceneObservation: NSKeyValueObservation?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            sceneObservation = window?.windowScene?.observe(\.effectiveGeometry, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.report() }
            }
            report()
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }

        private func report() {
            guard let window else { return }
            let insets = window.safeAreaInsets
            let bounds = window.bounds
            var value = WindowSafeArea(insets: insets, size: bounds.size)
            #if canImport(SwiftUI, _version: 8.0.85)
            if #available(iOS 27.1, *), bounds.width > bounds.height, insets.left != insets.right {
                value.cameraCorners = window.reservedRegions(kind: .occlusion).map(\.frame).filter { rect in
                    (rect.minY <= bounds.minY || rect.maxY >= bounds.maxY) && rect.height < bounds.height
                        && (insets.left > insets.right ? rect.minX <= bounds.minX : rect.maxX >= bounds.maxX)
                }
            }
            #endif
            guard value != reported else { return }
            reported = value
            DispatchQueue.main.async { [weak self] in self?.onChange?(value) }
        }
    }
}
#endif
