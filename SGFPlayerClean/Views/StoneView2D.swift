//
//  StoneView2D.swift
//  SGFPlayerClean
//
//  Updated (v3.65):
//  - Safe Asset Loading for textures.
//  - Robust procedural fallback.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct StoneView2D: View {
    let color: Stone
    let position: BoardPosition
    var seedOverride: Int? = nil
    
    var body: some View {
        ZStack {
            // Shadow
            Circle()
                .fill(Color.black.opacity(0.3))
                .offset(x: 1, y: 1)
            
            // Texture Layer (If Asset Exists)
            // If asset exists, show it. If not, show nothing here.
            SafeStoneImage(name: color == .black ? "stone_black" : "stone_white")
            
            // Fallback Layer (Procedural)
            // We overlay this *under* the image logic, but since we can't easily stack "if missing",
            // we will just show the gradient. If the image exists (and is opaque), it covers it.
            // If the image is missing, this is visible.
            if !hasImage(named: color == .black ? "stone_black" : "stone_white") {
                if color == .black {
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [.white.opacity(0.3), .black]),
                                center: .topLeading,
                                startRadius: 1,
                                endRadius: 10
                            )
                        )
                } else {
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [.white, .init(white: 0.9)]),
                                center: .topLeading,
                                startRadius: 1,
                                endRadius: 20
                            )
                        )
                        .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
                }
            }
        }
    }
    
    private func hasImage(named: String) -> Bool {
        #if os(macOS)
        return NSImage(named: named) != nil
        #else
        return UIImage(named: named) != nil
        #endif
    }
    
    // Initializer
    init(color: Stone, position: BoardPosition = BoardPosition(0,0), seedOverride: Int? = nil) {
        self.color = color
        self.position = position
        self.seedOverride = seedOverride
    }
}

struct SafeStoneImage: View {
    let name: String
    var body: some View {
        if hasImage(named: name) {
            Image(name).resizable()
        } else {
            EmptyView()
        }
    }
    private func hasImage(named: String) -> Bool {
        #if os(macOS)
        return NSImage(named: named) != nil
        #else
        return UIImage(named: named) != nil
        #endif
    }
}
