import Foundation

#if canImport(Metal)
import Metal
#endif

final class ToonMetalStringAccelerator {
    static let shared = ToonMetalStringAccelerator()

    let isAvailable: Bool

#if canImport(Metal)
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let encodeRangesPipelineState: MTLComputePipelineState?
    private let encodeRangesThreadgroupWidth: Int
    private let classifyPipelineState: MTLComputePipelineState?
    private let classifyAlternativePipelineState: MTLComputePipelineState?
    private let classifyThreadgroupWidth: Int
    private let classifyAlternativeThreadgroupWidth: Int
    private let lock = NSLock()
    private var inputBuffer: MTLBuffer?
    private var outputBuffer: MTLBuffer?
    private var rangeStartBuffer: MTLBuffer?
    private var rangeEndBuffer: MTLBuffer?
    private var rangeOffsetBuffer: MTLBuffer?
    private var outputLengthBuffer: MTLBuffer?
    private var outputModeBuffer: MTLBuffer?
    private var encodedStringBuffer: MTLBuffer?
    private var rangeStartsScratch: [UInt32] = []
    private var rangeEndsScratch: [UInt32] = []
    private var rangeOffsetsScratch: [UInt32] = []
    private var bufferCapacity = 0
    private var rangeBufferCapacity = 0
    private var encodedStringBufferCapacity = 0
    // Decode-specific Metal buffers (reuse encode buffers for I/O; access serialised by lock).
    private let decodeTokensPipelineState: MTLComputePipelineState?
    private let decodeTokensThreadgroupWidth: Int
    private var decodeOutputKindBuffer: MTLBuffer?
    private var decodeOutputKindBufferCapacity = 0
#endif

    private init() {
#if canImport(Metal)
        let metalDevice = MTLCreateSystemDefaultDevice()
        device = metalDevice
        commandQueue = metalDevice?.makeCommandQueue()

          if let metalDevice,
              let source = Self.loadCombinedMetalSource(),
           let library = try? metalDevice.makeLibrary(source: source, options: nil),
           let encodeRangesFunction = library.makeFunction(name: "encode_ascii_string_ranges"),
           let classifyFunction = library.makeFunction(name: "classify_ascii_string_characters"),
           let classifyAlternativeFunction = library.makeFunction(name: "classify_ascii_string_characters_alternative"),
           let decodeFunction = library.makeFunction(name: "decode_token_ranges"),
           let encodeRangesState = try? metalDevice.makeComputePipelineState(function: encodeRangesFunction),
           let classifyState = try? metalDevice.makeComputePipelineState(function: classifyFunction),
           let classifyAlternativeState = try? metalDevice.makeComputePipelineState(function: classifyAlternativeFunction),
           let decodeState = try? metalDevice.makeComputePipelineState(function: decodeFunction)
        {
            encodeRangesPipelineState = encodeRangesState
            encodeRangesThreadgroupWidth = max(
                encodeRangesState.threadExecutionWidth,
                min(encodeRangesState.maxTotalThreadsPerThreadgroup, 128)
            )
            classifyPipelineState = classifyState
            classifyAlternativePipelineState = classifyAlternativeState
            classifyThreadgroupWidth = max(classifyState.threadExecutionWidth, min(classifyState.maxTotalThreadsPerThreadgroup, 256))
            classifyAlternativeThreadgroupWidth = max(
                classifyAlternativeState.threadExecutionWidth,
                min(classifyAlternativeState.maxTotalThreadsPerThreadgroup, 256)
            )
            decodeTokensPipelineState = decodeState
            decodeTokensThreadgroupWidth = max(
                decodeState.threadExecutionWidth,
                min(decodeState.maxTotalThreadsPerThreadgroup, 128)
            )
            isAvailable = commandQueue != nil
        } else {
            encodeRangesPipelineState = nil
            encodeRangesThreadgroupWidth = 0
            classifyPipelineState = nil
            classifyAlternativePipelineState = nil
            classifyThreadgroupWidth = 0
            classifyAlternativeThreadgroupWidth = 0
            decodeTokensPipelineState = nil
            decodeTokensThreadgroupWidth = 0
            isAvailable = false
        }
#else
        isAvailable = false
#endif
    }

    func encodeASCIIStringLiterals(
        concatenatedBytes: [UInt8],
        ranges: [ToonASCIIStringRange],
        originalStrings: [String],
        delimiter: UInt8
    ) -> [String]? {
        guard isAvailable, !concatenatedBytes.isEmpty else {
            return nil
        }

        for range in ranges where range.originalIndex < 0 || range.originalIndex >= originalStrings.count {
            return nil
        }

        lock.lock()
        defer { lock.unlock() }

        if let encodedViaRangesKernel = encodeRanges(
            bytes: concatenatedBytes,
            ranges: ranges,
            originalStrings: originalStrings,
            delimiter: delimiter
        ) {
            return encodedViaRangesKernel
        }

        guard let outputPointer = classify(bytes: concatenatedBytes, delimiter: delimiter) else {
            return nil
        }

        var encoded: [String] = []
        encoded.reserveCapacity(ranges.count)

        for range in ranges {
            let originalString = originalStrings[range.originalIndex]
            guard let encodedString = ToonASCIIStringAnalyzer.encode(
                bytes: concatenatedBytes,
                flags: outputPointer,
                range: range,
                originalString: originalString
            ) else {
                return nil
            }
            encoded.append(encodedString)
        }

        return encoded
    }

    private func encodeRanges(
        bytes: [UInt8],
        ranges: [ToonASCIIStringRange],
        originalStrings: [String],
        delimiter: UInt8
    ) -> [String]? {
#if canImport(Metal)
        guard let device,
              let commandQueue,
              let encodeRangesPipelineState,
              !ranges.isEmpty
        else {
            return nil
        }

        let byteLength = bytes.count
        guard prepareBuffers(device: device, minimumCapacity: byteLength),
              let inputBuffer
        else {
            return nil
        }

        _ = bytes.withUnsafeBytes { pointer in
            memcpy(inputBuffer.contents(), pointer.baseAddress!, byteLength)
        }

        ensureScratchCapacity(rangeCount: ranges.count)

        var totalOutputCapacity = 0
        for (index, range) in ranges.enumerated() {
            let start = range.startIndex
            let end = range.endIndex

            guard start >= 0,
                  end >= start,
                  end <= byteLength,
                  start <= Int(UInt32.max),
                  end <= Int(UInt32.max),
                  totalOutputCapacity <= Int(UInt32.max)
            else {
                return nil
            }

            let rangeLength = end - start
            let slotCapacity = (rangeLength * 2) + 2

            guard slotCapacity >= 0,
                  totalOutputCapacity <= (Int(UInt32.max) - slotCapacity)
            else {
                return nil
            }

            rangeStartsScratch[index] = UInt32(start)
            rangeEndsScratch[index] = UInt32(end)
            rangeOffsetsScratch[index] = UInt32(totalOutputCapacity)
            totalOutputCapacity += slotCapacity
        }

        guard prepareRangeBuffers(
                device: device,
                minimumRangeCount: ranges.count,
                minimumEncodedByteCount: totalOutputCapacity
              ),
              let rangeStartBuffer,
              let rangeEndBuffer,
              let rangeOffsetBuffer,
              let outputLengthBuffer,
              let outputModeBuffer,
              let encodedStringBuffer,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            return nil
        }

        let u32Stride = MemoryLayout<UInt32>.size
        _ = rangeStartsScratch.withUnsafeBytes { pointer in
            memcpy(rangeStartBuffer.contents(), pointer.baseAddress!, ranges.count * u32Stride)
        }
        _ = rangeEndsScratch.withUnsafeBytes { pointer in
            memcpy(rangeEndBuffer.contents(), pointer.baseAddress!, ranges.count * u32Stride)
        }
        _ = rangeOffsetsScratch.withUnsafeBytes { pointer in
            memcpy(rangeOffsetBuffer.contents(), pointer.baseAddress!, ranges.count * u32Stride)
        }

        encoder.setComputePipelineState(encodeRangesPipelineState)
        encoder.setBuffer(inputBuffer, offset: 0, index: 0)
        var delimiterValue = delimiter
        encoder.setBytes(&delimiterValue, length: MemoryLayout<UInt8>.size, index: 1)
        encoder.setBuffer(rangeStartBuffer, offset: 0, index: 2)
        encoder.setBuffer(rangeEndBuffer, offset: 0, index: 3)
        encoder.setBuffer(rangeOffsetBuffer, offset: 0, index: 4)
        encoder.setBuffer(encodedStringBuffer, offset: 0, index: 5)
        encoder.setBuffer(outputLengthBuffer, offset: 0, index: 6)
        encoder.setBuffer(outputModeBuffer, offset: 0, index: 7)

        let gridSize = MTLSize(width: ranges.count, height: 1, depth: 1)
        let threadgroupSize = MTLSize(
            width: min(max(encodeRangesThreadgroupWidth, 1), ranges.count),
            height: 1,
            depth: 1
        )
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        guard commandBuffer.status == .completed else {
            return nil
        }

        let outputLengthPointer = outputLengthBuffer.contents().bindMemory(to: UInt32.self, capacity: ranges.count)
        let outputModePointer = outputModeBuffer.contents().bindMemory(to: UInt8.self, capacity: ranges.count)
        let encodedBytePointer = encodedStringBuffer.contents().bindMemory(to: UInt8.self, capacity: totalOutputCapacity)

        var encoded: [String] = []
        encoded.reserveCapacity(ranges.count)

        for index in 0..<ranges.count {
            let encodedLength = outputLengthPointer[index]
            let outputMode = outputModePointer[index]
            guard outputMode != 0xFF else {
                return nil
            }

            if outputMode == 0 {
                encoded.append(originalStrings[ranges[index].originalIndex])
                continue
            }

            if outputMode == 1 {
                encoded.append("\"\(originalStrings[ranges[index].originalIndex])\"")
                continue
            }

            guard outputMode == 2,
                  encodedLength != UInt32.max
            else {
                return nil
            }

            let offset = Int(rangeOffsetsScratch[index])
            let length = Int(encodedLength)
            guard offset >= 0,
                  length >= 0,
                  offset <= totalOutputCapacity,
                  length <= (totalOutputCapacity - offset)
            else {
                return nil
            }

            let buffer = UnsafeBufferPointer(start: encodedBytePointer + offset, count: length)
            encoded.append(String(decoding: buffer, as: UTF8.self))
        }

        return encoded
#else
        _ = bytes
        _ = ranges
        _ = delimiter
        return nil
#endif
    }


    // MARK: - Metal Decode

    /// Classifies and optionally unescapes a batch of token ranges in parallel on the GPU.
    ///
    /// - Returns: One `ToonValue?` per token range; an inner `nil` means the token contains
    ///   non-ASCII bytes and requires CPU handling.
    ///   The outer return is `nil` on Metal failure or unrecoverable input error.
    func decodeTokenRanges(
        concatenatedBytes: [UInt8],
        rangeStarts: [UInt32],
        rangeEnds: [UInt32]
    ) -> [ToonValue?]? {
#if canImport(Metal)
        guard let device,
              let commandQueue,
              let decodeTokensPipelineState,
              !rangeStarts.isEmpty,
              rangeStarts.count == rangeEnds.count
        else { return nil }

        let tokenCount = rangeStarts.count
        let byteCount  = concatenatedBytes.count
        guard byteCount > 0 else { return nil }

        lock.lock()
        defer { lock.unlock() }

        guard prepareBuffers(device: device, minimumCapacity: byteCount),
              let inputBuffer
        else { return nil }

        concatenatedBytes.withUnsafeBytes { ptr in
            memcpy(inputBuffer.contents(), ptr.baseAddress!, byteCount)
        }

        ensureScratchCapacity(rangeCount: tokenCount)

        var totalOutputCapacity = 0
        for i in 0..<tokenCount {
            rangeStartsScratch[i] = rangeStarts[i]
            rangeEndsScratch[i]   = rangeEnds[i]
            let tokenLen = max(Int(rangeEnds[i]) - Int(rangeStarts[i]), 0)
            guard totalOutputCapacity <= Int(UInt32.max) - tokenLen else { return nil }
            rangeOffsetsScratch[i] = UInt32(totalOutputCapacity)
            totalOutputCapacity += tokenLen
        }

        guard prepareRangeBuffers(
            device: device,
            minimumRangeCount: tokenCount,
            minimumEncodedByteCount: max(totalOutputCapacity, 1)
        ),
              let rangeStartBuffer,
              let rangeEndBuffer,
              let rangeOffsetBuffer,
              let outputLengthBuffer,
              let encodedStringBuffer
        else { return nil }

        if tokenCount > decodeOutputKindBufferCapacity {
            decodeOutputKindBuffer = device.makeBuffer(length: tokenCount, options: .storageModeShared)
            decodeOutputKindBufferCapacity = tokenCount
        }
        guard let decodeOutputKindBuffer else { return nil }

        let u32Stride = MemoryLayout<UInt32>.size
        rangeStartsScratch.withUnsafeBytes { ptr in
            memcpy(rangeStartBuffer.contents(), ptr.baseAddress!, tokenCount * u32Stride)
        }
        rangeEndsScratch.withUnsafeBytes { ptr in
            memcpy(rangeEndBuffer.contents(), ptr.baseAddress!, tokenCount * u32Stride)
        }
        rangeOffsetsScratch.withUnsafeBytes { ptr in
            memcpy(rangeOffsetBuffer.contents(), ptr.baseAddress!, tokenCount * u32Stride)
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else { return nil }

        encoder.setComputePipelineState(decodeTokensPipelineState)
        encoder.setBuffer(inputBuffer,            offset: 0, index: 0)
        encoder.setBuffer(rangeStartBuffer,       offset: 0, index: 1)
        encoder.setBuffer(rangeEndBuffer,         offset: 0, index: 2)
        encoder.setBuffer(rangeOffsetBuffer,      offset: 0, index: 3)
        encoder.setBuffer(encodedStringBuffer,    offset: 0, index: 4)
        encoder.setBuffer(outputLengthBuffer,     offset: 0, index: 5)
        encoder.setBuffer(decodeOutputKindBuffer, offset: 0, index: 6)

        let gridSize      = MTLSize(width: tokenCount, height: 1, depth: 1)
        let threadgroupSz = MTLSize(
            width: min(max(decodeTokensThreadgroupWidth, 1), tokenCount),
            height: 1, depth: 1
        )
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSz)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { return nil }

        let kindPtr   = decodeOutputKindBuffer.contents()
            .bindMemory(to: UInt8.self,  capacity: tokenCount)
        let lengthPtr = outputLengthBuffer.contents()
            .bindMemory(to: UInt32.self, capacity: tokenCount)
        let outRawPtr = encodedStringBuffer.contents()
            .bindMemory(to: UInt8.self,  capacity: max(totalOutputCapacity, 1))
        let inRawPtr  = inputBuffer.contents()
            .bindMemory(to: UInt8.self,  capacity: byteCount)

        var results: [ToonValue?] = []
        results.reserveCapacity(tokenCount)

        for i in 0..<tokenCount {
            let kind      = kindPtr[i]
            let rStart    = Int(rangeStarts[i])
            let rEnd      = Int(rangeEnds[i])
            let outOffset = Int(rangeOffsetsScratch[i])
            let outLen    = Int(lengthPtr[i])

            switch kind {
            case 0: // null
                results.append(.null)
            case 1: // bool true
                results.append(.bool(true))
            case 2: // bool false
                results.append(.bool(false))
            case 3: // unquoted string — use original bytes
                let count = max(rEnd - rStart, 0)
                results.append(.string(
                    String(decoding: UnsafeBufferPointer(start: inRawPtr + rStart, count: count),
                           as: UTF8.self)
                ))
            case 4: // quoted no-escape — inner bytes (strip surrounding quotes)
                let innerStart = rStart + 1
                let innerEnd   = max(rEnd - 1, innerStart)
                let count = innerEnd - innerStart
                results.append(.string(
                    String(decoding: UnsafeBufferPointer(start: inRawPtr + innerStart, count: count),
                           as: UTF8.self)
                ))
            case 5: // quoted with escape — unescaped content in output buffer
                guard outLen >= 0,
                      outOffset >= 0,
                      outOffset + outLen <= totalOutputCapacity
                else { return nil }
                results.append(.string(
                    String(decoding: UnsafeBufferPointer(start: outRawPtr + outOffset, count: outLen),
                           as: UTF8.self)
                ))
            case 6: // integer — parse raw bytes on CPU
                let count = max(rEnd - rStart, 0)
                let str = String(decoding: UnsafeBufferPointer(start: inRawPtr + rStart, count: count),
                                 as: UTF8.self)
                guard let intVal = Int64(str) else { return nil }
                results.append(.int(intVal))
            case 7: // double — parse raw bytes on CPU
                let count = max(rEnd - rStart, 0)
                let str = String(decoding: UnsafeBufferPointer(start: inRawPtr + rStart, count: count),
                                 as: UTF8.self)
                guard let dblVal = Double(str),
                      str.contains(".") || str.contains("e") || str.contains("E")
                else { return nil }
                results.append(.double(dblVal))
            case 8: // non-ASCII — signal CPU fallback for this specific token
                results.append(nil)
            default: // 255 = invalid escape sequence — abort entire batch
                return nil
            }
        }
        return results
#else
        _ = concatenatedBytes; _ = rangeStarts; _ = rangeEnds
        return nil
#endif
    }

    private func classify(bytes: [UInt8], delimiter: UInt8) -> UnsafeBufferPointer<UInt8>? {
#if canImport(Metal)
        guard let device,
              let commandQueue,
              let classifyPipelineState,
              let classifyAlternativePipelineState
        else {
            return nil
        }

        let length = bytes.count
        guard prepareBuffers(device: device, minimumCapacity: length),
              let inputBuffer,
              let outputBuffer
        else {
            return nil
        }

        _ = bytes.withUnsafeBytes { pointer in
            memcpy(inputBuffer.contents(), pointer.baseAddress!, length)
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            return nil
        }

        let selectedPipelineState: MTLComputePipelineState
        let selectedThreadgroupWidth: Int
        if length >= 131_072 {
            selectedPipelineState = classifyAlternativePipelineState
            selectedThreadgroupWidth = classifyAlternativeThreadgroupWidth
        } else {
            selectedPipelineState = classifyPipelineState
            selectedThreadgroupWidth = classifyThreadgroupWidth
        }

        encoder.setComputePipelineState(selectedPipelineState)
        encoder.setBuffer(inputBuffer, offset: 0, index: 0)
        var delimiterValue = delimiter
        encoder.setBytes(&delimiterValue, length: MemoryLayout<UInt8>.size, index: 1)
        encoder.setBuffer(outputBuffer, offset: 0, index: 2)

        let gridSize = MTLSize(width: length, height: 1, depth: 1)
        let threadgroupSize = MTLSize(
            width: min(max(selectedThreadgroupWidth, 1), length),
            height: 1,
            depth: 1
        )
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        guard commandBuffer.status == .completed else {
            return nil
        }

        let pointer = outputBuffer.contents().bindMemory(to: UInt8.self, capacity: length)
        return UnsafeBufferPointer(start: pointer, count: length)
#else
        _ = bytes
        _ = delimiter
        return nil
#endif
    }

#if canImport(Metal)
    private func prepareBuffers(device: MTLDevice, minimumCapacity: Int) -> Bool {
        if minimumCapacity > bufferCapacity {
            inputBuffer = device.makeBuffer(length: minimumCapacity, options: .storageModeShared)
            outputBuffer = device.makeBuffer(length: minimumCapacity, options: .storageModeShared)
            bufferCapacity = minimumCapacity
        }

        return inputBuffer != nil && outputBuffer != nil
    }

    private func prepareRangeBuffers(
        device: MTLDevice,
        minimumRangeCount: Int,
        minimumEncodedByteCount: Int
    ) -> Bool {
        if minimumRangeCount > rangeBufferCapacity {
            let bufferByteCount = minimumRangeCount * MemoryLayout<UInt32>.size
            rangeStartBuffer = device.makeBuffer(length: bufferByteCount, options: .storageModeShared)
            rangeEndBuffer = device.makeBuffer(length: bufferByteCount, options: .storageModeShared)
            rangeOffsetBuffer = device.makeBuffer(length: bufferByteCount, options: .storageModeShared)
            outputLengthBuffer = device.makeBuffer(length: bufferByteCount, options: .storageModeShared)
            outputModeBuffer = device.makeBuffer(length: minimumRangeCount, options: .storageModeShared)
            rangeBufferCapacity = minimumRangeCount
        }

        if minimumEncodedByteCount > encodedStringBufferCapacity {
            encodedStringBuffer = device.makeBuffer(length: minimumEncodedByteCount, options: .storageModeShared)
            encodedStringBufferCapacity = minimumEncodedByteCount
        }

        return rangeStartBuffer != nil
            && rangeEndBuffer != nil
            && rangeOffsetBuffer != nil
            && outputLengthBuffer != nil
                && outputModeBuffer != nil
            && encodedStringBuffer != nil
    }

    private func ensureScratchCapacity(rangeCount: Int) {
        if rangeStartsScratch.count < rangeCount {
            rangeStartsScratch = Array(repeating: 0, count: rangeCount)
            rangeEndsScratch = Array(repeating: 0, count: rangeCount)
            rangeOffsetsScratch = Array(repeating: 0, count: rangeCount)
        }
    }

    private static func loadCombinedMetalSource() -> String? {
        let shaderFilenames = [
            "ToonStringShaderCommon",
            "ToonStringClassifyPrimaryKernel",
            "ToonStringClassifyAlternativeKernel",
            "ToonStringEncodeRangesKernel",
            "ToonDecodeTokensKernel",
        ]

        var sources: [String] = []
        sources.reserveCapacity(shaderFilenames.count)

        for name in shaderFilenames {
            guard let sourceURL = Bundle.module.url(forResource: name, withExtension: "metal"),
                  let source = try? String(contentsOf: sourceURL, encoding: .utf8)
            else {
                return nil
            }
            sources.append(source)
        }

        return sources.joined(separator: "\n\n")
    }
#endif
}