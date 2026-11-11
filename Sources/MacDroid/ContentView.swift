import SwiftUI
import MacDroidCore

enum Palette {
    static let brand = Color(red: 0.12, green: 0.39, blue: 0.32)
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.52, green: 0.80, blue: 0.65, alpha: 1)
            : NSColor(srgbRed: 0.12, green: 0.39, blue: 0.32, alpha: 1)
    })
    static let mint = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.17, green: 0.28, blue: 0.23, alpha: 1)
            : NSColor(srgbRed: 0.87, green: 0.94, blue: 0.88, alpha: 1)
    })
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let subtle = Color.primary.opacity(0.055)
    static let border = Color.primary.opacity(0.09)
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var camera: CameraStore

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Palette.border).frame(width: 1)
            VStack(spacing: 0) {
                header
                Divider()
                if model.filter == .files { FileBrowserView(store: model.mtp, model: model) }
                else if model.filter == .history { HistoryView(model: model) }
                else if camera.items.isEmpty && camera.state != .ready {
                    ConnectionView(state: camera.state, usb: model.usb, refresh: camera.refresh)
                } else { library }
                if model.filter != .files && model.filter != .history {
                    if model.lastResult != nil && !model.isImporting { resultBanner }
                    Divider()
                    transferBar
                }
            }
            .background(Palette.canvas)
        }
        .background(Palette.canvas)
        .sheet(isPresented: $model.showGuide) { ConnectionGuide() }
        .sheet(item: $model.preview) { item in
            PreviewView(item: item, image: camera.thumbnails[item.id], selected: model.selection.contains(item.id),
                        toggle: { model.toggle(item) }, close: { model.preview = nil })
        }
        .alert("DroidDock", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .onChange(of: camera.activeDeviceID) { _, _ in model.connectionChanged() }
        .onChange(of: camera.items) { _, items in model.selection.formIntersection(Set(items.map(\.id))) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(Palette.brand).frame(width: 38, height: 38)
                    Image(systemName: "arrow.down.forward.and.arrow.up.backward").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("DroidDock").font(.system(size: 19, weight: .bold, design: .rounded))
                    Text("A little closer to home.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding(.top, 46).padding(.bottom, 31).padding(.horizontal, 22)

            sectionLabel("DEVICE")
            HStack(spacing: 12) {
                Image(systemName: "smartphone").font(.system(size: 28, weight: .light)).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.usingFileConnection ? model.mtp.deviceName : camera.deviceName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill((model.usingFileConnection ? model.mtp.connected : camera.state == .ready) ? Color.green : Color.orange).frame(width: 5, height: 5)
                        Text(camera.isDemo ? "Sample library" : model.usingFileConnection ? (model.mtp.connected ? "USB file transfer" : "Connect over USB") : camera.state == .ready ? "USB photo transfer" : "Photo transfer / PTP")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.subtle, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 16).padding(.bottom, 25)
            if camera.devices.count > 1 {
                Picker("Phone", selection: Binding(get: { camera.activeDeviceID ?? "" }, set: { camera.selectDevice($0) })) {
                    ForEach(camera.devices, id: \.uuidString) { device in Text(device.name ?? "Camera").tag(camera.deviceID(device)) }
                }.labelsHidden().padding(.horizontal, 16).padding(.bottom, 16).disabled(model.isImporting)
            }
            sectionLabel("USB FILE TRANSFER")
            navRow("All files", icon: "externaldrive", filter: .files, count: nil)
            navRow("Transfer history", icon: "clock.arrow.circlepath", filter: .history, count: nil)
            sectionLabel("PHOTO MODE · PTP").padding(.top, 25)
            navRow("Photo library", icon: "square.grid.2x2", filter: .all, count: camera.items.count)
            if !camera.items.isEmpty {
                navRow("Photos", icon: "photo", filter: .photos, count: camera.items.filter { $0.kind == .photo }.count)
                navRow("Videos", icon: "video", filter: .videos, count: camera.items.filter { $0.kind == .video }.count)
            }
            if !model.albums.isEmpty {
                sectionLabel("ON YOUR PHONE").padding(.top, 25)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.albums, id: \.self) { album in
                            navRow(album.components(separatedBy: " / ").last ?? album, icon: "folder", filter: .album(album), count: nil)
                                .help(album)
                        }
                    }
                }
            }
            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 9) {
                Label("Just your phone and Mac.", systemImage: "cable.connector").font(.system(size: 11, weight: .medium))
                Text("Full-quality copies.\nYour originals stay on your phone.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.subtle, in: RoundedRectangle(cornerRadius: 12)).padding(16)
            Button { model.showGuide = true } label: {
                Label("Connection help", systemImage: "questionmark.circle").font(.system(size: 12))
            }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 22)
        }
        .frame(width: 236)
        .background(Palette.card.opacity(0.45))
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary)
            .padding(.horizontal, 24).padding(.bottom, 10)
    }

    private func navRow(_ title: String, icon: String, filter: LibraryFilter, count: Int?) -> some View {
        Button { model.navigate(filter) } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 14)).frame(width: 18)
                Text(title).font(.system(size: 12, weight: model.filter == filter ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 2)
                if let count { Text(count == 0 ? "–" : count.formatted()).font(.system(size: 10, weight: .medium)).monospacedDigit().opacity(0.7) }
            }
            .foregroundStyle(model.filter == filter ? Palette.accent : Color.primary.opacity(0.75))
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(model.filter == filter ? Palette.mint : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 3)
            .disabled(model.isImporting || model.mtp.busy || model.switchingMode || (camera.isDemo && filter == .files))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(camera.isDemo ? "DEMO · SAMPLE ARTWORK" : "PHONE → MAC").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(Palette.accent)
                Text(model.filter == .files || model.filter == .history ? model.filter.title : camera.items.isEmpty && camera.state != .ready ? "Make room for more memories." : model.filter.title)
                    .font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-0.6)
            }
            Spacer(minLength: 6)
            if !camera.items.isEmpty && model.filter != .history && model.filter != .files {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search your photos", text: $model.search).textFieldStyle(.plain).font(.system(size: 12))
                    if !model.search.isEmpty {
                        Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                    }
                }.padding(10).frame(width: 190).background(Palette.subtle, in: RoundedRectangle(cornerRadius: 9))
            }
            Button {
                if model.filter == .files { Task { await model.mtp.connect() } } else { camera.refresh() }
            } label: { Image(systemName: "arrow.clockwise").frame(width: 18, height: 18) }
                .buttonStyle(.borderless).help("Refresh phone connection").disabled(model.isImporting || model.mtp.busy || camera.isDemo)
        }
        .padding(.horizontal, 30).padding(.top, 35).padding(.bottom, 24)
    }

    private var library: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(model.visibleItems.count.formatted()) items").font(.system(size: 12)).foregroundStyle(.secondary)
                if camera.state == .scanning { ProgressView().controlSize(.small); Text("Reading library…").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Select all") { model.selectAll() }.buttonStyle(.borderless).disabled(model.isImporting || model.visibleItems.isEmpty)
                if !model.selection.isEmpty {
                    Button("Clear selection") { model.selection = [] }.buttonStyle(.borderless).disabled(model.isImporting)
                }
                Divider().frame(height: 15).padding(.horizontal, 6)
                Picker("Sort", selection: $model.sort) { ForEach(SortOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .labelsHidden().frame(width: 130)
            }.padding(.horizontal, 30).padding(.vertical, 17)
            if case .problem(let message) = camera.state {
                Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).padding(.horizontal, 30).padding(.bottom, 12)
            }
            if model.visibleItems.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(.secondary)
                    Text(model.search.isEmpty ? "No photos in this view" : "No matching photos").font(.title3.weight(.medium))
                    Text(model.search.isEmpty ? "PTP shows the photos and videos your phone shares. Check DCIM or Pictures on your phone, then reconnect." : "Try another filename or choose a different folder.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 390)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 155, maximum: 240), spacing: 17)], spacing: 22) {
                        ForEach(model.visibleItems) { item in
                            PhotoCard(item: item, thumbnail: camera.thumbnails[item.id], selected: model.selection.contains(item.id), imported: model.imported.contains(item.id),
                                      select: { model.toggle(item) }, preview: { model.preview = item })
                                .onAppear { camera.requestThumbnail(for: item) }
                                .disabled(model.isImporting)
                        }
                    }.padding(.horizontal, 30).padding(.top, 3).padding(.bottom, 26)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultBanner: some View {
        Group {
            if let result = model.lastResult {
                HStack(spacing: 10) {
                    Image(systemName: result.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(result.failures.isEmpty ? Palette.accent : .orange)
                    Text("\(result.files.count) \(result.files.count == 1 ? "file" : "files") copied\(result.stopped ? " · Transfer stopped" : "")\(result.failures.isEmpty ? "" : " · \(result.failures.count) failed")")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    if !result.failures.isEmpty { Button("Details") { model.filter = .history }.buttonStyle(.borderless) }
                    Button("Show in Finder") { model.reveal(result.destination) }.buttonStyle(.borderless)
                    Button { model.lastResult = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).padding(.leading, 7)
                }.padding(.horizontal, 30).padding(.vertical, 13).background(Palette.accent.opacity(0.075))
            }
        }
    }

    private var transferBar: some View {
        VStack(spacing: 15) {
            if model.isImporting {
                VStack(spacing: 9) {
                    HStack {
                        Text("Copying \(model.completed + 1) of \(model.total) · \(model.currentFile)").font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Spacer()
                        Text("\(Int((Double(model.completed) + camera.downloadFraction) / Double(max(model.total, 1)) * 100))%")
                            .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(model.completed) + camera.downloadFraction, total: Double(max(model.total, 1)))
                }
            }
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Palette.subtle).frame(width: 40, height: 40)
                    Image(systemName: "folder").font(.system(size: 19, weight: .light)).foregroundStyle(Palette.accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("COPY TO").font(.system(size: 8, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text(model.destination.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                            .font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle).help(model.destination.path)
                        Button("Change…") { model.chooseDestination() }.font(.system(size: 11)).buttonStyle(.borderless).disabled(model.isImporting)
                    }
                }
                Spacer(minLength: 8)
                if model.isImporting {
                    Button(model.stopRequested ? "Finishing this file…" : "Stop after this file") { model.stopImport() }
                        .disabled(model.stopRequested).controlSize(.large)
                } else {
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(model.selection.isEmpty ? "Select your favorites" : "\(model.selection.count) selected · \(byteString(model.selectedBytes))")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Button { model.importSelected() } label: {
                            Label(model.selection.isEmpty ? "Copy to Mac" : "Copy \(model.selection.count) to Mac", systemImage: "arrow.down.to.line")
                                .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 3)
                        }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canImport)
                    }
                }
            }
        }.padding(.horizontal, 30).padding(.vertical, 20).background(Palette.card.opacity(0.5))
    }
}

struct PhotoCard: View {
    let item: MediaItem
    let thumbnail: NSImage?
    let selected: Bool
    let imported: Bool
    var select: () -> Void
    var preview: () -> Void
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button(action: select) {
                GeometryReader { geo in
                    ZStack {
                        RoundedRectangle(cornerRadius: 11).fill(Palette.subtle)
                        if let thumbnail {
                            Image(nsImage: thumbnail).resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped()
                        } else {
                            Image(systemName: item.kind == .video ? "video" : "photo").font(.system(size: 30, weight: .ultraLight)).foregroundStyle(.secondary)
                        }
                        if selected { Palette.accent.opacity(0.12) }
                        VStack {
                            HStack {
                                if imported { Image(systemName: "checkmark.seal.fill").foregroundStyle(.white).padding(6).background(.black.opacity(0.4), in: Circle()) }
                                Spacer()
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 21, weight: .medium))
                                    .foregroundStyle(selected ? Palette.accent : .white)
                                    .background(Circle().fill(selected ? .white : .black.opacity(0.18)).padding(2))
                                    .opacity(selected || hovered ? 1 : 0.7)
                            }
                            Spacer()
                            HStack {
                                if item.kind == .video { Image(systemName: "play.fill").font(.caption).foregroundStyle(.white).padding(6).background(.black.opacity(0.4), in: Capsule()) }
                                Spacer()
                            }
                        }.padding(10)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? Palette.accent : .clear, lineWidth: 3))
                }.aspectRatio(1.24, contentMode: .fit)
            }.buttonStyle(.plain).accessibilityLabel("\(selected ? "Deselect" : "Select") \(item.name)")
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text("\(item.date.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Unknown date") · \(byteString(item.byteCount))")
                        .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(action: preview) { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10)).padding(3) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Preview \(item.name)")
            }
        }
        .onHover { hovered = $0 }
        .contextMenu { Button("Preview", action: preview); Button(selected ? "Deselect" : "Select", action: select) }
    }
}
