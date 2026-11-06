import CryptoKit
import Foundation

@MainActor
final class TransferReceiver: ObservableObject {
    @Published private(set) var metadata: FDQRMetadata?
    @Published private(set) var receivedCount = 0
    @Published private(set) var message = "请将相机对准电脑上的二维码"
    @Published private(set) var completedFile: URL?
    @Published private(set) var lastError: String?

    private var sessionID: UInt64?
    private var chunks: [Int: Data] = [:]
    private var parity: [Int: Data] = [:]
    // Frames can be decoded before the metadata frame finishes decoding. Keep this small, per-session
    // staging area so camera warm-up never turns the first data frames into permanent losses.
    private var pendingSessionID: UInt64?
    private var pendingFrames: [FDQRFrame] = []
    private let pendingFrameLimit = 160
    private let frameDecoder = QRFrameDecoder()
    private var completed = false
    private var lastUIRefresh = Date.distantPast

    var progress: Double { guard let metadata else { return 0 }; return Double(receivedCount) / Double(metadata.ChunkCount) }
    var missingCount: Int { guard let metadata else { return 0 }; return metadata.ChunkCount - receivedCount }

    /// QR decoding uses one bounded lane: when overloaded it keeps the newest frame, never a stale backlog.
    func acceptQRCode(_ qrText: String) {
        frameDecoder.submit(qrText) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let frame): self.accept(frame)
            case .failure(let error as FDQRError):
                guard error != .crcMismatch else { return }
                self.show(error.localizedDescription)
            case .failure(let error): self.show(error.localizedDescription)
            }
        }
    }

    private func accept(_ frame: FDQRFrame) {
        guard !completed else { return }
        do {
            guard let sessionID else {
                if frame.type == .metadata {
                    // A metadata frame defines a new transfer. Do not replay staged frames from another session.
                    if pendingSessionID != nil && pendingSessionID != frame.sessionID { pendingFrames = [] }
                    try receiveMetadata(frame)
                    replayPendingFrames()
                    try completeIfReady()
                } else { stage(frame) }
                return
            }
            guard sessionID == frame.sessionID else { return }
            switch frame.type {
            case .metadata: try receiveMetadata(frame)
            case .data: receiveData(frame)
            case .parity: receiveParity(frame)
            }
            try completeIfReady()
        } catch { show(error.localizedDescription) }
    }

    func reset() {
        metadata = nil; sessionID = nil; chunks = [:]; parity = [:]; pendingSessionID = nil; pendingFrames = []; receivedCount = 0
        completed = false; completedFile = nil; lastError = nil; lastUIRefresh = .distantPast; message = "请将相机对准电脑上的二维码"
    }

    private func receiveMetadata(_ frame: FDQRFrame) throws {
        let decoded = try JSONDecoder().decode(FDQRMetadata.self, from: frame.payload)
        guard decoded.Magic == "FDQR", decoded.Version == 1, decoded.ChunkSize > 0, decoded.ChunkCount > 0,
              decoded.ParityGroupSize == 8 else { throw FDQRError.invalidMetadata }
        if metadata == nil {
            sessionID = frame.sessionID; metadata = decoded
            message = "已识别：\(decoded.FileName)，正在接收"
        }
    }

    private func receiveData(_ frame: FDQRFrame) {
        guard let metadata, frame.total == metadata.ChunkCount, frame.number >= 0, frame.number < metadata.ChunkCount else { return }
        if chunks[frame.number] == nil {
            chunks[frame.number] = frame.payload
            publishProgressIfNeeded()
        }
        recoverIfPossible(groupStart: frame.number / metadata.ParityGroupSize * metadata.ParityGroupSize)
    }

    private func receiveParity(_ frame: FDQRFrame) {
        guard let metadata, frame.total == metadata.ChunkCount, frame.number >= 0, frame.number < metadata.ChunkCount else { return }
        parity[frame.number] = frame.payload
        recoverIfPossible(groupStart: frame.number)
    }

    private func stage(_ frame: FDQRFrame) {
        if pendingSessionID != frame.sessionID {
            pendingSessionID = frame.sessionID
            pendingFrames = []
        }
        // The sender repeats metadata within about one second at the default rate. This limit is
        // comfortably above that interval while preventing unbounded memory use on unrelated scans.
        if pendingFrames.count == pendingFrameLimit { pendingFrames.removeFirst() }
        pendingFrames.append(frame)
    }

    private func replayPendingFrames() {
        guard let sessionID, pendingSessionID == sessionID else { pendingFrames = []; pendingSessionID = nil; return }
        let frames = pendingFrames; pendingFrames = []; pendingSessionID = nil
        for frame in frames {
            switch frame.type {
            case .metadata: continue
            case .data: receiveData(frame)
            case .parity: receiveParity(frame)
            }
        }
    }

    // Sender emits one zero-padded XOR frame per 8 data frames. It restores exactly one missing data frame per group.
    private func recoverIfPossible(groupStart: Int) {
        guard let metadata, let parityFrame = parity[groupStart] else { return }
        let end = min(groupStart + metadata.ParityGroupSize, metadata.ChunkCount)
        let missing = (groupStart..<end).filter { chunks[$0] == nil }
        guard missing.count == 1 else { return }
        var restored = [UInt8](parityFrame)
        guard restored.count == metadata.ChunkSize else { return }
        for index in groupStart..<end where index != missing[0] {
            guard let chunk = chunks[index] else { return }
            for (offset, value) in chunk.enumerated() { restored[offset] ^= value }
        }
        let recoveredIndex = missing[0]
        let expectedLength = recoveredIndex == metadata.ChunkCount - 1
            ? Int(metadata.FileSize - Int64(recoveredIndex * metadata.ChunkSize)) : metadata.ChunkSize
        chunks[recoveredIndex] = Data(restored.prefix(expectedLength))
        publishProgressIfNeeded(force: true, message: "已用冗余帧恢复第 \(recoveredIndex + 1) 个分片")
    }

    private func completeIfReady() throws {
        guard let metadata, chunks.count == metadata.ChunkCount, !completed else { return }
        var file = Data(); file.reserveCapacity(Int(metadata.FileSize))
        for index in 0..<metadata.ChunkCount { guard let chunk = chunks[index] else { return }; file.append(chunk) }
        file = Data(file.prefix(Int(metadata.FileSize)))
        let hash = SHA256.hash(data: file).map { String(format: "%02x", $0) }.joined()
        guard hash == metadata.Sha256.lowercased() else { throw FDQRError.hashMismatch }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Received", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = metadata.FileName.replacingOccurrences(of: "/", with: "_")
        let destination = directory.appendingPathComponent(safeName)
        try file.write(to: destination, options: .atomic)
        completedFile = destination; completed = true; receivedCount = metadata.ChunkCount; message = "接收完成，SHA-256 校验通过"
    }

    private func publishProgressIfNeeded(force: Bool = false, message newMessage: String? = nil) {
        let now = Date()
        guard force || now.timeIntervalSince(lastUIRefresh) >= 0.25 else { return }
        lastUIRefresh = now
        receivedCount = chunks.count
        message = newMessage ?? "已缓存后续数据；还差 \(missingCount) 个分片，发送端会在下一轮反向补发"
    }

    private func show(_ text: String) { lastError = text }
}
