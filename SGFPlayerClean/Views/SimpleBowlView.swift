//
//  SimpleBowlView.swift
//  SGFPlayerClean
//
//  Created: 2025-11-28
//  Purpose: Renders captured stone containers (Lids) in 2D
//

import SwiftUI

struct SimpleLidView: View {
    let stoneColor: Stone
    let stoneCount: Int
    let stoneSize: CGFloat
    let lidNumber: Int
    let lidSize: CGFloat
    
    var body: some View {
        ZStack {
            // Lid Texture
            Image(lidNumber == 1 ? "go_lid_1" : "go_lid_2")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: lidSize, height: lidSize)
                .shadow(color: .black.opacity(0.3), radius: 3, x: 2, y: 2)
            
            // Stones Pile
            if stoneCount > 0 {
                LidStonesPile(
                    color: stoneColor,
                    count: min(stoneCount, 25),
                    stoneSize: stoneSize, // FIX: Removed * 0.9 scaling so they match board size
                    lidSize: lidSize
                )
            }
            
            // Numbers Removed as requested
        }
        .frame(width: lidSize, height: lidSize)
    }
}

struct LidStonesPile: View {
    let color: Stone
    let count: Int
    let stoneSize: CGFloat
    let lidSize: CGFloat
    
    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let offset = getScatterOffset(index: index, radius: lidSize * 0.35)
                
                // Use the shared StoneView2D with a seed override
                StoneView2D(color: color, position: BoardPosition(0, 0), seedOverride: index * 7)
                    .frame(width: stoneSize, height: stoneSize)
                    .position(
                        x: (lidSize / 2) + offset.x,
                        y: (lidSize / 2) + offset.y
                    )
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
            }
        }
    }
    
    private func getScatterOffset(index: Int, radius: CGFloat) -> CGPoint {
        let angle = Double(index) * 2.4
        let dist = radius * sqrt(Double(index) / 25.0)
        return CGPoint(x: CGFloat(cos(angle) * dist), y: CGFloat(sin(angle) * dist))
    }
}
