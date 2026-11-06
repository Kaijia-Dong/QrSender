import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var receiver = TransferReceiver()
    @State private var isSharing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                ZStack {
                    QRScannerView { receiver.acceptQRCode($0) }
                    RoundedRectangle(cornerRadius: 22).stroke(.white, lineWidth: 3).padding(42)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .frame(maxHeight: 360)
                VStack(alignment: .leading, spacing: 9) {
                    Text(receiver.metadata?.FileName ?? "等待文件信息").font(.headline).lineLimit(1)
                    ProgressView(value: receiver.progress).tint(.blue)
                    if let metadata = receiver.metadata { Text("\(receiver.receivedCount) / \(metadata.ChunkCount) 个分片 · 还差 \(receiver.missingCount) 个 · \(Int(receiver.progress * 100))%") .foregroundStyle(.secondary) }
                    Text(receiver.message).font(.subheadline).foregroundStyle(.secondary)
                    if let error = receiver.lastError { Text(error).font(.footnote).foregroundStyle(.red) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if receiver.completedFile != nil {
                    Button("分享或用其他 App 打开", systemImage: "square.and.arrow.up") { isSharing = true }
                        .buttonStyle(.borderedProminent)
                }
                HStack {
                    Button("重新接收", role: .destructive) { receiver.reset() }
                    Spacer()
                    Text("FDQR v1").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
            .navigationTitle("文件二维码接收")
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            .sheet(isPresented: $isSharing) {
                if let url = receiver.completedFile { ShareSheet(items: [url]) }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
