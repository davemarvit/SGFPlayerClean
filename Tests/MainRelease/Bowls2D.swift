import SwiftUI
@testable import SGF_Player_OGS_Review

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n",stderr); exit(1) }
}

@main struct Bowls2DCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled",forKey:"customKataGoPath")
        AppSettings.shared.isMuted=true; AppSettings.shared.folderURL=nil
        let app=AppModel()
        defer { app.ogsClient.disconnect(); KataGoEngine.shared.stop() }
        app.aiAnalysisEnabled=false; app.showRightPanel=false; app.viewMode = .view2D
        let game=SGFGame.from(tree:try SGFParser.parse(text:"(;SZ[9]AB[ba][ab][bc]AW[bb][ca][db][cc];B[cb];W[];B[ff];W[gg])"))
        let url=URL(fileURLWithPath:"/private/tmp/sgf-bowls-\(UUID()).sgf")
        try "(;SZ[9])".write(to:url,atomically:true,encoding:.utf8)
        defer { try? FileManager.default.removeItem(at:url) }
        app.selectGame(SGFGameWrapper(url:url,game:game))
        let player=app.boardVM!.engine
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1200,height:850),styleMask:[.titled],backing:.buffered,defer:false)
        let host=NSHostingView(rootView:ContentView2D().environmentObject(app))
        window.contentView=host; window.orderFront(nil)
        defer { window.orderOut(nil) }
        func settle() { RunLoop.main.run(until:Date().addingTimeInterval(0.15)) }
        // Isolate the bowl components from playback status banners that move the
        // whole board when a pass or ko message changes height.
        let supplyHost=NSHostingView(rootView:HStack(spacing:0) {
            PlayerSupplyBowlView(player:player,stoneColor:.white,size:200)
            PlayerSupplyBowlView(player:player,stoneColor:.black,size:200)
        })
        window.contentView=supplyHost; window.setContentSize(CGSize(width:400,height:200))
        func capture() -> (black: Data, white: Data) {
            settle(); supplyHost.layoutSubtreeIfNeeded()
            let bitmap=supplyHost.bitmapImageRepForCachingDisplay(in:supplyHost.bounds)!
            supplyHost.cacheDisplay(in:supplyHost.bounds,to:bitmap)
            let image=bitmap.cgImage!
            func crop(x:Int) -> Data {
                let rect=CGRect(x:x,y:0,width:image.width/2,height:image.height)
                return NSBitmapImageRep(cgImage:image.cropping(to:rect)!).representation(using:.png,properties:[:])!
            }
            return (crop(x:image.width/2),crop(x:0))
        }
        func check(_ black:Int,_ white:Int) {
            settle()
            let counts=GoEquipment3D.supplyCounts(for:player)
            require(counts.black==black && counts.white==white,"Shared remaining counts: \(black), \(white)")
        }
        player.seek(to:0); check(178,176); let initial=capture()
        player.seek(to:1); check(177,176); let captured=capture()
        require(captured.black != initial.black,"Playing black changes the actual lower-right bowl")
        require(captured.white == initial.white,"Captured white stones do not refill the upper-left bowl")
        require(player.capturesByBlack==1,"Fixture captures a stone without refilling its supply")
        player.seek(to:2); check(177,176); let passed=capture()
        require(passed.black==captured.black && passed.white==captured.white,"A pass leaves both visible bowl images unchanged")
        player.seek(to:4); check(176,175); let later=capture()
        require(later.black != initial.black && later.white != initial.white,"Both players deplete their visible bowls")
        player.seek(to:0); check(178,176); let rewound=capture()
        require(rewound.black==initial.black && rewound.white==initial.white,"Rewind restores the original visible piles")
        player.load(game:SGFGame()); check(181,180)
        // The app must bundle every possible fill state, including empty bowls.
        for (color,capacity) in [(Stone.black,181),(Stone.white,180)] {
            for count in 0...capacity {
                require(BowlImages2D.image(color:color,remaining:count) != nil,"Bundled bowl state \(color) \(count)")
            }
            let full=BowlImages2D.image(color:color,remaining:capacity)!
            let empty=BowlImages2D.image(color:color,remaining:0)!
            require(full.tiffRepresentation != empty.tiffRepresentation,"Supply depletion changes the image")
            let bitmap=NSBitmapImageRep(data:full.tiffRepresentation!)!
            require(bitmap.colorAt(x:0,y:0)!.alphaComponent==0,"Bowl edges are genuinely transparent")
        }
        window.contentView=host
        for size in [CGSize(width:1200,height:850),CGSize(width:800,height:1000)] {
            window.setContentSize(size); settle(); host.layoutSubtreeIfNeeded()
            let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
            host.cacheDisplay(in:host.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/private/tmp/sgf-bowls-2d-\(Int(size.width)).png"))
        }
        print("PASS: live 2D supply pixels and shared counts, moves, passes, captures, setup, rewind, new game, all 363 bundled transparent states, and wide/narrow placement")
    }
}
