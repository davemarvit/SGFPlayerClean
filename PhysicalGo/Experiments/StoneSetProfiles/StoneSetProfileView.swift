import SwiftUI

/// Isolated UI candidate. The caller supplies a library; selection is descriptive
/// and has no connection to active vision, placement assignment or laser aiming.
struct StoneSetProfilePicker:View {
    @ObservedObject var store:StoneSetProfileStore
    @State private var editing:StoneSetProfile?
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Picker("Stone set",selection:Binding(get:{store.library.selectedStoneSetID},set:{store.select($0)})) {
                    Text("No set selected").tag(Optional<UUID>.none)
                    ForEach(store.library.profiles) {profile in Text(profile.name).tag(Optional(profile.id))}
                }
                Button("New set…") {editing=StoneSetProfile(name:"")}
                Button("Edit…") {editing=store.selected}.disabled(store.selected == nil)
            }
            Text(store.selected == nil ? "Choose or name your stones. You don't need to know their thickness.":"Saved for calibration. Selecting this set does not change current stone recognition.")
                .font(.caption).foregroundStyle(.secondary)
            if let selected=store.selected {
                HStack(alignment:.top,spacing:20) {
                    StoneSetColorSummary(title:"Black",profile:selected.black)
                    StoneSetColorSummary(title:"White",profile:selected.white)
                }
            }
            if let error=store.error {Text(error).font(.caption).foregroundStyle(.red)}
        }
        .sheet(item:$editing) {profile in
            StoneSetProfileEditor(store:store,profile:profile)
        }
    }
}

private struct StoneSetColorSummary:View {
    let title:String
    let profile:StoneSetColorProfile
    var body:some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.subheadline.bold())
            if let measured=profile.physicalThicknessMm {
                Text("Measured thickness: \(measured.value.formatted(.number.precision(.fractionLength(0...2)))) mm")
                    .font(.caption)
            } else {Text("Thickness unknown — that's okay").font(.caption).foregroundStyle(.secondary)}
            if profile.opticalHeightCandidates.isEmpty {
                Text("No camera estimate saved").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("\(profile.opticalHeightCandidates.count) camera estimate\(profile.opticalHeightCandidates.count == 1 ? "":"s") saved · needs validation")
                    .font(.caption).foregroundStyle(.orange)
                Text("Saved with its original board and camera setup; recheck with a different board or after moving the camera.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

private struct StoneSetProfileEditor:View {
    @ObservedObject var store:StoneSetProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft:StoneSetProfile
    @State private var blackThickness:String
    @State private var whiteThickness:String
    @State private var validationError:String?
    init(store:StoneSetProfileStore,profile:StoneSetProfile) {
        self.store=store
        _draft=State(initialValue:profile)
        _blackThickness=State(initialValue:profile.black.physicalThicknessMm.map{String($0.value)} ?? "")
        _whiteThickness=State(initialValue:profile.white.physicalThicknessMm.map{String($0.value)} ?? "")
    }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Stone set").font(.title2.bold())
            TextField("Name, for example Club glass stones",text:$draft.name)
            Text("Give this set a name so you can choose it again at the next setup. Thickness can stay unknown.")
                .font(.callout).foregroundStyle(.secondary)
            DisclosureGroup("Measured thickness (optional)") {
                VStack(alignment:.leading,spacing:8) {
                    thicknessField("Black",text:$blackThickness)
                    thicknessField("White",text:$whiteThickness)
                    Text("Enter measurements you know, in millimetres. Leave blank if unknown. Camera estimates are kept separately.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top,8)
            }
            HStack(alignment:.top,spacing:20) {
                StoneSetColorSummary(title:"Black",profile:draft.black)
                StoneSetColorSummary(title:"White",profile:draft.white)
            }
            if !draft.black.opticalHeightCandidates.isEmpty || !draft.white.opticalHeightCandidates.isEmpty {
                DisclosureGroup("Estimate details") {
                    ScrollView {
                        VStack(alignment:.leading,spacing:12) {
                            ForEach(draft.black.opticalHeightCandidates) {candidate in estimate(candidate,color:"Black")}
                            ForEach(draft.white.opticalHeightCandidates) {candidate in estimate(candidate,color:"White")}
                        }
                    }.frame(maxHeight:220)
                }
            }
            Text("This saves a profile for later calibration. It does not apply a camera estimate or change current recognition.")
                .font(.caption).foregroundStyle(.secondary)
            if let validationError {Text(validationError).font(.caption).foregroundStyle(.red)}
            if let error=store.error {Text(error).font(.caption).foregroundStyle(.red)}
            HStack {
                Spacer()
                Button("Cancel") {dismiss()}.keyboardShortcut(.cancelAction)
                Button("Save set") {save()}.keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width:560)
    }
    private func thicknessField(_ label:String,text:Binding<String>)->some View {
        HStack {
            Text(label).frame(width:50,alignment:.leading)
            TextField("Unknown",text:text).frame(width:110)
            Text("mm").foregroundStyle(.secondary)
            Button("Unknown") {text.wrappedValue=""}.disabled(text.wrappedValue.isEmpty)
        }
    }
    private func estimate(_ c:StoneOpticalHeightCandidate,color:String)->some View {
        VStack(alignment:.leading,spacing:4) {
            Text("\(color) camera estimate · unvalidated").font(.subheadline.bold())
            Text("Effective optical height: \(c.value.formatted()) \(c.units == .rowPitch ? "board row spacings":"mm")")
            if c.units == .rowPitch,let converted=c.opticalMillimetres,let conversion=c.metricConversion {
                Text("Converted optical estimate: \(converted.formatted()) mm, using \(conversion.rowPitchMm.formatted()) mm board spacing (\(conversion.source)).")
            }
            Text("This is the camera's observed surface height, not measured stone thickness.")
            Text(c.confidence.description)
            Text(c.uncertainty.description)
            Text(c.compatibility.description)
            Text("Geometry assumptions: \(c.geometryAssumptions.joined(separator:"; "))")
            Text("Measurement model: \(c.measurementModelID) \(c.measurementModelVersion)")
            Text("Setup: \(c.setupModelID); geometry hypothesis: \(c.geometryHypothesisID)")
            if let pitch=c.referenceBoardPitchID {Text("Original board spacing: \(pitch)")}
            if let report=c.heldOutReportID {Text("Held-out check report: \(report)")}
            Text("Independent setup validation: \(c.compatibility.independentSetupValidation.rawValue)")
            Text("Source captures: \(c.captures.map(\.captureID).joined(separator:", "))")
        }.font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
    }
    private func measurement(_ text:String,previous:StoneThicknessMeasurement?)throws->StoneThicknessMeasurement? {
        let value=text.trimmingCharacters(in:.whitespacesAndNewlines)
        if value.isEmpty {return nil}
        let separator=Locale.current.decimalSeparator ?? "."
        guard let number=Double(value.replacingOccurrences(of:separator,with:".")),number.isFinite,number>0 else {
            throw StoneSetProfileError.invalid("Enter a positive thickness in millimetres, or leave it blank.")
        }
        if previous?.value == number {return previous}
        return StoneThicknessMeasurement(value:number)
    }
    private func save() {
        do {
            var edited=draft
            edited.black.physicalThicknessMm=try measurement(blackThickness,previous:draft.black.physicalThicknessMm)
            edited.white.physicalThicknessMm=try measurement(whiteThickness,previous:draft.white.physicalThicknessMm)
            try edited.validate()
            if store.save(edited) {dismiss()}
        } catch {validationError=error.localizedDescription}
    }
}
