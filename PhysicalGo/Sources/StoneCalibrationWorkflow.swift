import AppKit
import SwiftUI

extension ExperimentModel {
    var canBeginStoneCalibration:Bool {
        stoneCalibrationSession==nil && liveBoardReady && hasReference && !onlineBoard.enabled &&
        (recorder.state == .idle || recorder.state == .finished) && !boardCorrections.isEditing
    }
    func beginStoneCalibration() {
        guard canBeginStoneCalibration,let referenceImage else {return}
        stoneCalibrationSession=StoneCalibrationSession(id:UUID(),size:size,quarterTurns:viewQuarterTurns,
            cameraID:cameraID,originalReference:referenceImage)
        stoneCalibrationError=""
        onlineBoard.pauseForCorrection()
    }
    func resumeStoneCalibration() {
        guard canBeginStoneCalibration,let folder=resumableStoneCalibrationFolder,
              let referenceImage,let calibration else {return}
        do {
            let saved=try StoneCalibrationArchive.load(folder:folder,reference:referenceImage,cameraID:cameraID,calibration:calibration,turns:viewQuarterTurns)
            stoneCalibrationSession=saved;stoneCalibrationFolder=folder;stoneCalibrationError=""
            if saved.stage==3 {stoneAppearanceProfile=StoneAppearanceModel(examples:saved.examples());stoneAppearanceProfileSession=saved}
            onlineBoard.pauseForCorrection()
        } catch {stoneCalibrationError=error.localizedDescription;message=error.localizedDescription}
    }
    var stoneCalibrationContextValid:Bool {
        guard let session=stoneCalibrationSession else {return false}
        return session.cameraID==cameraID && session.size==size && session.quarterTurns==viewQuarterTurns &&
            session.originalReference === referenceImage && !onlineBoard.enabled &&
            (recorder.state == .idle || recorder.state == .finished)
    }
    func captureStoneCalibrationPhoto() {
        guard !savingStoneCalibration,stoneCalibrationContextValid,liveBoardReady,
              var session=stoneCalibrationSession,session.stage<3,
              let image,let calibration,let observation else {
            stoneCalibrationError="Wait for a fresh aligned camera view. If the camera, board, or reference changed, cancel and start calibration again."
            return
        }
        // Camera pixels, geometry and raw readings come from the same analyzed frame.
        session.pending=StoneCalibrationPhoto(id:UUID(),capturedAt:Date(),image:image,calibration:calibration,
            readings:observation.readings,labels:session.labels,stage:session.stage)
        stoneCalibrationSession=session;stoneCalibrationError=""
    }
    func confirmStoneCalibrationPhoto() {
        guard !savingStoneCalibration,stoneCalibrationContextValid,
              var session=stoneCalibrationSession,let photo=session.pending else {return}
        savingStoneCalibration=true;stoneCalibrationError=""
        session.photos.append(photo);session.pending=nil
        let candidate=session
        let archiveRoot=stoneCalibrationArchiveRoot
        DispatchQueue.global(qos:.utility).async {
            let result=Result { () throws -> (URL,StoneAppearanceModel?) in
                let folder=try StoneCalibrationArchive.save(photo:photo,session:candidate,root:archiveRoot)
                let profile=candidate.stage==3 ? StoneAppearanceModel(examples:candidate.examples()) : nil
                if candidate.stage==3 {
                    guard let profile else {throw NSError(domain:"StoneCalibration",code:1,userInfo:[NSLocalizedDescriptionKey:"Not enough usable samples for all three appearances. The confirmed photos have been saved; cancel and repeat calibration with a clear view."])}
                    try StoneCalibrationArchive.saveProfile(profile,session:candidate,root:archiveRoot)
                }
                return (folder,profile)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else {return}
                self.savingStoneCalibration=false
                guard self.stoneCalibrationSession?.id==candidate.id else {return}
                switch result {
                case .success(let (folder,profile)):
                    self.stoneCalibrationFolder=folder
                    self.resumableStoneCalibrationFolder=candidate.stage<3 ? folder:nil
                    guard self.stoneCalibrationContextValid else {
                        self.stoneCalibrationError="The confirmed photo was saved, but the camera or reference changed. Cancel and restart calibration."
                        return
                    }
                    self.stoneCalibrationSession=candidate
                    if let profile {
                        self.stoneAppearanceProfile=profile
                        self.stoneAppearanceProfileSession=candidate
                    }
                case .failure(let error):self.stoneCalibrationError="Could not finish saving: \(error.localizedDescription). Your photo is still available to retry."
                }
            }
        }
    }
    func closeStoneCalibration() {
        guard !savingStoneCalibration else {return}
        stoneCalibrationSession=nil;stoneCalibrationError=""
        onlineBoard.pauseForCorrection()
    }
    var stoneAppearanceProfileIsCurrent:Bool {
        guard let session=stoneAppearanceProfileSession else {return false}
        return session.cameraID==cameraID && session.size==size && session.originalReference === referenceImage
    }
    func inspectStoneAppearance(at point:Int) -> (StoneAppearanceFeatures,StoneAppearanceModel.Prediction,StoneNeighborContext)? {
        guard stoneAppearanceProfileIsCurrent,liveBoardReady,
              let profile=stoneAppearanceProfile,let session=stoneAppearanceProfileSession,
              let first=session.photos.first,let image,let frame=GrayFrame(image:image),
              let reference=GrayFrame(image:first.image),let calibration,
              let features=StoneAppearanceFeatures.extract(frame:frame,reference:reference,calibration:calibration,
                  referenceCalibration:first.calibration,point:point) else {return nil}
        guard let original=StoneAppearanceFeatures.extract(frame:reference,reference:reference,
            calibration:first.calibration,referenceCalibration:first.calibration,point:point),
            abs(features.woodLevel-original.woodLevel)<=0.08 else {return nil}
        let context=observation.map{StoneNeighborContext.observed(point:point,observation:$0,manual:boardCorrections.values)} ?? .unknown
        return (features,profile.predict(features,context:context),context)
    }
}
