import SwiftUI
import MacDroidCore

struct ConnectionView: View {
    let state: ConnectionState
    @ObservedObject var usb: USBMonitor
    let refresh: () -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ConnectionIllustration().frame(height: 175).padding(.top, 25)
                VStack(spacing: 11) {
                    HStack(spacing: 7) {
                        Circle().fill(state == .waiting ? Color.orange : Palette.accent).frame(width: 6, height: 6)
                        Text(state.label.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.5)
                    }.foregroundStyle(.secondary)
                    Text("Good memories. Easy transfers.").font(.system(size: 28, weight: .semibold, design: .rounded)).tracking(-0.7)
                    Text("Bring your favorites from Android to Mac,\nwith a cable and a couple of clicks.")
                        .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(5).multilineTextAlignment(.center)
                }
                if case .problem(let message) = state {
                    Label(message, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).frame(maxWidth: 480)
                }
                if let message = usb.accessoryMessage {
                    Label(message, systemImage: "cable.connector.slash")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                        .padding(16).frame(maxWidth: 590).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                if state == .opening || state == .scanning { ProgressView().controlSize(.small) }
                HStack(alignment: .top, spacing: 14) {
                    SetupStep(number: "01", title: "Plug in your phone", detail: "Use a USB data cable.\nKeep your phone unlocked.", icon: "cable.connector")
                    SetupStep(number: "02", title: "Choose photo transfer", detail: "Tap the USB notification.\nChoose Photo transfer / PTP.", icon: "photo.on.rectangle")
                    SetupStep(number: "03", title: "Make yourself at home", detail: "Select your photos.\nChoose a folder. Start copying.", icon: "arrow.down.to.line")
                }.padding(.top, 8)
                Button("Check connection again", action: refresh).buttonStyle(.borderless).font(.system(size: 12)).padding(.bottom, 24)
            }.padding(.horizontal, 34).frame(maxWidth: .infinity)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SetupStep: View {
    let number: String
    let title: String
    let detail: String
    let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon).font(.system(size: 17, weight: .light)).foregroundStyle(Palette.accent)
                Spacer()
                Text(number).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.tertiary)
            }
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 130, alignment: .top)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.border, lineWidth: 1))
    }
}

struct ConnectionIllustration: View {
    var body: some View {
        ZStack {
            Ellipse().fill(Palette.mint.opacity(0.5)).frame(width: 300, height: 140).rotationEffect(.degrees(-10))
            HStack(spacing: 28) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Palette.card).frame(width: 78, height: 135)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.accent.opacity(0.65), lineWidth: 2))
                    VStack(spacing: 14) {
                        Capsule().fill(Palette.accent.opacity(0.4)).frame(width: 20, height: 3)
                        ZStack {
                            RoundedRectangle(cornerRadius: 8).fill(Palette.mint).frame(width: 54, height: 66)
                            Image(systemName: "photo").font(.system(size: 24, weight: .ultraLight)).foregroundStyle(Palette.accent)
                        }
                        Capsule().fill(Palette.accent.opacity(0.4)).frame(width: 20, height: 3)
                    }
                }.rotationEffect(.degrees(-9)).offset(y: -5)
                Image(systemName: "arrow.right").font(.system(size: 19, weight: .light)).foregroundStyle(Palette.accent)
                VStack(spacing: 0) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9).fill(Palette.card).frame(width: 140, height: 94)
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.accent.opacity(0.65), lineWidth: 2))
                        RoundedRectangle(cornerRadius: 5).fill(Palette.mint.opacity(0.7)).frame(width: 122, height: 76)
                        Image(systemName: "folder").font(.system(size: 29, weight: .ultraLight)).foregroundStyle(Palette.accent)
                    }
                    Capsule().fill(Palette.accent.opacity(0.6)).frame(width: 157, height: 4).padding(.top, 4)
                }.rotationEffect(.degrees(5)).offset(y: 12)
            }
        }.accessibilityHidden(true)
    }
}

struct ConnectionGuide: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 21) {
            HStack {
                Text("Connect your OxygenOS phone").font(.title2.weight(.semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
            Text("For photos and videos").font(.headline)
            Text("1. Connect your phone directly to the Mac with a USB data cable.\n\n2. Unlock the phone and open its notification shade. Tap the USB / charging notification.\n\n3. Choose Photo transfer or PTP. If asked, allow access on the phone and approve the accessory on your Mac.\n\n4. Keep the phone unlocked while DroidDock reads its library.")
                .font(.system(size: 13)).lineSpacing(4)
            Divider()
            Text("If the phone doesn’t appear").font(.headline)
            Text("Unplug and reconnect after choosing the mode. Try another data cable or USB port. Close Image Capture, Photos, Android File Transfer, or any other app using the phone. A charging-only cable cannot transfer files.")
                .font(.callout).foregroundStyle(.secondary).lineSpacing(4)
            Text("For all file types, select All files in DroidDock and choose File transfer / Android Auto on the phone. Open a folder, then use Copy to Mac or Send to phone. Folder contents are browsed one level at a time.")
                .font(.callout).foregroundStyle(.secondary).lineSpacing(4)
            Text("Photo transfer exposes only the folders Android shares through PTP, usually DCIM and Pictures. Files stored only in the cloud or in private app storage are not exposed over USB.")
                .font(.caption).foregroundStyle(.secondary).lineSpacing(3)
            HStack { Spacer(); Button("Got it") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(30).frame(width: 530)
    }
}

struct PreviewView: View {
    let item: MediaItem
    let image: NSImage?
    let selected: Bool
    let toggle: () -> Void
    let close: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            HStack { Text(item.name).font(.headline); Spacer(); Button("Done", action: close).keyboardShortcut(.cancelAction) }
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Palette.subtle)
                if let image { Image(nsImage: image).resizable().scaledToFit().padding(10) }
                else { Label("No preview available", systemImage: "photo").foregroundStyle(.secondary) }
            }.frame(height: 380)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.album).font(.callout)
                    Text("\(byteString(item.byteCount)) · \(item.date?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown date")").font(.caption).foregroundStyle(.secondary)
                    Text("Phone thumbnail · copies use the original file").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Button(selected ? "Deselect" : "Select to copy") { toggle(); close() }.buttonStyle(.borderedProminent)
            }
        }.padding(25).frame(width: 660)
    }
}

struct HistoryView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Group {
            if model.history.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(.secondary)
                    Text("Every transfer, right here.").font(.title3.weight(.medium))
                    Text("Your completed copies will appear here with a shortcut to their folder.").font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(model.history) { record in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: record.failures.isEmpty ? "checkmark.circle" : "exclamationmark.triangle").font(.title2).foregroundStyle(Palette.accent)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(record.files.count) files copied from \(record.deviceName)").font(.system(size: 13, weight: .semibold))
                                        Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Show in Finder") { model.reveal(record.destination) }
                                }
                                Text(record.destination).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                if record.stopped { Text("Stopped after the current file. Completed copies were kept.").font(.caption).foregroundStyle(.secondary) }
                                if !record.failures.isEmpty {
                                    DisclosureGroup("\(record.failures.count) files could not be copied") {
                                        ForEach(Array(record.failures.enumerated()), id: \.offset) { _, failure in
                                            Text(failure).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5).textSelection(.enabled)
                                        }
                                    }.font(.caption)
                                }
                            }.padding(20).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border))
                        }
                    }.padding(30)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
