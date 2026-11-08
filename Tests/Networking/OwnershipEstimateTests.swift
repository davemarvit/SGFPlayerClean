import XCTest
import CoreGraphics
@testable import SGFPlayerNetworking

final class OwnershipEstimateTests: XCTestCase {
    private func analysis(_ values: [Double], deviations: [Double]? = nil, visits: Int = 100) -> AIAnalysis {
        AIAnalysis(id: "fixture", isDuringSearch: false, turnNumber: 0, moveInfos: [],
            rootInfo: AIRootInfo(winrate: 0.5, scoreLead: 0, visits: visits),
            ownership: values, ownershipStdev: deviations)
    }

    func testOpposingOwnershipFadesWholeGroupsConsistentlyForEitherPlayer() {
        let a = BoardPosition(0, 0), b = BoardPosition(0, 1), white = BoardPosition(2, 2)
        let stones: [BoardPosition: Stone] = [a: .black, b: .black, white: .white]
        var values = Array(repeating: 0.0, count: 9)
        values[0] = -0.95; values[1] = -0.8; values[8] = 0.7
        let black = AILikelyDeadStones.strengths(analysis: analysis(values), stones: stones, size: 3, playerToMove: .black)
        let whitePerspective = AILikelyDeadStones.strengths(analysis: analysis(values.map { -$0 }), stones: stones, size: 3, playerToMove: .white)
        XCTAssertEqual(black, whitePerspective)
        XCTAssertEqual(black[a]!, 0.6, accuracy: 0.001)
        XCTAssertEqual(black[a], black[b], "One connected group has one estimate")
        XCTAssertEqual(black[white]!, 0.4, accuracy: 0.001)
        values[1] = 0.8
        let mixed = AILikelyDeadStones.strengths(analysis: analysis(values), stones: stones, size: 3, playerToMove: .black)
        XCTAssertNil(mixed[a], "An unsettled or mixed group must not be partially declared dead")
        XCTAssertNil(mixed[b])
    }

    func testNeutralLivingLowVisitAndDisputedPositionsAreNotMarkedDead() {
        let point = BoardPosition(1, 1), stones: [BoardPosition: Stone] = [point: .black]
        for value in [0.0, 0.9, -0.2] {
            let result = AILikelyDeadStones.strengths(analysis: analysis(Array(repeating: value, count: 9)), stones: stones, size: 3, playerToMove: .black)
            XCTAssertTrue(result.isEmpty, "Neutral/seki and weak estimates are not death")
        }
        let values = Array(repeating: -0.95, count: 9)
        XCTAssertTrue(AILikelyDeadStones.strengths(analysis: analysis(values, visits: 49), stones: stones, size: 3, playerToMove: .black).isEmpty)
        XCTAssertTrue(AILikelyDeadStones.strengths(analysis: analysis(values, deviations: Array(repeating: 0.8, count: 9)), stones: stones, size: 3, playerToMove: .black).isEmpty)
    }

    func testLikelyLossGetsSubtleWarningBeforeStrongDeathMark() throws {
        let point = BoardPosition(1, 1), stones: [BoardPosition: Stone] = [point: .black]
        var previous = 0.0
        for evidence in [0.21, 0.35, 0.5, 0.6, 0.8, 1.0] {
            let sample = analysis(Array(repeating: -evidence, count: 9))
            let strength = try XCTUnwrap(AILikelyDeadStones.strengths(
                analysis: sample, stones: stones, size: 3, playerToMove: .black)[point])
            XCTAssertGreaterThan(strength, previous)
            if evidence <= 0.5 { XCTAssertLessThanOrEqual(strength, 0.15) }
            previous = strength
        }
        XCTAssertEqual(previous, 1)
    }

    func testStrengthGrowsWithEvidenceAndRegionIncludesOccupiedIntersections() throws {
        let point = BoardPosition(1, 1), stones: [BoardPosition: Stone] = [point: .white]
        var previous = 0.0
        var previousOpacity: UInt8 = 0
        for value in [0.7, 0.85, 1.0] {
            let sample = analysis(Array(repeating: value, count: 9))
            let strength = AILikelyDeadStones.strengths(analysis: sample, stones: stones, size: 3, playerToMove: .black)[point]!
            XCTAssertGreaterThan(strength, previous); previous = strength
            let regions = AILikelyDeadStones.ownershipEstimates(analysis: sample, size: 3, playerToMove: .black)
            XCTAssertEqual(regions.count, 9)
            XCTAssertEqual(regions[point]?.color, .black, "Ownership is drawn under the likely-captured white stone too")
            let texture = try XCTUnwrap(AIOwnershipTexture.image(estimates: regions, size: 3))
            let data = try XCTUnwrap(texture.dataProvider?.data)
            let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
            let center = texture.width / 2
            let opacity = bytes[center * texture.bytesPerRow + center * 4 + 3]
            XCTAssertGreaterThan(opacity, previousOpacity, "Higher confidence makes territory less transparent")
            previousOpacity = opacity
        }
        XCTAssertEqual(previous, 1)
        let whiteRegions = AILikelyDeadStones.ownershipEstimates(analysis: analysis(Array(repeating: 1, count: 9)), size: 3, playerToMove: .white)
        XCTAssertTrue(whiteRegions.values.allSatisfy { $0.color == .white })
    }

    func testOwnershipRequiresStrongRegionalSupportRatherThanOneLivingStone() {
        let center = BoardPosition(1, 1)
        var values = Array(repeating: 0.5, count: 9)
        values[4] = 1
        XCTAssertTrue(AILikelyDeadStones.ownershipEstimates(analysis: analysis(values), size: 3, playerToMove: .black).isEmpty,
                      "An isolated stone's owned point must not paint territory")
        for value in [0.1, 0.5, 0.65, -0.65] {
            XCTAssertTrue(AILikelyDeadStones.ownershipEstimates(analysis: analysis(Array(repeating: value, count: 9)), size: 3, playerToMove: .black).isEmpty)
        }
        values = Array(repeating: 0.9, count: 9)
        XCTAssertTrue(AILikelyDeadStones.ownershipEstimates(analysis: analysis(values, deviations: Array(repeating: 0.3, count: 9)), size: 3, playerToMove: .black).isEmpty)
        let regions = AILikelyDeadStones.ownershipEstimates(analysis: analysis(values), size: 3, playerToMove: .black)
        XCTAssertEqual(regions.count, 9)
        XCTAssertEqual(regions[center]?.color, .black)
    }

    func testOwnershipTextureFeathersEdgesAndPreservesColorAndClearGaps() throws {
        var regions: [BoardPosition: AIOwnershipEstimate] = [:]
        for row in 0..<9 {
            for col in 0..<9 where col < 3 || col > 5 {
                regions[BoardPosition(row, col)] = AIOwnershipEstimate(color: col < 3 ? .black : .white, strength: 1)
            }
        }
        let texture = try XCTUnwrap(AIOwnershipTexture.image(estimates: regions, size: 9))
        let data = try XCTUnwrap(texture.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        func rgba(_ x: Int, _ y: Int) -> [UInt8] {
            let offset = y * texture.bytesPerRow + x * 4
            return (0..<4).map { bytes[offset + $0] }
        }
        let pitch = AIOwnershipTexture.pixelsPerCell
        let row = 4 * pitch + pitch / 2
        let black = rgba(pitch + pitch / 2, row), white = rgba(7 * pitch + pitch / 2, row)
        XCTAssertEqual(black[0], 0); XCTAssertEqual(white[0], white[3])
        XCTAssertEqual(black[3], white[3])
        XCTAssertGreaterThanOrEqual(black[3], 115, "Settled territory is clearly shaded")
        XCTAssertLessThanOrEqual(black[3], 140, "Board grain and grid remain visible")
        XCTAssertEqual(rgba(4 * pitch + pitch / 2, row)[3], 0, "Uncertain gap stays clear")
        let boundary = (2 * pitch + pitch / 2...3 * pitch + pitch / 2).map { rgba($0, row)[3] }
        XCTAssertGreaterThan(Set(boundary).count, 10, "Boundary has a gradual fade, not a tile edge")
        XCTAssertTrue(zip(boundary, boundary.dropFirst()).allSatisfy { $0 >= $1 })
        XCTAssertLessThan(rgba(0, row)[3], black[3], "Outer perimeter is feathered too")
        XCTAssertNil(AIOwnershipTexture.image(estimates: [:], size: 9))
    }

    func testMalformedMissingAndLegacyDataProduceNoOverlay() throws {
        let stones: [BoardPosition: Stone] = [BoardPosition(0, 0): .black]
        var samples: [AIAnalysis?] = [nil, analysis([]), analysis([1]),
            analysis(Array(repeating: .nan, count: 9)), analysis(Array(repeating: 2, count: 9)),
            analysis(Array(repeating: -1, count: 9), deviations: [0]),
            analysis(Array(repeating: -1, count: 9), deviations: Array(repeating: -0.1, count: 9))]
        let legacy = try JSONDecoder().decode(AIAnalysis.self, from: Data(#"{"id":"old","turnNumber":0,"rootInfo":{"winrate":0.5,"scoreLead":0,"visits":500}}"#.utf8))
        samples.append(legacy)
        for sample in samples {
            XCTAssertTrue(AILikelyDeadStones.strengths(analysis: sample, stones: stones, size: 3, playerToMove: .black).isEmpty)
            XCTAssertTrue(AILikelyDeadStones.ownershipEstimates(analysis: sample, size: 3, playerToMove: .black).isEmpty)
        }
        let original = analysis(Array(repeating: -0.9, count: 9), deviations: Array(repeating: 0.1, count: 9))
        let decoded = try JSONDecoder().decode(AIAnalysis.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.ownership, original.ownership)
        XCTAssertEqual(decoded.ownershipStdev, original.ownershipStdev)
    }
}
