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
        let on = visible && !away && hold.pull == nil && !hold.swiping
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
        .onChange(of: shown?.state) { settle() }
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
                        .foregroundStyle(Theme.faint)
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
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .frame(height: Self.height)
            .frame(maxWidth: 280)
            .fixedSize(horizontal: true, vertical: false)
            .background { BarFrost(shape: Capsule(), space: space) }
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

/// Downloads, on warm paper as Settings and New Space. Tap a finished file
/// to open it here (Quick Look); ↑ shares it; a saving one shows its
/// progress and ✕ to stop it. Hold one for Share…, Show in Files, and
/// Delete. Clear takes ended ones off the list (the files stay).
struct DownloadsSheet: View {
    let store: BrowserStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var preview: URL?
    @State private var deleting: Download?
    /// Firn's own hold menu on a download (`FrostMenu`).
    @State private var menu: OpenHoldMenu?
    @State private var held: Download?
    @State private var pressing: ObjectIdentifier?
    @State private var pointer = MenuPointer()
    @State private var frames: [ObjectIdentifier: CGRect] = [:]

    private var space: Space { store.activeSpace }
    private var list: [Download] { Downloads.shared.list(for: space.dataStoreID) }

    var body: some View {
        let list = list
        VStack(spacing: 0) {
            header(canClear: list.contains { $0.state != .downloading })
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if list.isEmpty {
                        Text("Nothing downloaded in this space since Firn opened.")
                            .font(.callout)
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, minHeight: 68)
                            .multilineTextAlignment(.center)
                            .card()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { index, download in
                                if index > 0 {
                                    Theme.holdMenuHairline.frame(height: 0.5).padding(.leading, 66)
                                }
                                row(download)
                            }
                        }
                        .card()
                    }
                    Button(action: FilesApp.showDownloads) {
                        HStack(spacing: 12) {
                            Image(systemName: "folder")
                                .foregroundStyle(Theme.muted)
                                .accessibilityHidden(true)
                            Text("Open in Files").foregroundStyle(Theme.ink)
                            Spacer(minLength: 0)
                        }
                        .font(.body)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressWash(radius: 22))
                    .card()
                    Text("Saved in On My iPhone › Firn › Downloads. Clear only takes them off this list.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 14)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollDisabled(menu != nil)
        }
        .overlay { heldLayer }
        .presentationDetents([.large])
        .presentationBackground {
            ZStack {
                Theme.page
                Theme.frameTint(space.color)
            }
        }
        .tint(Theme.ink)
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

    /// Clear on the left, the title in the middle, and Done on the right.
    private func header(canClear: Bool) -> some View {
        ZStack {
            Text("Downloads")
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button("Clear") { Downloads.shared.clear(space.dataStoreID) }
                    .font(.body)
                    .foregroundStyle(canClear ? Theme.muted : Theme.faint)
                    .disabled(!canClear)
                    .frame(minHeight: 44)
                    .accessibilityHint("Takes finished downloads off this list. The files stay.")
                Spacer()
                Button("Done") { dismiss() }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func row(_ download: Download) -> some View {
        let id = ObjectIdentifier(download)
        let isHeld = held === download
        return DownloadRow(download: download, space: space.color,
                           share: { share(download) }, stop: { download.cancel() })
            .contentShape(Rectangle())
            .scaleEffect(pressing == id ? 0.97 : 1)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: pressing == id)
            .opacity(isHeld ? 0 : 1)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames[id] = $0 }
            .onTapGesture { open(download) }
            .onLongPressGesture(minimumDuration: 0.4) {
                pressing = nil
                hold(download)
            } onPressingChanged: { down in
                pressing = down && canHold(download) ? id : nil
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(download.state == .finished ? .isButton : [])
            .accessibilityAction { open(download) }
            .accessibilityActions { actions(for: download) }
    }

    @ViewBuilder private func actions(for download: Download) -> some View {
        if download.state == .downloading {
            Button("Stop Download") { download.cancel() }
        } else if download.state == .finished, exists(download) {
            Button("Share…") { share(download) }
            Button("Show in Files", action: FilesApp.showDownloads)
            Button("Delete…") { deleting = download }
        }
    }

    /// The held row, lifted on a dim with Firn's menu beside it.
    @ViewBuilder private var heldLayer: some View {
        ZStack(alignment: .topLeading) {
            if menu != nil {
                Theme.holdDim
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
            if let held, let frame = frames[ObjectIdentifier(held)] {
                GeometryReader { geo in
                    let origin = geo.frame(in: .global).origin
                    DownloadRow(download: held, space: space.color, share: {}, stop: {})
                        .frame(width: frame.width, height: frame.height)
                        .background(Theme.page, in: .rect(cornerRadius: 18, style: .continuous))
                        .scaleEffect(menu != nil && !reduceMotion ? 1.03 : 1)
                        .shadow(color: Theme.shadowPeek, radius: 9, y: 8)
                        .offset(x: frame.minX - origin.x, y: frame.minY - origin.y)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .ignoresSafeArea()
            }
            if menu != nil {
                // A tap anywhere but the card closes the menu.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture(perform: closeMenu)
                    .accessibilityLabel("Close Menu")
                    .accessibilityAddTraits(.isButton)
            }
            // The card just under the held row (above it near the bottom),
            // lined up with its leading edge, placed in the sheet's own
            // space: a plain frame, so every row takes its tap.
            GeometryReader { geo in
                if let menu {
                    let box = geo.frame(in: .global)
                    let height = FrostMenu.height(of: menu.sections)
                    let below = menu.tile.maxY + 10 + height < box.maxY - 12
                    let y = below ? menu.tile.maxY + 10 : menu.tile.minY - 10 - height
                    FrostMenu(sections: menu.sections, space: space.color, backdrop: menu.backdrop,
                              pointer: pointer, pick: { item in
                                  closeMenu()
                                  item.action()
                              })
                        .frame(width: min(HoldMenuPlacement.width, box.width - 32))
                        .fixedSize(horizontal: false, vertical: true)
                        .offset(x: menu.tile.minX - box.minX, y: y - box.minY)
                        .id(menu.token)
                        .transition(reduceMotion ? .opacity
                                    : .opacity.combined(with: .scale(scale: 0.9, anchor: below ? .topLeading : .bottomLeading)))
                }
            }
        }
        .accessibilityAction(.escape) { if menu != nil { closeMenu() } }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.22), value: menu?.token)
    }

    // MARK: Doing

    private func exists(_ download: Download) -> Bool {
        download.fileURL.map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } ?? false
    }

    private func canHold(_ download: Download) -> Bool {
        download.state == .finished && exists(download)
    }

    private func open(_ download: Download) {
        guard menu == nil, download.state == .finished, exists(download) else { return }
        preview = download.fileURL
    }

    private func share(_ download: Download) {
        guard let url = download.fileURL, exists(download) else { return }
        ShareSheet.present(url)
    }

    private func hold(_ download: Download) {
        guard canHold(download), let frame = frames[ObjectIdentifier(download)] else { return }
        let items: [[HoldMenuItem]] = [
            [HoldMenuItem(title: "Share…", systemImage: "square.and.arrow.up") { share(download) },
             HoldMenuItem(title: "Show in Files", systemImage: "folder") { FilesApp.showDownloads() }],
            [HoldMenuItem(title: "Delete", systemImage: "trash", closes: true) { deleting = download }],
        ]
        held = download
        menu = OpenHoldMenu(id: download.id, tile: frame, fingerX: frame.minX + 40,
                            sections: items, backdrop: ScreenPicture.take())
    }

    private func closeMenu() {
        menu = nil
        Task {
            try? await Task.sleep(for: .seconds(0.2))
            if menu == nil { held = nil }
        }
    }
}

/// One download: a symbol for its kind, its name, how it's going, and ↑ to
/// share (finished) or ✕ to stop (saving).
private struct DownloadRow: View {
    let download: Download
    let space: String
    let share: () -> Void
    let stop: () -> Void

    private var missing: Bool {
        download.state == .finished && !(download.fileURL.map {
            FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
        } ?? false)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(Theme.muted)
                .frame(width: 40, height: 40)
                .background(Theme.hover, in: .rect(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(download.fileName ?? "Download")
                    .font(.callout)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(status)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(download.state == .failed ? Theme.danger : Theme.muted)
                if download.state == .downloading {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.holdMenuHairline)
                            Capsule().fill(Theme.spaceColor(space))
                                .frame(width: geo.size.width * (download.progress ?? 0))
                                .animation(.easeOut(duration: 0.3), value: download.progress)
                        }
                    }
                    .frame(height: 3)
                    .padding(.top, 5)
                    .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 0)
            if download.state == .downloading {
                roundButton("xmark", label: "Stop Download", action: stop)
            } else if download.state == .finished, !missing {
                roundButton("square.and.arrow.up", label: "Share", action: share)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 68)
    }

    private func roundButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.muted)
                .frame(width: 36, height: 36)
                .background(Theme.hover, in: Circle())
                // 44pt to tap.
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
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

/// A warm wash under a tapping finger, in the card's corners.
private struct PressWash: ButtonStyle {
    let radius: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(configuration.isPressed ? Theme.press : .clear)
            }
    }
}

private extension View {
    /// The sheet's paper-white card: 22pt corners and a warm hairline.
    func card() -> some View {
        background(Theme.page, in: .rect(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.holdMenuHairline, lineWidth: 0.5)
            }
            .clipShape(.rect(cornerRadius: 22, style: .continuous))
    }
}
