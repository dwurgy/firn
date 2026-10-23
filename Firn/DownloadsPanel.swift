import AppKit
import FirnCore
import SwiftUI
import UniformTypeIdentifiers

/// The space's downloads, at the right of the space row. Shown only while
/// the space has some; otherwise its spot stays empty, so the space icons
/// don't shift. While files arrive, a thin ring around the arrow fills.
/// The popover opens on its own as a download starts in the space on screen.
struct DownloadsButton: View {
    let store: BrowserStore
    let window: WindowModel

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
                    DownloadsIcon(progress: progress(of: downloads), active: downloads.contains { $0.state == .downloading })
                }
                .popover(isPresented: Bindable(window).showsDownloads, arrowEdge: .top) {
                    DownloadsPanel(dataStoreID: dataStoreID, window: window)
                }
                .transition(.opacity)
            }
        }
        .onChange(of: Downloads.shared.latest?.id) {
            // Only one from the space on screen, and only where it can be seen.
            guard let latest = Downloads.shared.latest, latest.dataStoreID == dataStoreID,
                  !window.sidebarCollapsed else { return }
            window.showsOverflow = false
            // A beat, so the button is there to open from when it's the first.
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                window.showsDownloads = true
            }
        }
        .onChange(of: downloads.isEmpty) { if downloads.isEmpty { window.showsDownloads = false } }
        .onChange(of: store.activeSpaceID) { window.showsDownloads = false }
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

    var body: some View {
        ZStack {
            Image(systemName: "arrow.down")
                .font(.system(size: active ? 10 : 13, weight: .medium))
            if active {
                Circle()
                    .stroke(Theme.faint.opacity(0.35), lineWidth: 1.5)
                Circle()
                    .trim(from: 0, to: progress ?? 0)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
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
