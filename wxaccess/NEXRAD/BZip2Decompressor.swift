import Foundation

enum BZip2Error: Error, LocalizedError {
    case decompressionFailed(Int32)
    case emptyInput

    var errorDescription: String? {
        switch self {
        case .decompressionFailed(let code): "BZip2 decompression failed (code \(code))"
        case .emptyInput: "BZip2 input was empty"
        }
    }
}

func bzip2Decompress(_ input: Data) throws -> Data {
    guard !input.isEmpty else { throw BZip2Error.emptyInput }

    // Allocate a generous output buffer; NEXRAD LDM blocks decompress ~5-8x.
    // Retry with larger buffer if BZ_OUTBUFF_FULL is returned.
    var multiplier = 8
    while multiplier <= 64 {
        var outputSize = UInt32(input.count * multiplier)
        var output = Data(count: Int(outputSize))
        let result = input.withUnsafeBytes { inputPtr -> Int32 in
            output.withUnsafeMutableBytes { outputPtr -> Int32 in
                BZ2_bzBuffToBuffDecompress(
                    outputPtr.baseAddress?.assumingMemoryBound(to: CChar.self),
                    &outputSize,
                    UnsafeMutableRawPointer(mutating: inputPtr.baseAddress)?
                        .assumingMemoryBound(to: CChar.self),
                    UInt32(input.count),
                    0,  // small: use standard (not low-memory) decompressor
                    0   // verbosity: silent
                )
            }
        }
        if result == BZ_OK {
            return output.prefix(Int(outputSize))
        }
        if result == BZ_OUTBUFF_FULL {
            multiplier *= 2
            continue
        }
        throw BZip2Error.decompressionFailed(result)
    }
    throw BZip2Error.decompressionFailed(BZ_OUTBUFF_FULL)
}
