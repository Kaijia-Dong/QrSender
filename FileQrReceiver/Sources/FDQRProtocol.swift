import CryptoKit
import Foundation

enum FDQRFrameType: UInt8 { case metadata = 1, data = 2, parity = 3 }

struct FDQRFrame {
    let sessionID: UInt64
    let type: FDQRFrameType
    let number: Int
    let total: Int
    let payload: Data

    static func decode(_ text: String) throws -> FDQRFrame {
        guard text.hasPrefix("FDQR1:") else { throw FDQRError.invalidPrefix }
        var encoded = String(text.dropFirst(6)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded), data.count >= 30 else { throw FDQRError.invalidEncoding }
        guard String(data: data[0..<4], encoding: .ascii) == "FDQR", data[4] == 1,
              let type = FDQRFrameType(rawValue: data[5]) else { throw FDQRError.invalidHeader }
        let payloadLength = Int(data.uint16LE(at: 24))
        guard data.count == 30 + payloadLength else { throw FDQRError.invalidLength }
        let payload = data[30...]
        guard CRC32.compute(Data(payload)) == data.uint32LE(at: 26) else { throw FDQRError.crcMismatch }
        return FDQRFrame(sessionID: data.uint64LE(at: 8), type: type, number: Int(data.uint32LE(at: 16)), total: Int(data.uint32LE(at: 20)), payload: Data(payload))
    }
}


struct FDQRMetadata: Decodable {
    let Magic: String
    let Version: Int
    let FileName: String
    let FileSize: Int64
    let ChunkSize: Int
    let ChunkCount: Int
    let ParityGroupSize: Int
    let Sha256: String
}

enum FDQRError: LocalizedError, Equatable { case invalidPrefix, invalidEncoding, invalidHeader, invalidLength, crcMismatch, invalidMetadata, hashMismatch
    var errorDescription: String? { switch self {
    case .invalidPrefix: return "不是 FDQR 二维码"
    case .invalidEncoding: return "二维码内容无法解码"
    case .invalidHeader: return "FDQR 协议头无效"
    case .invalidLength: return "FDQR 数据长度无效"
    case .crcMismatch: return "二维码数据校验失败"
    case .invalidMetadata: return "文件元数据无效"
    case .hashMismatch: return "文件完整性校验失败"
    }}
}

private extension Data {
    func uint16LE(at offset: Int) -> UInt16 { withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }.littleEndian }
    func uint32LE(at offset: Int) -> UInt32 { withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }.littleEndian }
    func uint64LE(at offset: Int) -> UInt64 { withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self) }.littleEndian }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { seed in
        (0..<8).reduce(UInt32(seed)) { value, _ in value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
    }
    static func compute(_ bytes: Data) -> UInt32 { ~bytes.reduce(0xFFFF_FFFF) { table[Int(($0 ^ UInt32($1)) & 0xFF)] ^ ($0 >> 8) } }
}
