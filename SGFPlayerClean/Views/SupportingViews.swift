// MARK: - File: SupportingViews.swift (v8.100)
import SwiftUI

struct TatamiBackground: View {
    let boardHeight: CGFloat
    var body: some View {
        let scale = max(0.1, boardHeight / 800.0)
        #if os(macOS)
        let img = NSImage(named: "tatami.jpg") ?? NSImage(named: "tatami")
        #else
        let img = UIImage(named: "tatami.jpg") ?? UIImage(named: "tatami")
        #endif
        return ZStack {
            Color(red: 0.88, green: 0.84, blue: 0.68)
            if let actual = img {
                #if os(macOS)
                Rectangle().fill(ImagePaint(image: Image(nsImage: actual), scale: scale))
                #else
                Rectangle().fill(ImagePaint(image: Image(uiImage: actual), scale: scale))
                #endif
            }
        }.ignoresSafeArea()
    }
}

struct SafeImage: View {
    let name: String; let resizingMode: Image.ResizingMode
    var body: some View {
        #if os(macOS)
        if let img = NSImage(named: name) ?? NSImage(named: (name as NSString).deletingPathExtension) {
            Image(nsImage: img).resizable(resizingMode: resizingMode).interpolation(.high)
        } else { Color.white.opacity(0.05) }
        #else
        if let img = UIImage(named: name) {
            Image(uiImage: img).resizable(resizingMode: resizingMode).interpolation(.high)
        } else { Color.clear }
        #endif
    }
}

struct BoardGridShape: Shape {
    let boardSize: Int
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let stepX = rect.width / CGFloat(boardSize - 1), stepY = rect.height / CGFloat(boardSize - 1)
        for i in 0..<boardSize {
            let x = CGFloat(i) * stepX; path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: rect.height))
            let y = CGFloat(i) * stepY; path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return path
    }
}

struct FrostedGlass: ViewModifier {
    @ObservedObject var settings = AppSettings.shared
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial.opacity(settings.panelDiffusiveness))
            .background(Color(red: 0.05, green: 0.1, blue: 0.1).opacity(settings.panelOpacity))
            .cornerRadius(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))
    }
}
extension View { func frostedGlassStyle() -> some View { modifier(FrostedGlass()) } }

struct StatRow: View {
    let label: String; let icon: String; let value: String; var isMonospaced: Bool = false
    var body: some View {
        HStack {
            Label(label, systemImage: icon).font(.caption)
            Spacer()
            Text(value).font(isMonospaced ? .system(.caption, design: .monospaced) : .caption)
        }.foregroundColor(.white.opacity(0.9))
    }
}
