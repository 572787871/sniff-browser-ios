import Foundation

// MARK: - 正式媒体引擎（libav C API）

/// 使用捆绑 FFmpeg libav XCFrameworks 的正式实现。
/// 仅当 `FFMPEG_ENABLED`（GitHub Actions 正式构建）时编译；
/// 本地无 FFmpeg 的构建由 StubFFmpegProcessor 兜底。
#if FFMPEG_ENABLED

struct FFmpegLibraryProcessor: FFmpegProcessor {

    func remux(source: URL, output: URL, container: String) async throws {
        try await FFmpegCore.run {
            try FFmpegCore.remux(source: source, output: output, container: container)
        }
    }

    func mux(video: URL, audio: URL?, output: URL, container: String) async throws {
        try await FFmpegCore.run {
            try FFmpegCore.mux(
                video: video,
                audio: audio,
                output: output,
                container: container
            )
        }
    }

    func processRemote(source: URL, output: URL, container: String) async throws {
        try await FFmpegCore.run {
            try FFmpegCore.remux(source: source, output: output, container: container)
        }
    }

    func extractMetadata(from url: URL) async throws -> MediaAssetInfo {
        try await FFmpegCore.run {
            try FFmpegCore.extractMetadata(from: url)
        }
    }

    func generateThumbnail(from url: URL, output: URL) async throws {
        try await FFmpegCore.run {
            try FFmpegCore.generateThumbnail(from: url, output: output)
        }
    }
}

/// libav* 桥接核心：所有 C 调用集中在后台串行队列执行，不阻塞 UI。
///
/// Swift 互操作约定（与 libav 头文件一一对应）：
/// - 完整结构体（AVFormatContext / AVStream / AVCodecContext / AVFrame /
///   AVCodecParameters）以命名类型导入；
/// - 不透明结构体（AVDictionary / AVCodec / SwsContext）以 `OpaquePointer` 导入；
/// - 释放类 API 接收 `Type **`，因此上下文一律用可选指针变量持有，
///   使用时以 `!` 取出。
private enum FFmpegCore {

    static let queue = DispatchQueue(
        label: "com.sniffbrowser.ffmpeg",
        qos: .userInitiated
    )

    /// AVERROR_EOF（宏未导入 Swift，这里固化常量）。
    static let averrorEOF: Int32 = -541_478_725
    /// AV_NOPTS_VALUE。
    static let avNopts: Int64 = Int64.min
    /// AV_TIME_BASE。
    static let avTimeBase: Double = 1_000_000

    static func run<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try body())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func inputURLString(for url: URL) -> String {
        url.isFileURL ? url.path : url.absoluteString
    }

    /// DEBUG 诊断：输出 libav 错误信息，便于定位媒体处理失败点。
    static func debugLog(_ message: String, code: Int32? = nil) {
        #if DEBUG
        if let code {
            print("[FFmpegCore] \(message): \(code) (\(errorText(code)))")
        } else {
            print("[FFmpegCore] \(message)")
        }
        #endif
    }

    static func errorText(_ code: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        av_strerror(code, &buffer, buffer.count)
        return String(cString: buffer)
    }

    // MARK: - 输入上下文

    private static func openInput(
        urlString: String
    ) throws -> UnsafeMutablePointer<AVFormatContext> {
        guard avformat_network_init() >= 0 else {
            throw MediaProcessError.ffmpegUnavailable
        }
        var context: UnsafeMutablePointer<AVFormatContext>?
        let openResult = avformat_open_input(&context, urlString, nil, nil)
        guard openResult == 0 else {
            debugLog("openInput 打开失败: \(urlString)", code: openResult)
            throw MediaProcessError.unsupportedFormat
        }
        guard let opened = context else {
            debugLog("openInput 返回空上下文")
            throw MediaProcessError.unsupportedFormat
        }
        let infoResult = avformat_find_stream_info(opened, nil)
        guard infoResult == 0 else {
            debugLog("find_stream_info 失败", code: infoResult)
            avformat_close_input(&context)
            throw MediaProcessError.metadataFailed
        }
        return opened
    }

    // MARK: - 无损转封装（HLS/TS/FLV/MKV/WebM/MOV → 目标容器）

    static func remux(
        source: URL,
        output: URL,
        container: String
    ) throws {
        var input: UnsafeMutablePointer<AVFormatContext>? =
            try openInput(urlString: inputURLString(for: source))
        defer { avformat_close_input(&input) }

        var options: OpaquePointer?
        defer { av_dict_free(&options) }
        av_dict_set(&options, "movflags", "faststart", 0)

        var outputContext: UnsafeMutablePointer<AVFormatContext>?
        let allocResult = avformat_alloc_output_context2(
            &outputContext,
            nil,
            container,
            output.path
        )
        guard allocResult == 0, let outputContext else {
            debugLog("alloc_output_context 失败: container=\(container)", code: allocResult)
            throw MediaProcessError.remuxFailed
        }
        defer { avformat_free_context(outputContext) }

        guard let inputStreams = input!.pointee.streams else {
            throw MediaProcessError.remuxFailed
        }
        for index in 0..<Int(input!.pointee.nb_streams) {
            guard let inputStream = inputStreams[index] else { continue }
            guard let outputStream = avformat_new_stream(outputContext, nil) else {
                throw MediaProcessError.remuxFailed
            }
            if let inputCodecpar = inputStream.pointee.codecpar,
               let outputCodecpar = outputStream.pointee.codecpar {
                avcodec_parameters_copy(outputCodecpar, inputCodecpar)
                // MP4 不需要 codec_tag，避免与容器默认标签冲突。
                outputCodecpar.pointee.codec_tag = 0
            }
            outputStream.pointee.time_base = inputStream.pointee.time_base
            outputStream.pointee.avg_frame_rate = inputStream.pointee.avg_frame_rate
        }

        try openOutputIfNeeded(
            outputContext: outputContext,
            outputURL: output.path
        )

        let headerResult = avformat_write_header(outputContext, &options)
        guard headerResult == 0 else {
            debugLog("write_header 失败", code: headerResult)
            throw MediaProcessError.remuxFailed
        }

        var packet = AVPacket()
        var lastReadResult: Int32 = 0
        while true {
            lastReadResult = av_read_frame(input!, &packet)
            if lastReadResult < 0 { break }
            defer { av_packet_unref(&packet) }

            let streamIndex = Int(packet.stream_index)
            guard streamIndex < Int(outputContext.pointee.nb_streams),
                  let inputStream = inputStreams[streamIndex],
                  let outputStream = outputContext.pointee.streams?[streamIndex]
            else {
                continue
            }
            av_packet_rescale_ts(
                &packet,
                inputStream.pointee.time_base,
                outputStream.pointee.time_base
            )
            packet.pos = -1
            let writeResult = av_interleaved_write_frame(outputContext, &packet)
            guard writeResult == 0 else {
                debugLog("interleaved_write_frame 失败 stream=\(streamIndex)", code: writeResult)
                throw MediaProcessError.remuxFailed
            }
        }
        guard lastReadResult == averrorEOF else {
            throw MediaProcessError.remuxFailed
        }

        av_write_trailer(outputContext)
        avio_closep(&outputContext.pointee.pb)

        guard FileManager.default.fileExists(atPath: output.path) else {
            throw MediaProcessError.remuxFailed
        }
    }

    // MARK: - DASH 音视频流合并

    private enum StreamKind {
        case video
        case audio
    }

    static func mux(
        video: URL,
        audio: URL?,
        output: URL,
        container: String
    ) throws {
        var videoInput: UnsafeMutablePointer<AVFormatContext>? =
            try openInput(urlString: video.path)
        defer { avformat_close_input(&videoInput) }

        var audioInput: UnsafeMutablePointer<AVFormatContext>?
        if let audio, FileManager.default.fileExists(atPath: audio.path) {
            audioInput = try openInput(urlString: audio.path)
        }
        // 无条件 defer：audioInput 为 nil 时 avformat_close_input 也是安全的。
        defer { avformat_close_input(&audioInput) }

        var options: OpaquePointer?
        defer { av_dict_free(&options) }
        av_dict_set(&options, "movflags", "faststart", 0)

        var outputContext: UnsafeMutablePointer<AVFormatContext>?
        let allocResult = avformat_alloc_output_context2(
            &outputContext,
            nil,
            container,
            output.path
        )
        guard allocResult == 0, let outputContext else {
            debugLog("mux alloc_output_context 失败", code: allocResult)
            throw MediaProcessError.muxFailed
        }
        defer { avformat_free_context(outputContext) }

        var mappings: [
            (input: UnsafeMutablePointer<AVFormatContext>, inputIndex: Int, outputIndex: Int)
        ] = []
        try appendStreams(
            from: videoInput!,
            kind: .video,
            output: outputContext,
            mappings: &mappings
        )
        if let audioInput {
            try appendStreams(
                from: audioInput,
                kind: .audio,
                output: outputContext,
                mappings: &mappings
            )
        }
        guard !mappings.isEmpty else {
            throw MediaProcessError.muxFailed
        }

        try openOutputIfNeeded(
            outputContext: outputContext,
            outputURL: output.path
        )

        let headerResult = avformat_write_header(outputContext, &options)
        guard headerResult == 0 else {
            debugLog("mux write_header 失败", code: headerResult)
            throw MediaProcessError.muxFailed
        }

        var eof = [false, false]
        var packets: [AVPacket?] = [nil, nil]
        while !(eof[0] && eof[1] && packets[0] == nil && packets[1] == nil) {
            for slot in 0..<2 {
                guard !eof[slot] else { continue }
                let slotContext: UnsafeMutablePointer<AVFormatContext>? =
                    slot == 0 ? videoInput : audioInput
                guard let slotContext, packets[slot] == nil else { continue }
                var candidate = AVPacket()
                let readResult = av_read_frame(slotContext, &candidate)
                if readResult < 0 {
                    eof[slot] = true
                    av_packet_unref(&candidate)
                    continue
                }
                packets[slot] = candidate
            }

            let chosenSlot: Int
            if let first = packets[0], let second = packets[1] {
                chosenSlot = chooseEarlierPacket(first, second) ? 0 : 1
            } else if packets[0] != nil {
                chosenSlot = 0
            } else if packets[1] != nil {
                chosenSlot = 1
            } else {
                continue
            }

            guard var packet = packets[chosenSlot] else { continue }
            packets[chosenSlot] = nil
            defer { av_packet_unref(&packet) }

            let context: UnsafeMutablePointer<AVFormatContext> =
                chosenSlot == 0 ? videoInput! : audioInput!
            guard let mapping = mappings.first(where: {
                $0.input == context && $0.inputIndex == Int(packet.stream_index)
            }) else {
                continue
            }
            guard let inputStream = context.pointee.streams?[mapping.inputIndex],
                  let outputStream = outputContext.pointee.streams?[mapping.outputIndex]
            else {
                continue
            }
            av_packet_rescale_ts(
                &packet,
                inputStream.pointee.time_base,
                outputStream.pointee.time_base
            )
            packet.pos = -1
            let writeResult = av_interleaved_write_frame(outputContext, &packet)
            guard writeResult == 0 else {
                debugLog("mux interleaved_write_frame 失败 slot=\(chosenSlot)", code: writeResult)
                throw MediaProcessError.muxFailed
            }
        }

        av_write_trailer(outputContext)
        avio_closep(&outputContext.pointee.pb)

        guard FileManager.default.fileExists(atPath: output.path) else {
            throw MediaProcessError.muxFailed
        }
    }

    private static func chooseEarlierPacket(_ first: AVPacket, _ second: AVPacket) -> Bool {
        if first.pts == avNopts && second.pts == avNopts { return true }
        if first.pts == avNopts { return false }
        if second.pts == avNopts { return true }
        return first.pts <= second.pts
    }

    private static func appendStreams(
        from input: UnsafeMutablePointer<AVFormatContext>,
        kind: StreamKind,
        output: UnsafeMutablePointer<AVFormatContext>,
        mappings: inout [
            (input: UnsafeMutablePointer<AVFormatContext>, inputIndex: Int, outputIndex: Int)
        ]
    ) throws {
        guard let inputStreams = input.pointee.streams else { return }
        for index in 0..<Int(input.pointee.nb_streams) {
            guard let inputStream = inputStreams[index],
                  let codecpar = inputStream.pointee.codecpar
            else {
                continue
            }
            let isVideo = codecpar.pointee.codec_type == AVMEDIA_TYPE_VIDEO
            let isAudio = codecpar.pointee.codec_type == AVMEDIA_TYPE_AUDIO
            let matches = kind == .video ? isVideo : isAudio
            guard matches else { continue }

            guard let outputStream = avformat_new_stream(output, nil) else {
                throw MediaProcessError.muxFailed
            }
            if let outputCodecpar = outputStream.pointee.codecpar {
                avcodec_parameters_copy(outputCodecpar, codecpar)
                outputCodecpar.pointee.codec_tag = 0
            }
            outputStream.pointee.time_base = inputStream.pointee.time_base
            outputStream.pointee.avg_frame_rate = inputStream.pointee.avg_frame_rate
            mappings.append((
                input,
                index,
                Int(output.pointee.nb_streams) - 1
            ))
        }
    }

    private static func openOutputIfNeeded(
        outputContext: UnsafeMutablePointer<AVFormatContext>,
        outputURL: String
    ) throws {
        guard let oformat = outputContext.pointee.oformat else {
            debugLog("输出上下文缺少 oformat")
            throw MediaProcessError.unsupportedFormat
        }
        if oformat.pointee.flags & AVFMT_NOFILE == 0 {
            let openResult = avio_open(
                &outputContext.pointee.pb,
                outputURL,
                AVIO_FLAG_WRITE
            )
            guard openResult == 0 else {
                debugLog("avio_open 失败: \(outputURL)", code: openResult)
                throw MediaProcessError.unsupportedFormat
            }
        }
    }

    // MARK: - 元数据（ffprobe 等价能力）

    static func extractMetadata(from url: URL) throws -> MediaAssetInfo {
        var input: UnsafeMutablePointer<AVFormatContext>? =
            try openInput(urlString: inputURLString(for: url))
        defer { avformat_close_input(&input) }

        var duration: TimeInterval = 0
        if input!.pointee.duration != avNopts {
            duration = Double(input!.pointee.duration) / avTimeBase
        }
        let bitrate: Double = input!.pointee.bit_rate > 0
            ? Double(input!.pointee.bit_rate)
            : 0

        var width = 0
        var height = 0
        let videoIndex = av_find_best_stream(
            input!,
            AVMEDIA_TYPE_VIDEO,
            -1,
            -1,
            nil,
            0
        )
        if videoIndex >= 0,
           let streams = input!.pointee.streams,
           let stream = streams[Int(videoIndex)],
           let codecpar = stream.pointee.codecpar {
            width = Int(codecpar.pointee.width)
            height = Int(codecpar.pointee.height)
        }

        let size: Int64 = (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        guard duration > 0 || width > 0 else {
            debugLog("元数据缺失 duration=\(duration) width=\(width)")
            throw MediaProcessError.metadataFailed
        }
        return MediaAssetInfo(
            duration: duration,
            width: width,
            height: height,
            estimatedBitrate: bitrate,
            fileSizeBytes: size
        )
    }

    // MARK: - 封面（解码首帧 → 缩放 → JPEG）

    static func generateThumbnail(from url: URL, output: URL) throws {
        var input: UnsafeMutablePointer<AVFormatContext>? =
            try openInput(urlString: url.path)
        defer { avformat_close_input(&input) }

        let videoIndex = av_find_best_stream(
            input!,
            AVMEDIA_TYPE_VIDEO,
            -1,
            -1,
            nil,
            0
        )
        guard videoIndex >= 0,
              let streams = input!.pointee.streams,
              let stream = streams[Int(videoIndex)],
              let codecpar = stream.pointee.codecpar
        else {
            throw MediaProcessError.thumbnailFailed
        }

        guard let decoder = avcodec_find_decoder(codecpar.pointee.codec_id) else {
            debugLog("未找到解码器 codec_id=\(codecpar.pointee.codec_id.rawValue)")
            throw MediaProcessError.thumbnailFailed
        }
        var decoderContext: UnsafeMutablePointer<AVCodecContext>? =
            avcodec_alloc_context3(decoder)
        guard decoderContext != nil else {
            throw MediaProcessError.thumbnailFailed
        }
        defer { avcodec_free_context(&decoderContext) }
        guard avcodec_parameters_to_context(decoderContext!, codecpar) >= 0 else {
            debugLog("parameters_to_context 失败")
            throw MediaProcessError.thumbnailFailed
        }
        decoderContext!.pointee.pkt_timebase = stream.pointee.time_base
        guard avcodec_open2(decoderContext!, decoder, nil) >= 0 else {
            debugLog("解码器打开失败")
            throw MediaProcessError.thumbnailFailed
        }

        let sourceWidth = max(1, Int(codecpar.pointee.width))
        let sourceHeight = max(1, Int(codecpar.pointee.height))
        let targetWidth = 480
        let targetHeight = max(
            1,
            Int((Double(targetWidth) * Double(sourceHeight) / Double(sourceWidth)).rounded())
        )

        var frame: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
        guard frame != nil else {
            throw MediaProcessError.thumbnailFailed
        }
        defer { av_frame_free(&frame) }

        var packet = AVPacket()
        var succeeded = false
        while av_read_frame(input!, &packet) >= 0 {
            defer { av_packet_unref(&packet) }
            guard Int(packet.stream_index) == Int(videoIndex) else { continue }
            if avcodec_send_packet(decoderContext!, &packet) == 0 {
                while avcodec_receive_frame(decoderContext!, frame!) == 0 {
                    succeeded = writeJPEG(
                        frame: frame!,
                        targetWidth: targetWidth,
                        targetHeight: targetHeight,
                        output: output
                    )
                    break
                }
            }
            if succeeded { break }
        }
        guard succeeded else {
            debugLog("未成功解码视频帧")
            throw MediaProcessError.thumbnailFailed
        }
    }

    private static func writeJPEG(
        frame: UnsafeMutablePointer<AVFrame>,
        targetWidth: Int,
        targetHeight: Int,
        output: URL
    ) -> Bool {
        let sourceFormat = AVPixelFormat(rawValue: frame.pointee.format)
        guard let scaler = sws_getCachedContext(
            nil,
            Int32(frame.pointee.width),
            Int32(frame.pointee.height),
            sourceFormat,
            Int32(targetWidth),
            Int32(targetHeight),
            AV_PIX_FMT_YUV420P,
            SWS_BILINEAR,
            nil,
            nil,
            nil
        ) else {
            debugLog("sws_getCachedContext 失败 format=\(frame.pointee.format)")
            return false
        }
        defer { sws_freeContext(scaler) }

        var scaled: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
        guard scaled != nil else { return false }
        defer { av_frame_free(&scaled) }
        scaled!.pointee.width = Int32(targetWidth)
        scaled!.pointee.height = Int32(targetHeight)
        scaled!.pointee.format = Int32(AV_PIX_FMT_YUV420P.rawValue)
        guard av_frame_get_buffer(scaled!, 32) >= 0 else { return false }
        guard sws_scale_frame(scaler, scaled!, frame) >= 0 else {
            debugLog("sws_scale_frame 失败")
            return false
        }

        guard let encoder = avcodec_find_encoder(AV_CODEC_ID_MJPEG) else {
            debugLog("未找到 MJPEG 编码器")
            return false
        }
        var encoderContext: UnsafeMutablePointer<AVCodecContext>? =
            avcodec_alloc_context3(encoder)
        guard encoderContext != nil else {
            return false
        }
        defer { avcodec_free_context(&encoderContext) }
        encoderContext!.pointee.width = Int32(targetWidth)
        encoderContext!.pointee.height = Int32(targetHeight)
        encoderContext!.pointee.pix_fmt = AV_PIX_FMT_YUV420P
        encoderContext!.pointee.time_base = AVRational(num: 1, den: 25)
        guard avcodec_open2(encoderContext!, encoder, nil) >= 0 else {
            debugLog("MJPEG 编码器打开失败")
            return false
        }

        guard avcodec_send_frame(encoderContext!, scaled!) >= 0 else {
            debugLog("send_frame 失败")
            return false
        }

        guard FileManager.default.createFile(atPath: output.path, contents: nil),
              let handle = FileHandle(forWritingAtPath: output.path)
        else {
            return false
        }
        defer { try? handle.close() }

        var encoded = AVPacket()
        var wroteAny = false
        while avcodec_receive_packet(encoderContext!, &encoded) >= 0 {
            defer { av_packet_unref(&encoded) }
            if encoded.size > 0, let data = encoded.data {
                handle.write(Data(bytes: data, count: Int(encoded.size)))
                wroteAny = true
            }
        }
        if !wroteAny {
            debugLog("MJPEG 未产出数据包")
        }
        return wroteAny
    }
}

#endif
