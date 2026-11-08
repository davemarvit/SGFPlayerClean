import XCTest
import UIKit
final class TabletUITests: XCTestCase {
    @MainActor func testReviewToolsAndLibrary() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.otherElements["board2D"].waitForExistence(timeout: 15))
        app.otherElements["board2D"].tap()
        app.buttons["reviewMode"].tap()
        XCTAssertTrue(app.buttons["reviewPlayback"].waitForExistence(timeout: 5))
        app.buttons["Variations"].tap()
        XCTAssertTrue(app.buttons["Move 0"].exists)
        app.buttons["chooseGame"].tap()
        XCTAssertTrue(app.navigationBars["Game library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Import from Files…"].exists)
        app.buttons["Done"].tap()
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "iPad updated review tools"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    @MainActor func testCompactModesAndCollapsiblePanel() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let board = app.otherElements["board2D"]
        XCTAssertTrue(board.waitForExistence(timeout: 15))
        for id in ["onlineMode", "localMode", "observeMode", "reviewMode"] { XCTAssertTrue(app.buttons[id].isHittable) }
        XCTAssertEqual(app.buttons["localMode"].value as? String, "Selected")
        board.tap()
        app.buttons["reviewMode"].tap()
        XCTAssertEqual(app.buttons["reviewMode"].value as? String, "Selected")
        XCTAssertTrue(app.buttons["chooseGame"].isHittable)
        XCTAssertFalse(app.buttons["Pass"].exists)
        XCTAssertTrue(app.staticTexts["Move 1"].exists)
        app.buttons["Previous move"].tap()
        XCTAssertTrue(app.staticTexts["Move 0"].exists)
        app.buttons["Next move"].tap()
        app.buttons["localMode"].tap()
        XCTAssertTrue(app.buttons["Pass"].isHittable)
        let initialArea = board.frame.width * board.frame.height
        app.buttons["Hide controls"].tap()
        XCTAssertFalse(app.otherElements["gameSidebar"].exists)
        XCTAssertGreaterThan(board.frame.width * board.frame.height, initialArea * 1.15)
        XCTAssertTrue(app.buttons["localMode"].isHittable)
        var screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name = "iPad compact controls landscape expanded board"; screen.lifetime = .keepAlways; add(screen)
        app.buttons["Show controls"].tap()
        XCTAssertTrue(app.otherElements["gameSidebar"].exists)
        screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name = "iPad compact controls landscape panel"; screen.lifetime = .keepAlways; add(screen)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["localMode"].isHittable)
        XCTAssertLessThan(app.otherElements["compactControls"].frame.height, 70)
        XCTAssertTrue(app.staticTexts["Move 1"].exists)
        screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name = "iPad compact controls portrait"; screen.lifetime = .keepAlways; add(screen)
    }

    @MainActor func testVisibleEnvironmentMenu() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        app.buttons["toggle3D"].tap()
        let board = app.otherElements["board3D"]
        XCTAssertTrue(board.waitForExistence(timeout: 20))
        board.tap(); waitForCamera(board, moving: false)
        let menu = app.buttons["environmentMenu"]
        XCTAssertTrue(menu.isHittable)
        XCTAssertEqual(menu.value as? String, "Garden-view room")
        menu.tap(); app.buttons["Moon"].tap()
        waitForCamera(board, moving: true)
        board.tap(); waitForCamera(board, moving: false)
        XCTAssertEqual(menu.value as? String, "Moon")
        XCTAssertTrue(app.staticTexts["Move 0"].exists)
        let portrait = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        portrait.name = "iPad larger 3D board portrait"; portrait.lifetime = .keepAlways; add(portrait)
        XCUIDevice.shared.orientation = .landscapeLeft
        expectation(for: NSPredicate { _, _ in app.frame.width > app.frame.height }, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(menu.waitForExistence(timeout: 5)); XCTAssertTrue(menu.isHittable)
        XCTAssertTrue((board.value as? String ?? "").hasPrefix("seated"), "Rotation must not restart the camera tour")
        let sidebar = app.otherElements["gameSidebar"]
        XCTAssertGreaterThanOrEqual(board.frame.height, sidebar.frame.height - 1)
        let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscape.name = "iPad larger 3D board landscape"; landscape.lifetime = .keepAlways; add(landscape)
        app.buttons["Hide controls"].tap()
        XCTAssertTrue((board.value as? String ?? "").hasPrefix("seated"), "Collapsing controls must preserve the camera")
        XCTAssertTrue(menu.isHittable)
        let expanded = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        expanded.name = "iPad 3D with compact side controls"; expanded.lifetime = .keepAlways; add(expanded)
        menu.tap(); app.buttons["Garden-view room"].tap()
        waitForCamera(board, moving: true); board.tap(); waitForCamera(board, moving: false)
        XCTAssertEqual(menu.value as? String, "Garden-view room")
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor func testCameraTourCompletesAndTouchSkipsWithoutPlaying() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        app.buttons["toggle3D"].tap()
        let board = app.otherElements["board3D"]
        XCTAssertTrue(board.waitForExistence(timeout: 20))
        waitForCamera(board, moving: true)
        let opening = board.value as? String
        let movement = NSPredicate { _, _ in
            let pose = board.value as? String ?? ""
            return pose.hasPrefix("moving") && pose != opening
        }
        expectation(for: movement, evaluatedWith: nil); waitForExpectations(timeout: 6)
        let tour = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        tour.name = "iPad environment camera tour"; tour.lifetime = .keepAlways; add(tour)
        waitForCamera(board, moving: false, timeout: 16)
        XCTAssertTrue(app.staticTexts["Move 0"].exists)
        app.buttons["toggle3D"].tap(); app.buttons["toggle3D"].tap()
        waitForCamera(board, moving: true)
        // Touch-down skips immediately; holding then lifting must not place a stone.
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.60)).press(forDuration: 1.5)
        waitForCamera(board, moving: false)
        XCTAssertTrue(app.staticTexts["Move 0"].exists)
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.60)).tap()
        XCTAssertTrue(app.staticTexts["Move 1"].waitForExistence(timeout: 5))
        board.rotate(.pi / 4, withVelocity: 1)
        let orbited = board.value as? String
        app.buttons["Recenter board"].tap()
        waitForCamera(board, moving: false)
        XCTAssertNotEqual(board.value as? String, orbited)
        XCTAssertTrue(app.staticTexts["Move 1"].exists)
        app.buttons["Game menu"].tap(); app.buttons["Board settings"].tap()
        app.buttons["environmentPicker"].tap(); app.buttons["Moon"].tap()
        app.buttons["Done"].tap()
        waitForCamera(board, moving: true)
        let moon = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        moon.name = "iPad Moon arrival after settings"; moon.lifetime = .keepAlways; add(moon)
        board.tap()
        waitForCamera(board, moving: false)
        XCTAssertTrue(app.staticTexts["Move 1"].exists)
    }

    @MainActor private func waitForCamera(_ board: XCUIElement, moving: Bool, timeout: TimeInterval = 5) {
        let prefix = moving ? "moving" : "seated"
        let predicate = NSPredicate { _, _ in (board.value as? String ?? "").hasPrefix(prefix) }
        expectation(for: predicate, evaluatedWith: nil); waitForExpectations(timeout: timeout)
    }

    @MainActor func testBowlsCapturesAndRotation() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let board = app.otherElements["board2D"]
        XCTAssertTrue(board.waitForExistence(timeout: 20))
        let black = app.otherElements["black-supply-bowl"]
        let white = app.otherElements["white-supply-bowl"]
        let captures = app.otherElements["white-capture-lid"]
        XCTAssertTrue(black.exists); XCTAssertTrue(white.exists); XCTAssertTrue(captures.exists)
        XCTAssertLessThan(white.frame.maxY, board.frame.minY)
        XCTAssertGreaterThan(black.frame.minY, board.frame.maxY)
        func tap(_ row: Int, _ col: Int) {
            board.coordinate(withNormalizedOffset: CGVector(dx: 0.065 + Double(col) * 0.87 / 18,
                                                            dy: 0.065 + Double(row) * 0.87 / 18)).tap()
        }
        tap(0, 1); tap(0, 0); tap(1, 0)
        XCTAssertTrue(app.staticTexts["Move 3"].waitForExistence(timeout: 5))
        XCTAssertEqual(captures.value as? String, "1")
        app.buttons["Previous move"].tap()
        XCTAssertEqual(captures.value as? String, "0")
        app.buttons["Next move"].tap()
        XCTAssertEqual(captures.value as? String, "1")
        let portrait = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        portrait.name = "iPad bowls portrait"; portrait.lifetime = .keepAlways; add(portrait)
        app.buttons["Details"].tap()
        XCTAssertTrue(app.buttons["Score position"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Black captured 1 white stone"].exists)
        XCTAssertTrue(app.staticTexts["White captured 0 black stones"].exists)
        app.buttons["Done"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        let beside = NSPredicate { _, _ in white.frame.maxX < board.frame.minX && black.frame.minX > board.frame.maxX }
        expectation(for: beside, evaluatedWith: nil); waitForExpectations(timeout: 10)
        XCTAssertEqual(captures.value as? String, "1")
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Move 4"].waitForExistence(timeout: 5))
        let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscape.name = "iPad bowls landscape"; landscape.lifetime = .keepAlways; add(landscape)
        XCUIDevice.shared.orientation = .portrait
    }
    @MainActor func testTouchPlacementNavigationAnd3D() throws {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--ui-testing"];app.launch()
        let board=app.otherElements["board2D"]
        XCTAssertTrue(board.waitForExistence(timeout:20))
        board.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        XCTAssertFalse(app.buttons["placeStone"].exists)
        XCTAssertTrue(app.staticTexts["Move 1"].waitForExistence(timeout:5))
        app.buttons["Previous move"].tap()
        XCTAssertTrue(app.staticTexts["Move 0"].exists)
        app.buttons["Next move"].tap()
        XCTAssertTrue(app.staticTexts["Move 1"].exists)
        let tatami = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); tatami.name = "iPad 2D tatami"; tatami.lifetime = .keepAlways; add(tatami)
        app.buttons["toggle3D"].tap()
        XCTAssertTrue(app.buttons["Recenter board"].waitForExistence(timeout:30))
        let board3D=app.otherElements["board3D"]
        board3D.tap() // Skip the arrival; this touch must not play a stone.
        XCTAssertTrue(app.staticTexts["Move 1"].exists)
        board3D.coordinate(withNormalizedOffset:CGVector(dx:0.55,dy:0.60)).tap()
        XCTAssertTrue(app.staticTexts["Move 2"].waitForExistence(timeout:5))
        let initialCamera = board3D.value as? String
        XCTAssertNotNil(initialCamera)
        board3D.rotate(.pi / 4, withVelocity: 1)
        XCTAssertNotEqual(board3D.value as? String, initialCamera, "Two-finger rotation must move the camera")
        XCTAssertTrue(app.staticTexts["Move 2"].exists, "Camera gestures must not place stones")
        app.buttons["Recenter board"].tap()
        waitForCamera(board3D, moving: false)
        let recenteredCamera = board3D.value as? String
        board3D.pinch(withScale: 1.4, velocity: 1)
        XCTAssertNotEqual(board3D.value as? String, recenteredCamera, "Pinch must still zoom")
        XCTAssertTrue(app.staticTexts["Move 2"].exists)
        app.buttons["Recenter board"].tap()
        waitForCamera(board3D, moving: false)
        assertNoShaderFailure(in:app.screenshot().image)
        let portrait=XCTAttachment(screenshot:app.screenshot());portrait.name="iPad 3D portrait";portrait.lifetime = .keepAlways;add(portrait)
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        XCTAssertFalse(app.buttons["placeStone"].exists)
        assertNoShaderFailure(in:app.screenshot().image)
        let landscape=XCTAttachment(screenshot:app.screenshot());landscape.name="iPad 3D landscape";landscape.lifetime = .keepAlways;add(landscape)
        app.buttons["toggle3D"].tap()
        XCTAssertTrue(board.waitForExistence(timeout:5))
        XCUIDevice.shared.orientation = .portrait
    }
    @MainActor func testObserveEntryListAndReadOnlyBoard() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--online-ui-testing", "--observe-ui-testing"]
        app.launch()
        app.buttons["observeMode"].tap()
        XCTAssertFalse(app.segmentedControls["onlineBrowserMode"].exists)
        let username = app.textFields["Username"]
        XCTAssertTrue(username.waitForExistence(timeout: 10))
        username.tap(); username.typeText("test")
        let password = app.secureTextFields["Password"]
        password.tap(); password.typeText("fixture")
        app.buttons["Sign in"].tap()
        let row = app.buttons["observeGame_7001"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let list = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        list.name = "iPad Observe games list"; list.lifetime = .keepAlways; add(list)
        row.tap()
        XCTAssertTrue(app.staticTexts["Spectating"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["observeMode"].value as? String, "Selected")
        XCTAssertFalse(app.buttons["Pass"].exists)
        XCTAssertFalse(app.buttons["Resign"].exists)
        XCTAssertFalse(app.buttons["analyzePosition"].exists)
        app.otherElements["board2D"].tap()
        XCTAssertTrue(app.staticTexts["Move 0"].exists)
        func checkPlayers() {
            XCTAssertEqual(app.staticTexts["onlinePlayerBlack"].label, "Black: Observed black (3d)")
            XCTAssertEqual(app.staticTexts["onlinePlayerWhite"].label, "White: Test opponent (1d)")
            XCTAssertTrue(app.staticTexts["onlinePlayerBlack"].isHittable)
            XCTAssertTrue(app.staticTexts["onlinePlayerWhite"].isHittable)
        }
        checkPlayers()
        XCTAssertEqual(app.buttons.matching(identifier: "chooseGame").count, 1)
        XCTAssertFalse(app.buttons["Observe games"].exists)
        app.buttons["observeMode"].tap() // Reselecting the current mode does not reopen the browser.
        XCTAssertTrue(app.staticTexts["Spectating"].exists)
        var players = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        players.name = "iPad player ranks expanded panel"; players.lifetime = .keepAlways; add(players)
        app.buttons["Hide controls"].tap()
        checkPlayers()
        players = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        players.name = "iPad player ranks compact panel"; players.lifetime = .keepAlways; add(players)
        app.buttons["chooseGame"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(app.segmentedControls["onlineBrowserMode"].exists)
        app.buttons["Done"].tap()
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["observeMode"].isHittable)
        XCTAssertTrue(app.staticTexts["Spectating"].exists)
        checkPlayers()
        players = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        players.name = "iPad player ranks portrait"; players.lifetime = .keepAlways; add(players)
        app.buttons["localMode"].tap()
        XCTAssertTrue(app.buttons["Previous move"].waitForExistence(timeout: 5))
    }
    @MainActor func testOnlineLoginPlayChatAndReturnToLocal() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--online-ui-testing"]; app.launch()
        app.buttons["onlineMode"].tap()
        let username = app.textFields["Username"]
        XCTAssertTrue(username.waitForExistence(timeout: 10))
        username.tap(); username.typeText("test")
        let password = app.secureTextFields["Password"]; password.tap(); password.typeText("fixture")
        app.buttons["Sign in"].tap()
        let resume = app.buttons["resumeGame_7001"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10)); resume.tap()
        let status = app.staticTexts["Your turn"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["analyzePosition"].exists)
        let board = app.otherElements["board2D"]
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(app.buttons["placeStone"].exists)
        XCTAssertTrue(app.staticTexts["Opponent’s turn"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Move 1"].exists)
        app.buttons["Chat"].tap()
        let message = app.textFields["Message"]
        // A multiline SwiftUI field is exposed as a text view on some iPadOS versions.
        let editor = message.exists ? message : app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText("Hello from the iPad test")
        app.buttons["Send"].tap()
        XCTAssertTrue(app.staticTexts["Hello from the iPad test"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screen.name = "iPad OGS simulated game"; screen.lifetime = .keepAlways; add(screen)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["Opponent’s turn"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Move 1"].exists)
        app.buttons["localMode"].tap()
        XCTAssertTrue(app.buttons["Previous move"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Move 0"].exists)
        XCTAssertFalse(app.buttons["analyzePosition"].isEnabled)
        XCUIDevice.shared.orientation = .portrait
    }
    private func assertNoShaderFailure(in image:UIImage, file:StaticString=#filePath, line:UInt=#line) {
        guard let source=image.cgImage else {XCTFail("Missing screenshot",file:file,line:line);return}
        let width=source.width,height=source.height
        var pixels=[UInt8](repeating:0,count:width*height*4)
        pixels.withUnsafeMutableBytes { bytes in
            let context=CGContext(data:bytes.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(source,in:CGRect(x:0,y:0,width:width,height:height))
        }
        let magenta=stride(from:0,to:pixels.count,by:4).filter{pixels[$0]>240 && pixels[$0+1]<15 && pixels[$0+2]>240}.count
        XCTAssertLessThan(magenta,100,"SceneKit shader failure color in render",file:file,line:line)
    }
}
