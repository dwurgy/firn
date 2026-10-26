import AppKit
import FirnCore
import SwiftUI
import UniformTypeIdentifiers

/// The space's downloads, at the right of the space row. Shown only while
/// the space has some; otherwise its spot stays empty, so the overflow
/// doesn't shift. While files arrive, a thin ring around the arrow fills.
/// The popover opens on its own as a download starts in the space on screen.
/// As a file arrives, the arrow dips and settles, and frost forms over the
/// button in the space's color, holds, and thaws, like the tidy pill.
struct DownloadsButton: View {
    let store: BrowserStore
    let window: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counts arrivals; each one plays the arrow's dip.
    @State private var landings = 0
    @State private var frosted = false
    @State private var thawTask: Task<Void, Never>?
    /// The popover is about to open on its own; the finish isn't needed then.
    @State private var opening = false
    /// The ring shows only once a file has been arriving for a beat, so a
    /// quick one doesn't flash it.
    @State private var showsRing = false

    var body: some View {
        let dataStoreID = store.activeSpace.dataStoreID
        let downloads = Downloads.shared.list(for: dataStoreID)
        Group {
            if downloads.isEmpty {
                Color.clear.frame(width: 28, height: 28)
            } else {
                ChromeButton("Downloads") {
                    window.showsDownloads.toggle()
                } icon: {
                    DownloadsIcon(progress: progress(of: downloads),
                                  active: showsRing,
                                  landings: landings)
                }
                .background {
                    if frosted {
                        FrostGlass(shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
                                   color: Theme.spaceColor(store.activeSpace.color))
                            .transition(.opacity)
                    }
                }
                .popover(isPresented: Bindable(window).showsDownloads, arrowEdge: .top) {
                    DownloadsPanel(dataStoreID: dataStoreID, window: window)
                }
                .transition(.opacity)
            }
        }
        // Fades in and out, as the overflow box does.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: downloads.isEmpty)
        .onChange(of: Downloads.shared.latest?.id) {
            // Only one from the space on screen, and only where it can be seen.
            guard let latest = Downloads.shared.latest, latest.dataStoreID == dataStoreID,
                  !window.sidebarCollapsed else { return }
            window.showsOverflow = false
            opening = true
            // Once the button has faded in, so it opens from a settled spot.
            Task {
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 260))
                window.showsDownloads = true
                opening = false
            }
        }
        .onChange(of: downloads.isEmpty) { if downloads.isEmpty { window.showsDownloads = false } }
        .onChange(of: store.activeSpaceID) {
            window.showsDownloads = false
            thawTask?.cancel()
            frosted = false
        }
        .task(id: downloads.contains { $0.state == .downloading }) {
            guard downloads.contains(where: { $0.state == .downloading }) else {
                showsRing = false
                return
            }
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { showsRing = true }
        }
        .onChange(of: downloads.map { Arrival(id: $0.id, state: $0.state) }) { old, new in
            // Only a file in this list that was arriving and now has.
            let arriving = Set(old.filter { $0.state == .downloading }.map(\.id))
            guard new.contains(where: { $0.state == .finished && arriving.contains($0.id) }) else { return }
            land()
        }
    }

    private struct Arrival: Equatable {
        let id: UUID
        let state: Download.State
    }

    /// The finish: the arrow dips, frost forms, holds a moment, and thaws.
    /// Reduce Motion: no dip; the frost just fades in and out. Not while the
    /// popover is showing (or about to): its "Done" already says so.
    private func land() {
        guard !window.showsDownloads, !opening else { return }
        if !reduceMotion { landings += 1 }
        withAnimation(.easeOut(duration: 0.3)) { frosted = true }
        thawTask?.cancel()
        thawTask = Task {
            try? await Task.sleep(for: .milliseconds(1300))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.thaw) { frosted = false }
        }
    }

    /// How far along the files still arriving are, together; nil when none
    /// says how big it is.
    private func progress(of downloads: [Download]) -> Double? {
        let known = downloads.filter { $0.state == .downloading }.compactMap(\.progress)
        guard !known.isEmpty else { return nil }
        return known.reduce(0, +) / Double(known.count)
    }
}

/// A down arrow; while files arrive, a faint ring around it fills as they do.
private struct DownloadsIcon: View {
    let progress: Double?
    let active: Bool
    let landings: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Scaled rather than resized, so it glides between sizes.
            Image(systemName: "arrow.down")
                .font(.system(size: 13, weight: .medium))
                .scaleEffect(active ? 10.0 / 13 : 1)
                // As a file arrives: a soft dip, then settling back, no bounce.
                .keyframeAnimator(initialValue: 0.0, trigger: landings) { arrow, dip in
                    arrow.offset(y: dip)
                } keyframes: { _ in
                    CubicKeyframe(3, duration: 0.18)
                    CubicKeyframe(0, duration: 0.32)
                }
            if active {
                Group {
                    Circle()
                        .stroke(Theme.faint.opacity(0.35), lineWidth: 1.5)
                    Circle()
                        .trim(from: 0, to: progress ?? 0)
                        .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        // Fills smoothly between progress updates.
                        .animation(reduceMotion ? nil : .linear(duration: 0.3), value: progress)
                }
                .transition(.opacity)
            }
        }
        // The arrow shrinks as the ring fades in, and grows back as it goes.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: active)
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

private struct DownloadsPanel: View {
    let dataStoreID: UUID
    let window: WindowModel

    var body: some View {
        let downloads = Downloads.shared.list(for: dataStoreID)
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent downloads")
                    .font(Theme.groupNameFont)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if downloads.contains(where: { $0.state != .downloading }) {
                    Button("Clear") { Downloads.shared.clear(dataStoreID) }
                        .buttonStyle(TextActionStyle())
                        .help("Takes finished downloads off this list. The files stay.")
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
            ScrollView {
                VStack(spacing: Theme.rowSpacing) {
                    ForEach(downloads) { DownloadRow(download: $0) }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Downloads folder") {
                    if let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                        NSWorkspace.shared.open(folder)
                    }
                }
                .buttonStyle(TextActionStyle())
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .frame(width: 300)
    }
}

/// One file: the Mac's icon for its kind, its name, and how it's going.
/// A click on a finished one opens it; on hover, a magnifier shows it in
/// Finder (or ✕ stops one still arriving).
private struct DownloadRow: View {
    let download: Download
    @State private var hovering = false

    private var name: String { download.fileName ?? "Starting…" }
    private var finished: Bool { download.state == .finished && download.fileURL != nil }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Image(nsImage: Self.icon(for: download.fileName))
                    .resizable()
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(Theme.tabFont)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(status)
                        .font(Theme.hintFont.monospacedDigit())
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.rowPadding)
            .padding(.vertical, 6)
            // Room for the button on the right, so long names stop short of it.
            .padding(.trailing, hovering ? 20 : 0)
            .background {
                RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                    .fill(hovering && finished ? Theme.hover : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if hovering {
                if download.state == .downloading {
                    Button("Stop download", systemImage: "xmark") { download.cancel() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(CloseButtonStyle())
                        .help("Stop download")
                        .padding(.trailing, 8)
                } else if finished {
                    Button("Show in Finder", systemImage: "magnifyingglass", action: reveal)
                        .labelStyle(.iconOnly)
                        .buttonStyle(CloseButtonStyle())
                        .help("Show in Finder")
                        .padding(.trailing, 8)
                }
            }
        }
        .onHover { hovering = $0 }
        .help(finished ? "Open \(name)" : "")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(status)")
        .accessibilityHint(finished ? "Opens the file" : "")
        .accessibilityAction(named: "Show in Finder") { if finished { reveal() } }
    }

    private var status: String {
        switch download.state {
        case .downloading:
            if let progress = download.progress { return "Downloading… \(Int(progress * 100))%" }
            return "Downloading…"
        case .finished: return "Done"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    /// Opens the file with its app. It carries macOS's quarantine mark, so
    /// Gatekeeper still checks apps and scripts before they run.
    private func open() {
        guard finished, let url = download.fileURL, FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        else { return reveal() }
        NSWorkspace.shared.open(url)
    }

    /// Shows the file in Finder, or the Downloads folder if it's been moved.
    private func reveal() {
        if let url = download.fileURL, FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            NSWorkspace.shared.open(folder)
        }
    }

    /// The Mac's icon for the kind of file, from its name alone (the file is
    /// never read for it).
    private static func icon(for name: String?) -> NSImage {
        let ext = name.map { ($0 as NSString).pathExtension } ?? ""
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
    }
}
