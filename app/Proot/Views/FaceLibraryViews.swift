import SwiftUI

/// Prompt shown on the Faces tab when the visor doesn't have the ProtoFrenz faces yet.
struct FaceLibraryBanner: View {
    @Environment(DeviceStore.self) private var store

    var body: some View {
        if let s = store.state, !s.vendorFaces, s.facePack != true {
            HStack(spacing: 12) {
                Image(systemName: "face.dashed").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.importedFaces == nil ? "Get your ProtoFrenz faces" : "Send your faces to the visor").font(.subheadline.bold())
                    Text(store.importedFaces == nil
                         ? "All 52 eyes, 33 mouths and 24 noses from the original firmware."
                         : "They're on this phone but not on the visor yet.")
                        .font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
                FaceImportButton(compact: true)
            }
            .padding(14)
            .background(LinearGradient(colors: [Theme.violet.opacity(0.18), Theme.pink.opacity(0.18)], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.violet.opacity(0.35)))
            .padding(.top, 14)
        }
    }
}

struct FaceImportButton: View {
    @Environment(DeviceStore.self) private var store
    var compact = false

    var body: some View {
        Group {
            switch store.faceImport {
            case .downloading:
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Getting…") }
            case .sending(let p):
                HStack(spacing: 6) { ProgressView(value: p).frame(width: 50); Text("\(Int(p * 100))%") }
            default:
                Button(store.importedFaces == nil ? (compact ? "Get" : "Get ProtoFrenz faces") : (compact ? "Send" : "Send to visor")) {
                    Task {
                        if store.importedFaces == nil {
                            await store.importProtoFrenzFaces()
                        } else {
                            do { try await store.installFacePack() } catch { store.flash("Couldn't send faces: \(error.localizedDescription)") }
                        }
                    }
                }
                .buttonStyle(SmallButtonStyle())
            }
        }
        .font(.system(size: 13, weight: .semibold))
    }
}

/// Settings section: what's on the visor and on the phone, and the import controls.
struct FaceLibrarySection: View {
    @Environment(DeviceStore.self) private var store
    @State private var confirmForget = false

    var body: some View {
        if let s = store.state {
            SectionHeader(title: "Face library")
            RowGroup {
                Row {
                    Text("On the visor").frame(maxWidth: .infinity, alignment: .leading)
                    Text(s.facePack == true ? "ProtoFrenz (\(store.faces.eyes.count) eyes)" : s.vendorFaces ? "ProtoFrenz (built in)" : "Proot default")
                        .foregroundStyle(Theme.dim)
                }
                Row {
                    Text("On this phone").frame(maxWidth: .infinity, alignment: .leading)
                    if let f = store.importedFaces {
                        Text("\(f.eyes.count) eyes · \(f.mouths.count) mouths · \(f.noses.count) noses").font(.footnote).foregroundStyle(Theme.dim)
                    } else {
                        Text("Not imported").foregroundStyle(Theme.dim)
                    }
                }
                Row {
                    RowLabel(title: store.importedFaces == nil ? "Import ProtoFrenz faces" : "Install on visor",
                             subtitle: store.importedFaces == nil ? "Downloads the official firmware and extracts its presets on this phone"
                                                                  : "Your expressions keep their original preset numbers")
                    FaceImportButton()
                }
                if case .failed(let why) = store.faceImport {
                    Row { Text(why).font(.footnote).foregroundStyle(Theme.bad) }
                }
                if s.facePack == true {
                    Row {
                        RowLabel(title: "Use Proot's faces instead", subtitle: "Removes the pack from the visor")
                        Button("Remove") { store.removeFacePack() }.buttonStyle(SmallButtonStyle(danger: true))
                    }
                }
                if store.importedFaces != nil {
                    Row {
                        Text("Re-download").frame(maxWidth: .infinity, alignment: .leading)
                        Button("Refresh") { Task { await store.importProtoFrenzFaces() } }.buttonStyle(SmallButtonStyle())
                        Button { confirmForget = true } label: { Image(systemName: "trash") }.buttonStyle(SmallButtonStyle(danger: true))
                    }
                }
            }
            .confirmationDialog("Delete the ProtoFrenz faces from this phone?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Delete from phone", role: .destructive) { store.forgetImportedFaces() }
            } message: {
                Text("The visor keeps its copy.")
            }
        }
    }
}
