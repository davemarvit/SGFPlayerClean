//
//  LayoutViewModel.swift
//  SGFPlayerClean
//
//  Created: 2025-11-19
//  Purpose: Manages geometric calculations for the 2D board layout
//

import SwiftUI
import Combine

class LayoutViewModel: ObservableObject {
    
    // MARK: - Published State
    
    /// The exact screen frame of the board image
    @Published var boardFrame: CGRect = .zero
    
    /// The center point of the board
    @Published var boardCenter: CGPoint = .zero
    
    /// The total window size
    @Published var windowSize: CGSize = .zero
    
    // MARK: - Internal Metrics
    
    private var cellWidth: CGFloat = 0
    private var cellHeight: CGFloat = 0
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Layout Logic
    
    /// Updates the layout state based on the calculated frame from the View
    /// Called by ContentView2D when it determines where the board sits
    func updateBoardFrame(_ frame: CGRect, boardSize: Int) {
        self.boardFrame = frame
        self.boardCenter = CGPoint(x: frame.midX, y: frame.midY)
        
        // Recalculate cell metrics based on the visual frame
        // Logic: Board width / (lines + 1) to account for margins
        let divisor = CGFloat(boardSize + 1)
        
        if divisor > 0 {
            self.cellWidth = frame.width / divisor
            self.cellHeight = frame.height / divisor
        }
        
        // Notify observers that layout has changed
        self.objectWillChange.send()
    }
    
    /// Initial calculation logic (legacy/fallback)
    /// Used if the view hasn't explicitly set the frame yet
    func calculateLayout(containerSize: CGSize, boardSize: Int, leftPanelWidth: CGFloat) {
        self.windowSize = containerSize
        
        // Default aspect ratio for Go board (slightly non-square)
        let boardAspect: CGFloat = 1.0 / 1.0773
        
        let availableW = leftPanelWidth
        let availableH = containerSize.height
        
        var w: CGFloat = 0
        var h: CGFloat = 0
        
        if availableW / availableH < boardAspect {
            w = availableW * 0.9 // 90% fill
            h = w / boardAspect
        } else {
            h = availableH * 0.9 // 90% fill
            w = h * boardAspect
        }
        
        // Center in left panel
        let x = (leftPanelWidth - w) / 2
        let y = (availableH - h) / 2
        
        let frame = CGRect(x: x, y: y, width: w, height: h)
        updateBoardFrame(frame, boardSize: boardSize)
    }
    
    func handleResize(newSize: CGSize, boardSize: Int, leftPanelWidth: CGFloat) {
        calculateLayout(containerSize: newSize, boardSize: boardSize, leftPanelWidth: leftPanelWidth)
    }
    
    // MARK: - Getters for Subviews
    
    func getCellWidth(boardSize: Int) -> CGFloat {
        if cellWidth > 0 { return cellWidth }
        // Fallback if frame isn't set yet
        return (boardFrame.width > 0 ? boardFrame.width : 500) / CGFloat(boardSize + 1)
    }
    
    func getCellHeight(boardSize: Int) -> CGFloat {
        if cellHeight > 0 { return cellHeight }
        return (boardFrame.height > 0 ? boardFrame.height : 500) / CGFloat(boardSize + 1)
    }
    
    func getLidDiameter(boardSize: Int) -> CGFloat {
        // Requested: Diameter approx 1/3 of the board height
        if boardFrame.height > 0 {
            return boardFrame.height / 3.0
        }
        return 150.0 // Fallback
    }
    
    func getWhiteStoneSize(boardSize: Int) -> CGFloat {
        return getCellWidth(boardSize: boardSize) * 0.95
    }
    
    func getBlackStoneSize(boardSize: Int) -> CGFloat {
        // Black stones are traditionally slightly larger (optical illusion correction)
        return getCellWidth(boardSize: boardSize) * 0.97
    }
}
