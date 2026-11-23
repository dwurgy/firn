import FirnCore
import QuickLook
import SwiftUI

// Downloads on the iPhone (docs/IOS-PLAN.md, phase 6, "Downloads to Files",
// step 4; look from docs/downloads-design.html): the pill above the bar while
// one saves, then "Saved to Files"; and the Downloads sheet, from the page
// menu, the command bar, or a tap on the pill. Only the space on screen's
// downloads (each space is its own browser). The list is forgotten on quit,
// as on the Mac; the files stay in Files.

extension EnvironmentValues {
    /// Opens the Downloads sheet (`BrowserScreen` shows it): the page menu's
    /// Downloads row and the command bar's.
    @Entry var showDownloads: SheetAction? = nil
}

extension Downloads {
    /// What the page menu's Downloads row says under its name: how many are
    /// saving, or how many there are. Nil while the space has none.
    func summary(for dataStoreID: UUID) -> String? {
        let list = list(for: dataStoreID)
        guard !list.isEmpty else { return nil }
        let saving = list.filter { $0.state == .downloading }.count
        if saving > 0 { return "\(saving) saving" }
        return list.count == 1 ? "1 file" : "\(list.count) files"
    }
}

/// The Files app, opened on Firn's Downloads folder (On My iPhone › Firn ›
/// Downloads). Files can only open a folder, not point at one file in it.
@MainActor enum FilesApp {
    static func showDownloads() {
        guard let folder = Downloads.folder,
              var parts = URLComponents(url: folder, resolvingAgainstBaseURL: false) else { return }
        // Files' own address for a folder on the phone: the same path, under
        // its scheme. Only ever Firn's own folder, never anything a page gave.
        parts.scheme = "shareddocuments"
        if let url = parts.url { UIApplication.shared.open(url) }
    }
}

/// How big a file is, in the words Files uses ("4.8 MB").
private func size(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

// MARK: - The pill

/// A quiet frosted pill just above the bar while a download saves: a ring
/// filling in the space's color, the file's name, and how far along it is.
/// Then a check and "Saved to Files", held a few seconds before it fades.
/// A tap opens Downloads. The page stays usable; the pill never covers the
/// bar.
struct DownloadPill: View {
    let store: BrowserStore
    let hold: Hold
    /// The overview, a hidden page, typing, or the page menu.
    let away: Bool
    /// The overview showing counts as away too (read here, not by the screen).
    let landing: Landing
    /// The bar's top edge (global), and the page's ZStack's top (global), so
    /// the pill sits just above the bar wherever it is.
    let barTop: CGFloat
    let open: () -> Void

    @State private var shown: Download?
    @State private var visible = false
    @State private var hiding: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let height: CGFloat = 36
    private static let gap: CGFloat = 10

    var body: some View {
        let space = store.activeSpace
        let on = visible && !away && !landing.shown && hold.pull == nil && !hold.swiping
            && shown?.dataStoreID == space.dataStoreID
        GeometryReader { geo in
            let top = barTop - geo.frame(in: .global).minY
            ZStack {
                if on, let shown {
                    pill(shown, space: space.color)
                        .transition(reduceMotion ? .opacity
                                    : .opacity.combined(with: .offset(y: 6)).combined(with: .scale(scale: 0.97)))
                }
            }
            .frame(width: geo.size.width)
            .position(x: geo.size.width / 2, y: top - Self.gap - Self.height / 2)
            .animation(.easeOut(duration: 0.2), value: barTop)
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25), value: on)
        .onChange(of: Downloads.shared.latest.map(ObjectIdentifier.init), initial: true) {
            guard let latest = Downloads.shared.latest, latest !== shown else { return }
            show(latest)
        }
        .onChange(of: shown?.state) { _, state in
            settle()
            announce(state)
        }
    }

    /// VoiceOver hears a download end, wherever focus is (the pill is out
    /// of the way, so it's rarely focused). Not a stop: that was a tap.
    private func announce(_ state: Download.State?) {
        guard let shown, shown.dataStoreID == store.activeSpace.dataStoreID else { return }
        let name = shown.fileName ?? "Download"
        switch state {
        case .finished: AccessibilityNotification.Announcement("\(name) saved to Files").post()
        case .failed: AccessibilityNotification.Announcement("\(name) download failed").post()
        default: break
        }
    }

    private func show(_ download: Download) {
        hiding?.cancel()
        shown = download
        visible = download.state == .downloading
        settle()
    }

    /// Done or failed: it holds a few seconds, then fades. Stopped: it goes.
    private func settle() {
        guard let shown, shown.state != .downloading else { return }
        hiding?.cancel()
        let wait: Duration = shown.state == .cancelled ? .zero : .seconds(3.2)
        hiding = Task {
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            visible = false
        }
    }

    private func pill(_ download: Download, space: String) -> some View {
        Button(action: open) {
            HStack(spacing: 8) {
                switch download.state {
                case .downloading:
                    ProgressRing(progress: download.progress, space: space)
                    Text(download.fileName ?? "Download")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(Theme.ink)
                    Text(download.progress.map { "\(Int(($0 * 100).rounded()))%" }
                         ?? size(download.receivedBytes))
                        .monospacedDigit()
                        // Muted, not faint: text needs 4.5:1 (faint is 2.9:1 on paper).
                        .foregroundStyle(Theme.muted)
                case .finished:
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.page)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Theme.spaceColor(space)))
                    Text("Saved to Files").foregroundStyle(Theme.ink)
                case .failed, .cancelled:
                    Image(systemName: "exclamationmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 20, height: 20)
                        .background(Circle().stroke(Theme.faint, lineWidth: 1.5))
                    Text(download.state == .failed ? "Download failed" : "Download stopped")
                        .foregroundStyle(Theme.ink)
                }
            }
            .font(.subheadline)
            // Fits its 36pt (the bar's own cap); VoiceOver reads it whole.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .frame(height: Self.height)
            .frame(maxWidth: 280)
            .fixedSize(horizontal: true, vertical: false)
            .background { BarFrost(shape: Capsule()) }
            .shadow(color: Theme.shadowPeek.opacity(0.5), radius: 9, y: 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label(download))
        .accessibilityHint("Shows your downloads")
    }

    private func label(_ download: Download) -> String {
        let name = download.fileName ?? "Download"
        switch download.state {
        case .downloading:
            return "Downloading \(name)" + (download.progress.map { ", \(Int(($0 * 100).rounded())) percent" } ?? "")
        case .finished: return "\(name), saved to Files"
        case .failed: return "\(name), download failed"
        case .cancelled: return "\(name), download stopped"
        }
    }
}

/// A ring filling in the space's color; with no size known, a quarter of it
/// turning slowly (still with Reduce Motion).
private struct ProgressRing: View {
    let progress: Double?
    let space: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turning = false

    var body: some View {
        ZStack {
            Circle().stroke(Theme.holdMenuHairline, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress ?? 0.25)
                .stroke(Theme.spaceColor(space), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90 + (progress == nil && turning ? 360 : 0)))
                .animation(.easeOut(duration: 0.3), value: progress)
        }
        .frame(width: 16, height: 16)
        .padding(2)
        .onAppear {
            guard progress == nil, !reduceMotion else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { turning = true }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The sheet

/// Downloads, as iOS's own list (docs/IOS-PLAN.md, section 9): a grouped
/// list on iOS's neutral background, as Settings and New Space, never washed
/// in the space's color. Tap a finished file to open it here (Quick Look);
/// ↑ shares it; a saving one shows its progress and ✕ to stop it. Hold a
/// file for iOS's menu (Share…, Show in Files, Delete); a swipe left deletes.
/// Clear takes ended ones off the list (the files stay).
struct DownloadsSheet: View {
    let store: BrowserStore

    @Environment(\.dismiss) private var dismiss
    @State private var preview: URL?
    @State private var deleting: Download?

    private var space: Space { store.activeSpace }

    var body: some View {
        let list = Downloads.shared.list(for: space.dataStoreID)
        NavigationStack {
            List {
                Section {
                    if list.isEmpty {
                        Text("Nothing downloaded in this space since Firn opened.")
                            .foregroundStyle(Color.secondary)
                    } else {
                        ForEach(list) { download in
                            row(download)
                        }
                    }
                }

                Section {
                    Button(action: FilesApp.showDownloads) {
                        Label {
                            Text("Open in Files").foregroundStyle(Color.primary)
                        } icon: {
                            Image(systemName: "folder").foregroundStyle(Color.secondary)
                        }
                    }
                } footer: {
                    Text("Saved in On My iPhone › Firn › Downloads. Clear only takes them off this list.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") { Downloads.shared.clear(space.dataStoreID) }
                        .tint(Theme.ink)
                        .disabled(!list.contains { $0.state != .downloading })
                        .accessibilityHint("Takes finished downloads off this list. The files stay.")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) { dismiss() }
                        .tint(Theme.ink)
                }
            }
        }
        // Ink, so iOS's menu draws its symbols neutral; only the progress
        // bar is Glacier, as the system's other controls.
        .tint(Theme.ink)
        .presentationDetents([.large])
        .quickLookPreview($preview)
        .alert("Delete this file?", isPresented: Binding(get: { deleting != nil },
                                                          set: { if !$0 { deleting = nil } }),
               presenting: deleting) { download in
            Button("Delete", role: .destructive) { Downloads.shared.delete(download) }
            Button("Cancel", role: .cancel) {}
        } message: { download in
            Text("“\(download.fileName ?? "This file")” can’t be brought back.")
        }
    }

    // MARK: Parts

    /// One row: a tap opens a finished file; iOS's own hold menu and swipe
    /// only on a file that's really there.
    @ViewBuilder private func row(_ download: Download) -> some View {
        let there = download.state == .finished && exists(download)
        DownloadRow(download: download, missing: download.state == .finished && !there,
                    open: { preview = download.fileURL },
                    share: { share(download) }, stop: { download.cancel() })
            .contextMenu {
                if there {
                    Button("Share…", systemImage: "square.and.arrow.up") { share(download) }
                    Button("Show in Files", systemImage: "folder", action: FilesApp.showDownloads)
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = download }
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if there {
                    // No destructive role: the row stays until the alert's
                    // Delete, since the file can't be brought back.
                    Button("Delete", systemImage: "trash") { deleting = download }
                        .tint(.red)
                }
            }
    }

    // MARK: Doing

    private func exists(_ download: Download) -> Bool {
        download.fileURL.map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } ?? false
    }

    private func share(_ download: Download) {
        guard let url = download.fileURL, exists(download) else { return }
        ShareSheet.present(url)
    }
}

/// One download: a symbol for its kind, its name, how it's going, and ↑ to
/// share (finished) or ✕ to stop (saving).
private struct DownloadRow: View {
    let download: Download
    /// Finished, but moved or deleted in Files since.
    let missing: Bool
    let open: () -> Void
    let share: () -> Void
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // The row's own button: a tap anywhere but ↑ or ✕ opens the file.
            Button(action: open) {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 18))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 40, height: 40)
                        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        // `Color`, not `.primary`: inside a list's button the
                        // style would follow the tint.
                        Text(download.fileName ?? "Download")
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(status)
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(download.state == .failed ? Theme.danger : Color.secondary)
                        if download.state == .downloading {
                            ProgressView(value: download.progress ?? 0)
                                .tint(Theme.accent)
                                .padding(.top, 4)
                                .accessibilityHidden(true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .disabled(download.state != .finished || missing)
            .accessibilityElement(children: .combine)

            if download.state == .downloading {
                sideButton("xmark", label: "Stop Download", action: stop)
            } else if download.state == .finished, !missing {
                sideButton("square.and.arrow.up", label: "Share", action: share)
            }
        }
        .padding(.vertical, 2)
    }

    /// Borderless, so it takes its own tap inside the row.
    private func sideButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.secondary)
                // 44pt to tap.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }

    private var status: String {
        switch download.state {
        case .downloading:
            if let progress = download.progress, let total = download.totalBytes {
                return "Saving… \(Int((progress * 100).rounded()))% · \(size(download.receivedBytes)) of \(size(total))"
            }
            return "Saving… \(size(download.receivedBytes))"
        case .finished:
            if missing { return "Moved or deleted in Files" }
            return download.totalBytes.map { "Done · \(size($0))" } ?? "Done"
        case .failed: return "Failed"
        case .cancelled: return "Stopped"
        }
    }

    /// A plain symbol for the kind of file, from its name's ending.
    private var symbol: String {
        let ext = (download.fileName as NSString?)?.pathExtension.lowercased() ?? ""
        switch ext {
        case "zip", "gz", "tgz", "bz2", "xz", "7z", "rar", "tar": return "doc.zipper"
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "bmp", "svg": return "photo"
        case "mp4", "mov", "m4v", "webm", "avi", "mkv": return "film"
        case "mp3", "m4a", "wav", "aac", "flac", "ogg": return "music.note"
        case "pdf", "txt", "rtf", "doc", "docx", "pages", "md": return "doc.text"
        default: return "doc"
        }
    }
}
