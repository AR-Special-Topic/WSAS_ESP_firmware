import Foundation
import SwiftUI

/// Feed this view with updates from exportAll(to:progress:).
public struct SDExportProgressView: View {
    public let progress: SDExportProgress
    public init(progress: SDExportProgress) { self.progress = progress }

    private func size(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if progress.phase == .scanning {
                ProgressView("正在掃描 SD 卡…")
            } else {
                ProgressView(value: progress.fractionCompleted) {
                    Text("整體傳輸 \(Int(progress.fractionCompleted * 100))%")
                }
                Text("Event \(progress.completedEvents)/\(progress.totalEvents) · 檔案 \(progress.completedFiles)/\(progress.totalFiles)")
                Text("WAV \(size(progress.completedWAVBytes)) / \(size(progress.totalWAVBytes))")
                Text("總計 \(size(progress.completedBytes)) / \(size(progress.totalBytes))")
                if !progress.path.isEmpty {
                    Text(progress.path).font(.caption).lineLimit(1)
                    ProgressView(value: progress.fileFractionCompleted)
                    Text("\(size(progress.bytes)) / \(size(progress.total))").font(.caption)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Keep this view's Control operations serialized with the App's export actions.
@MainActor
public struct VADControlView: View {
    private let link: SDExportBLELink
    @State private var applied: Bool?
    @State private var changing = false
    @State private var errorMessage: String?

    public init(link: SDExportBLELink) { self.link = link }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(applied.map { $0 ? "VAD 已開啟" : "VAD 已關閉" } ?? "選擇 VAD 狀態")
            HStack {
                Button("開啟 VAD") { change(true) }
                Button("停止 VAD") { change(false) }
                if changing { ProgressView() }
            }
            .disabled(changing)
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
        }
    }

    private func change(_ enabled: Bool) {
        changing = true
        errorMessage = nil
        Task { @MainActor in
            defer { changing = false }
            do { applied = try await link.setVAD(enabled: enabled) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
