import Foundation
import VideoToolbox
import CoreMedia

class AumiVideoDecoder {
    // FIX: was `VTDecompressionSession??` (double optional) — corrected to single optional
    private var decompressionSession: VTDecompressionSession? = nil
    private var formatDescription: CMVideoFormatDescription? = nil

    var onFrameDecoded: ((CVPixelBuffer) -> Void)?

    // MARK: - Public Entry Point
    func decode(data: Data, pts: Int64) {
        // H.264 stream comes in as Annex-B (start codes 0x000001 / 0x00000001).
        // We split on start codes and handle SPS(7), PPS(8), and IDR/non-IDR frames.
        let nalUnits = splitNALUnits(data: data)

        var spsData: Data?
        var ppsData: Data?

        for nal in nalUnits {
            guard !nal.isEmpty else { continue }
            let nalType = nal[0] & 0x1F
            switch nalType {
            case 7: spsData = nal     // Sequence Parameter Set
            case 8: ppsData = nal     // Picture Parameter Set
            default: break
            }
        }

        // If we received SPS + PPS, rebuild the format description
        if let sps = spsData, let pps = ppsData {
            rebuildFormatDescription(sps: sps, pps: pps)
        }

        guard formatDescription != nil else { return }

        // Decode each frame NAL (IDR=5, non-IDR=1)
        for nal in nalUnits {
            guard !nal.isEmpty else { continue }
            let nalType = nal[0] & 0x1F
            if nalType == 1 || nalType == 5 {
                decodeNAL(nal, pts: pts)
            }
        }
    }

    // MARK: - Format Description
    private func rebuildFormatDescription(sps: Data, pps: Data) {
        decompressionSession = nil // Tear down old session
        sps.withUnsafeBytes { spsPtr in
            pps.withUnsafeBytes { ppsPtr in
                let paramSets: [UnsafePointer<UInt8>] = [
                    spsPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    ppsPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
                ]
                let sizes: [Int] = [sps.count, pps.count]
                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: paramSets,
                    parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &formatDescription
                )
            }
        }
        setupSession()
    }

    // MARK: - Decompression Session
    private func setupSession() {
        guard let formatDesc = formatDescription else { return }
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        // FIX: was force-unwrapping decompressionSession before it was created
        VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDesc,
            decoderSpecification: nil,
            imageBufferAttributes: attrs as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &decompressionSession
        )
    }

    // MARK: - Frame Decode
    private func decodeNAL(_ nal: Data, pts: Int64) {
        guard let session = decompressionSession, let formatDesc = formatDescription else { return }

        // Convert Annex-B start code to AVCC 4-byte length prefix
        var lengthPrefixedData = Data(count: nal.count + 4)
        var length = UInt32(nal.count).bigEndian
        lengthPrefixedData.replaceSubrange(0..<4, with: withUnsafeBytes(of: &length) { Data($0) })
        lengthPrefixedData.replaceSubrange(4..., with: nal)

        var blockBuffer: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: lengthPrefixedData.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: lengthPrefixedData.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard let buffer = blockBuffer else { return }
        lengthPrefixedData.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(
                with: $0.baseAddress!, blockBuffer: buffer,
                offsetIntoDestination: 0, dataLength: lengthPrefixedData.count
            )
        }

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: pts, timescale: 1_000_000),
            decodeTimeStamp: .invalid
        )
        CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: buffer,
            formatDescription: formatDesc, sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sizeEntryCount: 0, sizeArray: nil, sampleBufferOut: &sampleBuffer
        )
        guard let sb = sampleBuffer else { return }

        VTDecompressionSessionDecodeFrame(
            session, sampleBuffer: sb,
            flags: [._EnableAsynchronousDecompression],
            frameContext: nil
        ) { [weak self] status, _, imageBuffer, _, _ in
            if status == noErr, let pixelBuffer = imageBuffer {
                self?.onFrameDecoded?(pixelBuffer)
            }
        }
    }

    // MARK: - NAL Unit Splitting (Annex-B)
    private func splitNALUnits(data: Data) -> [Data] {
        var units: [Data] = []
        let bytes = [UInt8](data)
        var start = 0
        var i = 0
        while i < bytes.count - 3 {
            // Detect 3-byte (0x000001) or 4-byte (0x00000001) start codes
            let is4Byte = i + 3 < bytes.count && bytes[i] == 0 && bytes[i+1] == 0 && bytes[i+2] == 0 && bytes[i+3] == 1
            let is3Byte = bytes[i] == 0 && bytes[i+1] == 0 && bytes[i+2] == 1
            if is4Byte || is3Byte {
                if i > start {
                    units.append(Data(bytes[start..<i]))
                }
                start = i + (is4Byte ? 4 : 3)
                i = start
            } else {
                i += 1
            }
        }
        if start < bytes.count {
            units.append(Data(bytes[start...]))
        }
        return units
    }
}
