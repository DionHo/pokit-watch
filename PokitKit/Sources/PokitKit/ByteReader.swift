import Foundation

/// Little-endian access to the bytes of a characteristic value.
///
/// `Data` slices keep the indices of the collection they were cut from, so the bytes are
/// copied into a plain array first; offsets are then always zero-based.
struct ByteReader {
    private let bytes: [UInt8]

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    var count: Int { bytes.count }

    func uint8(at offset: Int) -> UInt8 {
        bytes[offset]
    }

    func uint16(at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    func uint32(at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }

    func float32(at offset: Int) -> Float {
        Float(bitPattern: uint32(at: offset))
    }

    func slice(at offset: Int, count: Int) -> [UInt8] {
        Array(bytes[offset..<(offset + count)])
    }
}

extension Data {
    mutating func appendLittleEndian(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }
}
