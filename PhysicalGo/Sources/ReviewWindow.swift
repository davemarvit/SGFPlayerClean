import AppKit
import SwiftUI

/// An independent window lets players compare the review with the main board/feed.
@MainActor final class ReviewWindow: NSObject,ObservableObject,NSWindowDelegate {
    private(set) var window:NSWindow?
    private weak var recorder:GameRecorder?
    func open(recorder:GameRecorder,id:UUID,orientation:BoardOrientation,onCheckPhoto:(()->Void)?=nil) {
        // Keep unsubmitted selections intact if another review button is clicked.
        if let window {window.makeKeyAndOrderFront(nil);return}
        guard recorder.contextForReview(id) != nil else {return}
        self.recorder=recorder;recorder.activeReviewID=id
        recorder.pause();recorder.returnToLatest();recorder.clock.pause("Reviewing a section · clocks paused")
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:920,height:720),
                            styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="Review \(recorder.reviewHistory.sections.first{$0.id==id}?.reviewNumber ?? 0)"
        window.isReleasedWhenClosed=false;window.delegate=self
        window.contentMinSize=NSSize(width:890,height:690)
        window.contentView=NSHostingView(rootView:ReviewSectionView(recorder:recorder,id:id,orientation:orientation,onClose:{[weak self] in self?.close()},onCheckPhoto:onCheckPhoto.map {action in { [weak self] in self?.close();action() }}))
        self.window=window;window.center();window.makeKeyAndOrderFront(nil)
    }
    func close() {window?.close()}
    func windowWillClose(_ notification:Notification) {recorder?.activeReviewID=nil;recorder=nil;window?.contentView=nil;window=nil}
}
