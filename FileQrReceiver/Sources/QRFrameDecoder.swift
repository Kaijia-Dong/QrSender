import Foundation

/// A single, latest-frame-wins decode lane. It prevents high camera rates from building a backlog
/// of obsolete QR strings, while preserving the order of frames that are actually decoded.
final class QRFrameDecoder {
    private typealias Pending = (text: String, completion: (Result<FDQRFrame, Error>) -> Void)
    private let queue = DispatchQueue(label: "com.fileqrsender.receiver.frame-decoder", qos: .userInitiated)
    private var pending: Pending?
    private var isDecoding = false

    func submit(_ text: String, completion: @escaping (Result<FDQRFrame, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            // If the scanner outpaces decoding, retain only the newest frame. Old frames will be
            // replayed by the sender anyway; processing them late only makes the receiver lag more.
            pending = (text, completion)
            guard !isDecoding else { return }
            isDecoding = true
            decodeNext()
        }
    }

    private func decodeNext() {
        guard let next = pending else { isDecoding = false; return }
        pending = nil
        let result: Result<FDQRFrame, Error>
        do { result = .success(try FDQRFrame.decode(next.text)) }
        catch { result = .failure(error) }
        DispatchQueue.main.async { next.completion(result) }
        queue.async { [weak self] in self?.decodeNext() }
    }
}
