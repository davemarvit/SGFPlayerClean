import Foundation

/// Fit the board and both lids together, leaving room for the game caption.
struct SaverLayout {
    let board: CGRect
    let blackLid: CGRect
    let whiteLid: CGRect
    let caption: CGRect

    init(bounds: CGRect) {
        let width = max(1, min(bounds.width * 0.94 / 1.41,
                               max(1, bounds.height - 34) * 0.94 / 1.0773))
        let height = width * 1.0773
        board = CGRect(x: bounds.midX - width * 1.41 / 2,
                       y: bounds.midY - (height + 24) / 2, width: width, height: height)
        let diameter = width * 0.36
        blackLid = CGRect(x: board.maxX + width * 0.05, y: board.minY + width * 0.025,
                          width: diameter, height: diameter)
        whiteLid = CGRect(x: blackLid.minX, y: board.maxY - diameter - width * 0.025,
                          width: diameter, height: diameter)
        caption = CGRect(x: bounds.minX + bounds.width * 0.03, y: board.maxY + 7,
                         width: bounds.width * 0.94, height: 20)
    }
}
