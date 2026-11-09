import SwiftUI

/// Review editors belong to the main window. Saving returns to its status area.
@MainActor final class ReviewPresentation: ObservableObject {
    struct Session:Identifiable {
        let id:UUID
        let recorder:GameRecorder
        let orientation:BoardOrientation
        let onCheckPhoto:(()->Void)?
    }
    @Published private(set) var session:Session?
    private var afterDismiss:(()->Void)?
    func open(recorder:GameRecorder,id:UUID,orientation:BoardOrientation,onCheckPhoto:(()->Void)?=nil) {
        // Do not discard an unfinished selection when another review is selected.
        guard session==nil,recorder.contextForReview(id) != nil else {return}
        recorder.activeReviewID=id
        recorder.pause();recorder.returnToLatest();recorder.clock.pause("Reviewing a section · clocks paused")
        session=Session(id:id,recorder:recorder,orientation:orientation,onCheckPhoto:onCheckPhoto)
    }
    func close() {
        session?.recorder.activeReviewID=nil
        session=nil
    }
    func checkPhoto() {
        afterDismiss=session?.onCheckPhoto
        close()
    }
    func didDismiss() {
        let action=afterDismiss;afterDismiss=nil
        close();action?()
    }
}
