import SwiftUI
import MacDroidCore

struct FileBrowserView: View {
    @ObservedObject var store: MTPStore
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if store.connected {
                locationBar
                Divider()
                VStack(spacing: 12) {
                  HStack {
                    Text("\(store.visible.count) items").font(.caption).foregroundStyle(.secondary)
                    if store.calculatingSize {
                        ProgressView().controlSize(.mini)
                        Text("Calculating folder size…").font(.caption).foregroundStyle(.secondary)
                    } else if let size = store.folderSize {
                        Text("· \(byteString(Int64(clamping: size.bytes))) total · \(size.files) files")
                            .font(.caption).foregroundStyle(.secondary)
                            .help("Includes every file in this folder and its subfolders, regardless of the search filter.")
                    } else if let error = store.sizeError {
                        Button("Size unavailable · Retry") { store.calculateSizes() }.buttonStyle(.borderless).font(.caption).help(error).disabled(store.busy)
                    }
                    Spacer()
                    Picker("Group files", selection: $store.groupByMonth) {
                        Text("Modified month").tag(true)
                        Text("No grouping").tag(false)
                    }.labelsHidden().frame(width: 155).disabled(store.busy)
                        .help("Groups all file types by the modification date reported by the phone, not the photo capture date.")
                  }
                  HStack {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search this folder", text: $store.search).textFieldStyle(.plain)
                    }.padding(8).frame(maxWidth: 260).background(Palette.subtle, in: RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    Button("Select files") { store.selection.formUnion(store.visible.filter { !$0.isFolder }.map(\.id)) }.buttonStyle(.borderless).disabled(store.busy)
                    Button("Clear") { store.selection = [] }.buttonStyle(.borderless).disabled(store.busy || store.selection.isEmpty)
                    Button(role: .destructive) { store.confirmDeleteSelected() } label: { Label("Delete from phone…", systemImage: "trash") }
                        .help("Delete selected files from phone…").accessibilityLabel("Delete from phone…")
                        .disabled(store.busy || store.selectedFiles.isEmpty || model.camera.isDemo)
                  }
                }.padding(.horizontal, 28).padding(.vertical, 14)
                ScrollView {
                    LazyVStack(spacing: 3) {
                        if store.groupByMonth {
                            if !store.visibleFolders.isEmpty {
                                Text("Folders").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                                ForEach(store.visibleFolders) { file in fileRow(file) }
                            }
                            ForEach(store.monthGroups, id: \.month) { group in
                                monthHeader(group.month, files: group.files)
                                ForEach(group.files) { file in fileRow(file) }
                            }
                        } else { ForEach(store.visible) { file in fileRow(file) } }
                        if store.visible.isEmpty && !store.busy {
                            Text(store.search.isEmpty ? "This folder is empty." : "No matching files.").foregroundStyle(.secondary).padding(50)
                        }
                    }.padding(.horizontal, 22).padding(.bottom, 20)
                }.overlay { if store.busy && !store.transferring && !store.deleting { ProgressView().padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "externaldrive.connected.to.line.below").font(.system(size: 52, weight: .ultraLight)).foregroundStyle(Palette.accent)
                    Text("Everything you keep on your phone.").font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("Photos, videos, music, documents, and downloads.\nBrowse folders and copy files in either direction.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(6)
                    Text("On your phone, choose File transfer / Android Auto\nin the USB notification, then reconnect the cable.")
                        .font(.system(size: 13, weight: .medium)).multilineTextAlignment(.center).lineSpacing(5)
                        .padding(22).background(Palette.subtle, in: RoundedRectangle(cornerRadius: 12))
                    if let message = model.usb.accessoryMessage {
                        Label(message.replacingOccurrences(of: "Photo transfer (PTP) for photos or File transfer for all files", with: "File transfer"), systemImage: "cable.connector.slash")
                            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: 510)
                    }
                    if store.busy { ProgressView("Connecting to phone…") }
                    else { Button("Connect file transfer") { Task { await store.connect() } }.buttonStyle(.borderedProminent).controlSize(.large) }
                    Text("Android shares public storage. Private app data and cloud-only files remain in their apps.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: 430).multilineTextAlignment(.center)
                }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let error = store.error {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    ScrollView { Text(error).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 70)
                    Button { store.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.padding(16).background(Color.orange.opacity(0.07))
            }
            if let message = store.message {
                HStack {
                    Label(message, systemImage: "checkmark.circle").font(.caption)
                    Spacer()
                    Button { store.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.padding(16).foregroundStyle(Palette.accent).background(Palette.accent.opacity(0.07))
            }
            Divider()
            footer
        }
    }

    private var locationBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Storage", selection: Binding(get: { store.storageID }, set: { value in Task { await store.load(path: [], storage: value) } })) {
                    ForEach(store.storages) { storage in Text(storage.name).tag(storage.id) }
                }.frame(maxWidth: 250).disabled(store.busy)
                Spacer()
                Text(store.deviceName).font(.caption).foregroundStyle(.secondary)
                Button { Task { await store.load() } } label: { Image(systemName: "arrow.clockwise") }.disabled(store.busy)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    Button { Task { await store.load(path: []) } } label: { Image(systemName: "house") }
                    ForEach(Array(store.path.enumerated()), id: \.element.id) { index, folder in
                        Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                        Button(folder.name) { Task { await store.load(path: Array(store.path.prefix(index + 1))) } }
                    }
                }.buttonStyle(.borderless).font(.system(size: 12)).disabled(store.busy)
            }
        }.padding(.horizontal, 28).padding(.vertical, 18)
    }

    private func fileRow(_ file: RemoteFile) -> some View {
        Button { store.toggle(file) } label: {
            HStack(spacing: 13) {
                Image(systemName: file.symbol).font(.system(size: 21, weight: .light)).foregroundStyle(Palette.accent).frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text(file.isFolder ? folderDescription(file) : "\(byteString(Int64(clamping: file.size))) · \(file.date?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown date")")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: file.isFolder ? "chevron.right" : store.selection.contains(file.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(store.selection.contains(file.id) ? Palette.accent : Color.secondary.opacity(0.5))
            }.padding(13).background(store.selection.contains(file.id) ? Palette.accent.opacity(0.1) : Palette.card.opacity(0.45), in: RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(store.busy)
    }

    private func folderDescription(_ file: RemoteFile) -> String {
        if let size = store.folderSizes[String(file.id)] {
            return "Folder · \(byteString(Int64(clamping: size.bytes))) · \(size.files) \(size.files == 1 ? "file" : "files") including subfolders"
        }
        return store.calculatingSize ? "Folder · Calculating…" : "Folder · Size unavailable"
    }

    private func monthHeader(_ month: FileMonth, files: [RemoteFile]) -> some View {
        let ids = Set(files.map(\.id))
        let allSelected = ids.isSubset(of: store.selection)
        return HStack {
            Text(month.title).font(.headline)
            Text("\(files.count) \(files.count == 1 ? "file" : "files")").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(allSelected ? "Clear month" : "Select month") {
                if allSelected { store.selection.subtract(ids) } else { store.selection.formUnion(ids) }
            }.buttonStyle(.borderless).disabled(store.busy)
                .help("Selects the files shown in this group. Search filters apply; files in other folders are not included.")
        }.padding(.top, 18).padding(.bottom, 8)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.transferring || store.deleting {
                HStack {
                    Text("\(store.deleting ? "Deleting" : "Transferring") \(min(store.completed + 1, store.total)) of \(store.total) · \(store.currentFile)").font(.caption).lineLimit(1)
                    Spacer()
                    Button(store.stopRequested ? "Finishing this file…" : "Stop after this file") { store.stopRequested = true }.disabled(store.stopRequested)
                }
                ProgressView(value: Double(store.completed) + store.fraction, total: Double(max(1, store.total)))
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MAC DESTINATION").font(.system(size: 8, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                    HStack {
                        Text(model.destination.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                            .font(.caption).lineLimit(1).truncationMode(.middle).help(model.destination.path)
                        Button("Change…") { model.chooseDestination() }.buttonStyle(.borderless).font(.caption).disabled(store.busy)
                    }
                }
                Spacer()
                Button { store.chooseFilesToSend() } label: { Label("Send to phone…", systemImage: "arrow.up.to.line") }
                    .controlSize(.large).disabled(!store.connected || store.busy)
                Button { store.copySelected(to: model.destination, record: model.recordImport) } label: {
                    Label(store.selection.isEmpty ? "Copy to Mac" : "Copy \(store.selection.count) to Mac", systemImage: "arrow.down.to.line")
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(store.selectedFiles.isEmpty || store.busy)
            }
        }.padding(22).background(Palette.card.opacity(0.5))
    }
}
