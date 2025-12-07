//
//  SGFCoordinates.swift
//  SGFPlayerClean
//
//  Created: 2025-12-04
//  Purpose: The "Rosetta Stone" for converting between Grid Integers and SGF Strings.
//

import Foundation

struct SGFCoordinates {
    static let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

    /// Converts Grid Coordinate (0,0) to SGF String "aa"
    static func toSGF(x: Int, y: Int) -> String {
        guard x >= 0, x < alphabet.count, y >= 0, y < alphabet.count else { return "" }
        return "\(String(alphabet[x]))\(String(alphabet[y]))"
    }

    /// Converts SGF String "aa" to Grid Coordinate (0,0)
    static func fromSGF(_ sgf: String) -> (x: Int, y: Int)? {
        guard sgf.count >= 2 else { return nil }
        let xChar = sgf.first!
        let yChar = sgf.dropFirst().first!
        
        guard let x = alphabet.firstIndex(of: xChar),
              let y = alphabet.firstIndex(of: yChar) else { return nil }
        
        return (x, y)
    }
}
