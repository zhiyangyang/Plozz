#if os(iOS)
import SwiftUI
import UIKit

/// Rasterizes the stock ambient mesh once per screen size and color set.
///
/// The page background is a very soft 3x3 gradient, so a low-resolution bitmap
/// is visually indistinguishable from the live shader. Every tab and destination
/// used to instantiate its own full-screen `MeshGradient`, including layers that
/// were fully covered by another background. Rendering the stock mesh once and
/// compositing a cached image keeps navigation from paying for several mesh
/// passes at 120Hz.
struct CachedAmbientMesh: View {
    let colors: [Color]

    @State private var image: UIImage?
    @State private var renderedKey: String?

    var body: some View {
        GeometryReader { proxy in
            let key = Self.key(colors: colors, size: proxy.size)
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                } else {
                    AmbientGradientBackground.mesh(colors: colors)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: key) {
                guard renderedKey != key || image == nil else { return }
                await Task.yield()
                guard !Task.isCancelled,
                      let rendered = AmbientMeshRasterizer.image(
                        colors: colors, size: proxy.size, key: key
                      )
                else { return }
                guard !Task.isCancelled else { return }
                image = rendered
                renderedKey = key
            }
        }
    }

    private static func key(colors: [Color], size: CGSize) -> String {
        "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))|\(colorKey(colors))"
    }

    fileprivate static func colorKey(_ colors: [Color]) -> String {
        colors.map { color in
            let ui = UIColor(color)
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            guard ui.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
                return ui.description
            }
            return String(format: "%.3f,%.3f,%.3f,%.3f", red, green, blue, alpha)
        }.joined(separator: "|")
    }
}

@MainActor
private enum AmbientMeshRasterizer {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(colors: [Color], size: CGSize, key: String) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let cacheKey = "\(key)|\(CachedAmbientMesh.colorKey(colors))" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }

        // A soft mesh needs no more than this; stretching it to the full screen
        // is indistinguishable and keeps the one-time render cheap.
        let aspect = min(max(size.height / max(size.width, 1), 0.25), 2.5)
        let renderSize = CGSize(width: 512, height: max(1, (512 * aspect).rounded()))
        let renderer = ImageRenderer(
            content: AmbientGradientBackground.mesh(colors: colors)
                .frame(width: renderSize.width, height: renderSize.height)
        )
        renderer.scale = 1
        guard let image = renderer.uiImage else { return nil }
        cache.setObject(image, forKey: cacheKey)
        return image
    }
}
#endif
