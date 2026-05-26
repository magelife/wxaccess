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

    return try input.withUnsafeBytes { inputPtr in
        guard let inputBase = inputPtr.baseAddress else { throw BZip2Error.emptyInput }

        var stream = bz_stream()
        var result = BZ2_bzDecompressInit(&stream, 0, 0)
        guard result == BZ_OK else { throw BZip2Error.decompressionFailed(result) }
        defer { BZ2_bzDecompressEnd(&stream) }

        stream.next_in = UnsafeMutableRawPointer(mutating: inputBase)
            .assumingMemoryBound(to: CChar.self)
        stream.avail_in = UInt32(input.count)

        var output = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        let chunkSize = chunk.count

        repeat {
            result = chunk.withUnsafeMutableBytes { outputPtr in
                stream.next_out = outputPtr.baseAddress?.assumingMemoryBound(to: CChar.self)
                stream.avail_out = UInt32(chunkSize)
                return BZ2_bzDecompress(&stream)
            }

            let produced = chunkSize - Int(stream.avail_out)
            if produced > 0 {
                output.append(contentsOf: chunk.prefix(produced))
            }

            if result == BZ_STREAM_END {
                return output
            }

            guard result == BZ_OK else {
                throw BZip2Error.decompressionFailed(result)
            }

            if stream.avail_in == 0 && produced == 0 {
                throw BZip2Error.decompressionFailed(result)
            }
        } while true
    }
}
