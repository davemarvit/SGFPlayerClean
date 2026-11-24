import Foundation

/// Candidate data only. No field in this library grants recognition authority.
struct StoneSetProfile:Codable,Equatable,Identifiable {
    var schemaVersion=1
    var stoneSetID=UUID()
    var name:String
    var createdAt=Date()
    var updatedAt=Date()
    var black=StoneSetColorProfile()
    var white=StoneSetColorProfile()
    var id:UUID {stoneSetID}

    func validate() throws {
        guard schemaVersion == 1,!name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              name.count<=80,createdAt.timeIntervalSince1970.isFinite,updatedAt.timeIntervalSince1970.isFinite,
              updatedAt>=createdAt else {throw StoneSetProfileError.invalid("Check the stone-set name and dates.")}
        try black.validate();try white.validate()
    }
}
struct StoneSetColorProfile:Codable,Equatable {
    var physicalThicknessMm:StoneThicknessMeasurement?
    /// Preserve different grid/intrinsics hypotheses as distinct candidates.
    var opticalHeightCandidates:[StoneOpticalHeightCandidate]=[]
    func validate() throws {
        try physicalThicknessMm?.validate()
        guard opticalHeightCandidates.count<=100,
              Set(opticalHeightCandidates.map(\.candidateID)).count == opticalHeightCandidates.count else {
            throw StoneSetProfileError.invalid("Duplicate or excessive optical-height candidates.")
        }
        for candidate in opticalHeightCandidates {try candidate.validate()}
    }
}
struct StoneThicknessMeasurement:Codable,Equatable {
    var value:Double
    var uncertaintyMm:Double?
    var source="userMeasurement"
    var measuredAt=Date()
    func validate() throws {
        guard value.isFinite,value>0,source == "userMeasurement",measuredAt.timeIntervalSince1970.isFinite,
              uncertaintyMm.map({$0.isFinite && $0>=0 && $0<=value}) ?? true else {
            throw StoneSetProfileError.invalid("Measured thickness must be a positive number in millimetres.")
        }
    }
}
struct StoneOpticalHeightCandidate:Codable,Equatable,Identifiable {
    enum Units:String,Codable {case rowPitch,millimetres}
    struct Confidence:Codable,Equatable {
        var calibrationStatus="uncalibrated"
        var description:String
        var sampleCount:Int
    }
    struct Uncertainty:Codable,Equatable {
        enum Kind:String,Codable {case sensitivityRange,statisticalInterval,unknown}
        var kind:Kind
        var lower:Double?
        var upper:Double?
        var description:String
    }
    struct MetricConversion:Codable,Equatable {
        var rowPitchMm:Double
        var uncertaintyMm:Double?
        var source:String
    }
    struct Capture:Codable,Equatable {
        var captureID:String
        var imageSHA256:String
        var metadataSHA256:String
    }
    struct Compatibility:Codable,Equatable {
        enum IndependentValidation:String,Codable {case notPerformed,passed,failed}
        var description:String
        var independentSetupValidation:IndependentValidation = .notPerformed
        var validationReportID:String?
    }
    var candidateID=UUID()
    var status="offlineCandidate"
    var value:Double
    var units:Units
    var referenceBoardPitchID:String?
    var metricConversion:MetricConversion?
    var metricScaleSource:String?
    var measurementModelID:String
    var measurementModelVersion:String
    var setupModelID:String
    var geometryHypothesisID:String
    var geometryAssumptions:[String]
    var confidence:Confidence
    var uncertainty:Uncertainty
    var compatibility:Compatibility
    var heldOutReportID:String?
    var captures:[Capture]
    var sourceCodeSHA256:[String:String]
    var id:UUID {candidateID}

    /// A scale conversion stays an optical estimate, never measured thickness.
    var opticalMillimetres:Double? {
        switch units {
        case .millimetres:return value
        case .rowPitch:return metricConversion.map{value*$0.rowPitchMm}
        }
    }
    func validate() throws {
        func present(_ s:String?)->Bool {s.map{!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty} ?? false}
        func hash(_ s:String)->Bool {s.count == 64 && s.allSatisfy{"0123456789abcdefABCDEF".contains($0)}}
        guard status == "offlineCandidate",value.isFinite,value>0,
              present(measurementModelID),present(measurementModelVersion),present(setupModelID),present(geometryHypothesisID),
              !geometryAssumptions.isEmpty,geometryAssumptions.allSatisfy({present($0)}),
              confidence.calibrationStatus == "uncalibrated",present(confidence.description),confidence.sampleCount>=0,
              present(uncertainty.description),present(compatibility.description),!captures.isEmpty,
              captures.allSatisfy({present($0.captureID) && hash($0.imageSHA256) && hash($0.metadataSHA256)}),
              !sourceCodeSHA256.isEmpty,sourceCodeSHA256.allSatisfy({present($0.key) && hash($0.value)}) else {
            throw StoneSetProfileError.invalid("Optical estimate lacks its candidate status, assumptions or provenance.")
        }
        if units == .rowPitch && !present(referenceBoardPitchID) {
            throw StoneSetProfileError.invalid("A board-relative estimate needs the original board-spacing identity.")
        }
        if units == .millimetres && !present(metricScaleSource) {
            throw StoneSetProfileError.invalid("A metric optical estimate needs an explicit metric-scale source.")
        }
        if let conversion=metricConversion {
            guard units == .rowPitch,conversion.rowPitchMm.isFinite,conversion.rowPitchMm>0,present(conversion.source),
                  conversion.uncertaintyMm.map({$0.isFinite && $0>=0 && $0<conversion.rowPitchMm}) ?? true,
                  opticalMillimetres?.isFinite == true else {
                throw StoneSetProfileError.invalid("Metric conversion needs a measured board spacing and its source.")
            }
        }
        if uncertainty.kind == .unknown {
            guard uncertainty.lower == nil,uncertainty.upper == nil else {throw StoneSetProfileError.invalid("Unknown uncertainty cannot claim interval bounds.")}
        } else {
            guard let low=uncertainty.lower,let high=uncertainty.upper,low.isFinite,high.isFinite,
                  low>=0,low<=value,value<=high else {throw StoneSetProfileError.invalid("Invalid optical-estimate uncertainty interval.")}
        }
        if compatibility.independentSetupValidation != .notPerformed && !present(compatibility.validationReportID) {
            throw StoneSetProfileError.invalid("Independent validation needs a report reference.")
        }
    }
}
struct StoneSetLibrary:Codable,Equatable {
    var schemaVersion=1
    var selectedStoneSetID:UUID?
    var profiles:[StoneSetProfile]=[]
    func validate() throws {
        guard schemaVersion == 1,profiles.count<=1000,Set(profiles.map(\.stoneSetID)).count == profiles.count,
              selectedStoneSetID == nil || profiles.contains(where:{$0.id == selectedStoneSetID}) else {
            throw StoneSetProfileError.invalid("The saved stone-set library is invalid.")
        }
        let names=profiles.map{$0.name.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()}
        guard Set(names).count == names.count else {throw StoneSetProfileError.invalid("Choose a distinct name for each stone set.")}
        for profile in profiles {try profile.validate()}
    }
}
enum StoneSetProfileError:LocalizedError {
    case invalid(String)
    var errorDescription:String? {switch self {case .invalid(let detail):return detail}}
}
