import AVFoundation
import SwiftUI

struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerController { ScannerController(onCode: onCode) }
    func updateUIViewController(_ controller: ScannerController, context: Context) {}
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let onCode: (String) -> Void
    private let metadataQueue = DispatchQueue(label: "com.fileqrsender.receiver.scanner", qos: .userInitiated)
    private var lastValue = ""
    private var lastTime = Date.distantPast

    init(onCode: @escaping (String) -> Void) { self.onCode = onCode; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() { super.viewDidLoad(); configure() }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); view.layer.sublayers?.compactMap { $0 as? AVCaptureVideoPreviewLayer }.forEach { $0.frame = view.bounds } }
    private func configure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async { self?.configureSession() }
            }
        default: break
        }
    }
    private func configureSession() {
        guard session.inputs.isEmpty else { return }
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput(); guard session.canAddOutput(output) else { return }; session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: metadataQueue); output.metadataObjectTypes = [.qr]
        let preview = AVCaptureVideoPreviewLayer(session: session); preview.videoGravity = .resizeAspectFill; view.layer.addSublayer(preview)
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let value = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        let now = Date(); guard value != lastValue || now.timeIntervalSince(lastTime) > 0.15 else { return }
        lastValue = value; lastTime = now
        // Keep capture/decode scheduling off this callback queue; hand only the string to SwiftUI.
        DispatchQueue.main.async { [onCode] in onCode(value) }
    }
}
