//
//  StoneView2D.swift
//  SGFPlayerClean
//
//  Created: 2025-12-01
//  Purpose: Reusable textured stone view for 2D board and lids
//

import SwiftUI

struct StoneView2D: View {
    let color: Stone
    let position: BoardPosition // Used for texture seeding
    
    // Optional: seed override for when position isn't on the grid (e.g. lids)
    var seedOverride: Int? = nil
    
    var body: some View {
        Group {
            if color == .black {
                Image("stone_black")
                    .resizable()
            } else {
                // Use seed to pick a clam texture
                let seed = seedOverride ?? ((position.row * 19) + position.col)
                
                // FIX: You have clam_01 through clam_05.
                // Modulus 5 gives 0..4. Adding 1 gives 1..5.
                let variant = (seed % 5) + 1
                let textureName = String(format: "clam_%02d", variant)
                
                Image(textureName)
                    .resizable()
            }
        }
    }
}
