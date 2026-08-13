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

    func generateThumbnail(
        from url: URL,
        output: URL,
        requestHeaders: [String: String]
    ) async throws {
        try await FFmpegCore.run {
            try FFmpegCore.generateThumbnail(
                from: url,
                output: output,
                requestHeaders: requestHeaders
            )
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
fileprivate enum FFmpegCore {

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
    /// AV_TIME_BASE_Q。
    static let avTimeBaseQ = AVRational(num: 1, den: 1_000_000)

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
        urlString: String,
        requestHeaders: [String: String] = [:],
        isThumbnailProbe: Bool = false
    ) throws -> UnsafeMutablePointer<AVFormatContext> {
        guard avformat_network_init() >= 0 else {
            throw MediaProcessError.ffmpegUnavailable
        }
        var context: UnsafeMutablePointer<AVFormatContext>?
        var options: OpaquePointer?
        defer { av_dict_free(&options) }
        if urlString.contains("://") {
            // Prevent a stalled thumbnail request from occupying the serial
            // media queue indefinitely. FFmpeg uses microseconds here.
            av_dict_set(
                &options,
                "rw_timeout",
                isThumbnailProbe ? "8000000" : "15000000",
                0
            )
            av_dict_set(&options, "reconnect", "1", 0)
            av_dict_set(&options, "reconnect_streamed", "1", 0)
            av_dict_set(&options, "reconnect_delay_max", "2", 0)
            if isThumbnailProbe {
                // A thumbnail only needs enough stream metadata to decode an
                // early key frame. A bounded probe avoids placing several
                // multi-second HLS analyses ahead of the visible main video.
                av_dict_set(&options, "probesize", "262144", 0)
                av_dict_set(&options, "analyzeduration", "1000000", 0)
                av_dict_set(&options, "max_probe_packets", "64", 0)
            }
            applyHTTPHeaders(requestHeaders, to: &options)
        }
        let openResult = avformat_open_input(
            &context,
            urlString,
            nil,
            &options
        )
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

    private static func applyHTTPHeaders(
        _ requestHeaders: [String: String],
        to options: inout OpaquePointer?
    ) {
        var customHeaders: [String] = []
        for (name, rawValue) in requestHeaders.sorted(by: { $0.key < $1.key }) {
            let value = rawValue
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n", with: "")
            guard !value.isEmpty,
                  !name.contains("\r"),
                  !name.contains("\n")
            else { continue }
            if name.caseInsensitiveCompare("User-Agent") == .orderedSame {
                av_dict_set(&options, "user_agent", value, 0)
            } else {
                customHeaders.append("\(name): \(value)")
            }
        }
        guard !customHeaders.isEmpty else { return }
        av_dict_set(
            &options,
            "headers",
            customHeaders.joined(separator: "\r\n") + "\r\n",
            0
        )
    }

    // MARK: - 无损转封装（HLS/TS/FLV/MKV/WebM/MOV/MP4 → 目标容器）

    static func remux(
        source: URL,
        output: URL,
        container: String
    ) throws {
        // DASH（MPD）不走 libavformat 的 dash demuxer（部分预编译包未内置），
        // 统一走自解析 MPD + 分段装配 + mux 的流程。
        if source.pathExtension.lowercased() == "mpd" {
            try processDASH(source: source, output: output)
            return
        }

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
                debugLog(
                    "interleaved_write_frame 失败 stream=\(streamIndex) "
                        + "pts=\(packet.pts) dts=\(packet.dts) duration=\(packet.duration)",
                    code: writeResult
                )
                throw MediaProcessError.remuxFailed
            }
        }
        guard lastReadResult == averrorEOF else {
            debugLog("remux 读取异常", code: lastReadResult)
            throw MediaProcessError.remuxFailed
        }

        av_write_trailer(outputContext)
        avio_closep(&outputContext.pointee.pb)

        guard FileManager.default.fileExists(atPath: output.path) else {
            throw MediaProcessError.remuxFailed
        }
    }

    // MARK: - 音视频合并（DASH 分离流 → 单一 MP4）

    private enum StreamKind {
        case video
        case audio
    }

    private struct StreamMapping {
        let input: UnsafeMutablePointer<AVFormatContext>
        let inputIndex: Int
        let outputIndex: Int
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

        var mappings: [StreamMapping] = []
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
            debugLog("mux 没有可合并的流")
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

        let inputs: [UnsafeMutablePointer<AVFormatContext>?] = [
            videoInput,
            audioInput,
        ]
        var eof = [false, false]
        var pending: [AVPacket?] = [nil, nil]

        while !(eof[0] && eof[1] && pending[0] == nil && pending[1] == nil) {
            // 每个输入各读一个候选包。
            for slot in 0..<2 {
                guard !eof[slot], pending[slot] == nil else { continue }
                guard let context = inputs[slot] else {
                    eof[slot] = true
                    continue
                }
                var candidate = AVPacket()
                let readResult = av_read_frame(context, &candidate)
                if readResult < 0 {
                    eof[slot] = true
                    av_packet_unref(&candidate)
                    continue
                }
                pending[slot] = candidate
            }

            guard let chosenSlot = chooseSlot(
                pending: pending,
                inputs: inputs,
                mappings: mappings
            ) else {
                continue
            }

            guard var packet = pending[chosenSlot] else { continue }
            pending[chosenSlot] = nil
            defer { av_packet_unref(&packet) }

            guard let context = inputs[chosenSlot],
                  let mapping = mappings.first(where: {
                      $0.input == context && $0.inputIndex == Int(packet.stream_index)
                  }),
                  let inputStream = context.pointee.streams?[mapping.inputIndex],
                  let outputStream = outputContext.pointee.streams?[mapping.outputIndex]
            else {
                continue
            }

            av_packet_rescale_ts(
                &packet,
                inputStream.pointee.time_base,
                outputStream.pointee.time_base
            )
            // 关键：必须把包映射到输出流索引（输入流索引与输出流索引可能不同）。
            packet.stream_index = Int32(mapping.outputIndex)
            packet.pos = -1

            let writeResult = av_write_frame(outputContext, &packet)
            guard writeResult == 0 else {
                debugLog(
                    "mux av_write_frame 失败 stream=\(mapping.outputIndex) "
                        + "pts=\(packet.pts) dts=\(packet.dts) duration=\(packet.duration)",
                    code: writeResult
                )
                throw MediaProcessError.muxFailed
            }
        }

        av_write_trailer(outputContext)
        avio_closep(&outputContext.pointee.pb)

        guard FileManager.default.fileExists(atPath: output.path) else {
            throw MediaProcessError.muxFailed
        }
    }

    /// 按全局时间轴（AV_TIME_BASE）选择 dts 更早的候选包；dts 缺失时回退 pts。
    private static func chooseSlot(
        pending: [AVPacket?],
        inputs: [UnsafeMutablePointer<AVFormatContext>?],
        mappings: [StreamMapping]
    ) -> Int? {
        var candidates: [(slot: Int, time: Int64)] = []
        for slot in 0..<2 {
            guard let packet = pending[slot],
                  let context = inputs[slot],
                  let mapping = mappings.first(where: {
                      $0.input == context && $0.inputIndex == Int(packet.stream_index)
                  }),
                  let inputStream = context.pointee.streams?[mapping.inputIndex]
            else {
                continue
            }
            let timeBase = inputStream.pointee.time_base
            let timestamp = packet.dts != avNopts ? packet.dts : packet.pts
            let commonTime = timestamp != avNopts
                ? av_rescale_q(timestamp, timeBase, avTimeBaseQ)
                : 0
            candidates.append((slot, commonTime))
        }
        guard let first = candidates.min(by: {
            if $0.time != $1.time { return $0.time < $1.time }
            return $0.slot < $1.slot
        }) else {
            return nil
        }
        return first.slot
    }

    private static func appendStreams(
        from input: UnsafeMutablePointer<AVFormatContext>,
        kind: StreamKind,
        output: UnsafeMutablePointer<AVFormatContext>,
        mappings: inout [StreamMapping]
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
            mappings.append(StreamMapping(
                input: input,
                inputIndex: index,
                outputIndex: Int(output.pointee.nb_streams) - 1
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

    // MARK: - DASH（MPD 自解析 + 分段装配 + mux）
    //
    // 部分 FFmpeg 预编译包未内置 dash demuxer。这里在 FFmpegProcessor 内部完成
    // MPD 解析、分段下载与装配（init + media 拼接为 fMP4），再交给 mux() 合并，
    // 对外仍然只暴露“FFmpegProcessor 处理 DASH”。

    fileprivate struct DASHRepresentation {
        let id: String
        let isVideo: Bool
        let initializationTemplate: String
        let mediaTemplate: String
        let timescale: Int64
        let startNumber: Int64
        let segmentCount: Int64
    }

    private static func processDASH(source: URL, output: URL) throws {
        let mpdData: Data
        do {
            mpdData = try Data(contentsOf: source)
        } catch {
            debugLog("读取 MPD 失败: \(source.absoluteString)")
            throw MediaProcessError.unsupportedFormat
        }
        guard let parser = DASHManifestParser(data: mpdData),
              let representations = parser.parse()
        else {
            debugLog("MPD 解析失败")
            throw MediaProcessError.unsupportedFormat
        }

        let baseURL = source.deletingLastPathComponent()
        let workDirectory = output.deletingLastPathComponent()
        var videoFile: URL?
        var audioFile: URL?

        for representation in representations {
            let assembledURL = workDirectory
                .appendingPathComponent("dash-\(representation.id).mp4")
            try assemble(
                representation: representation,
                baseURL: baseURL,
                output: assembledURL
            )
            if representation.isVideo {
                videoFile = assembledURL
            } else {
                audioFile = assembledURL
            }
        }

        if let videoFile {
            try mux(
                video: videoFile,
                audio: audioFile,
                output: output,
                container: "mp4"
            )
        } else if let audioFile {
            try remux(source: audioFile, output: output, container: "mp4")
        } else {
            throw MediaProcessError.unsupportedFormat
        }

        // 装配产生的中间 fMP4 立即清理，只保留最终文件。
        if let videoFile { try? FileManager.default.removeItem(at: videoFile) }
        if let audioFile { try? FileManager.default.removeItem(at: audioFile) }
    }

    private static func assemble(
        representation: DASHRepresentation,
        baseURL: URL,
        output: URL
    ) throws {
        guard FileManager.default.createFile(atPath: output.path, contents: nil),
              let handle = FileHandle(forWritingAtPath: output.path)
        else {
            throw MediaProcessError.remuxFailed
        }
        defer { try? handle.close() }

        func resolve(_ template: String, number: Int64? = nil) -> URL {
            var value = template
                .replacingOccurrences(of: "$RepresentationID$", with: representation.id)
            if let number {
                value = value.replacingOccurrences(of: "$Number$", with: "\(number)")
            }
            if let url = URL(string: value, relativeTo: baseURL) {
                return url.absoluteURL
            }
            return baseURL.appendingPathComponent(value)
        }

        // init 段。
        let initData = try fetchData(from: resolve(representation.initializationTemplate))
        handle.write(initData)

        // media 段（按 $Number$ 递增）。
        let end = representation.startNumber + representation.segmentCount
        for number in representation.startNumber..<end {
            let segmentData = try fetchData(from: resolve(
                representation.mediaTemplate,
                number: number
            ))
            handle.write(segmentData)
        }
    }

    private static func fetchData(from url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            debugLog("DASH 分段下载失败: \(url.absoluteString)")
            throw MediaProcessError.remuxFailed
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

    static func generateThumbnail(
        from url: URL,
        output: URL,
        requestHeaders: [String: String] = [:]
    ) throws {
        var input: UnsafeMutablePointer<AVFormatContext>? =
            try openInput(
                urlString: inputURLString(for: url),
                requestHeaders: requestHeaders,
                isThumbnailProbe: true
            )
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
        // Some pages expose several 4K pre-roll playlists before their main
        // stream. FFmpeg's default frame threading can allocate one large
        // frame set per core, which is unnecessary for a single thumbnail and
        // can exceed an iPhone's memory budget. One decoder thread is both
        // predictable and fast enough for the first frame.
        decoderContext!.pointee.thread_count = 1
        guard avcodec_open2(decoderContext!, decoder, nil) >= 0 else {
            debugLog("解码器打开失败")
            throw MediaProcessError.thumbnailFailed
        }

        let sourceWidth = max(1, Int(codecpar.pointee.width))
        let sourceHeight = max(1, Int(codecpar.pointee.height))
        let targetWidth = 320
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
        guard av_frame_get_buffer(scaled!, 32) >= 0 else {
            debugLog("av_frame_get_buffer 失败")
            return false
        }
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
        encoderContext!.pointee.time_base = AVRational(num: 1, den: 25)
        // 使用编码器支持的首个像素格式（MJPEG 通常为 yuv420p/yuvj420p）。
        if let supported = encoder.pointee.pix_fmts,
           supported.pointee != AV_PIX_FMT_NONE {
            encoderContext!.pointee.pix_fmt = supported.pointee
        } else {
            encoderContext!.pointee.pix_fmt = AV_PIX_FMT_YUV420P
        }
        let openResult = avcodec_open2(encoderContext!, encoder, nil)
        guard openResult >= 0 else {
            debugLog("MJPEG 编码器打开失败", code: openResult)
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

// MARK: - DASH MPD 解析器（Foundation XMLParser）

/// 解析静态 DASH MPD 的常用结构：
/// MPD → Period → AdaptationSet → Representation + SegmentTemplate(+SegmentTimeline)。
/// 支持 `$RepresentationID$` / `$Number$` 模板与 SegmentTimeline 的段数量计算。
private final class DASHManifestParser: NSObject, XMLParserDelegate {

    private struct RepresentationAttributes {
        var id = ""
        var isVideo = false
        var initialization = ""
        var media = ""
        var timescale: Int64 = 1
        var startNumber: Int64 = 1
        var segmentDurationTotal: Int64 = 0
        var segmentCount: Int64 = 0
    }

    private let parser: XMLParser
    private var representations: [RepresentationAttributes] = []
    private var currentRepresentation: RepresentationAttributes?
    private var currentAdaptationContentType = ""
    private var currentAdaptationMimeType = ""
    private var inSegmentTemplate = false
    private var inSegmentTimeline = false
    private var timelineEntryDuration: Int64 = 0
    private var timelineEntryCount: Int64 = 0

    init?(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
    }

    func parse() -> [FFmpegCore.DASHRepresentation]? {
        guard parser.parse() else { return nil }
        var result: [FFmpegCore.DASHRepresentation] = []
        for attributes in representations {
            guard attributes.segmentCount > 0 else { continue }
            result.append(FFmpegCore.DASHRepresentation(
                id: attributes.id,
                isVideo: attributes.isVideo,
                initializationTemplate: attributes.initialization,
                mediaTemplate: attributes.media,
                timescale: attributes.timescale,
                startNumber: attributes.startNumber,
                segmentCount: attributes.segmentCount
            ))
        }
        return result.isEmpty ? nil : result
    }

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "AdaptationSet":
            currentAdaptationContentType = attributeDict["contentType"] ?? ""
            currentAdaptationMimeType = attributeDict["mimeType"] ?? ""
        case "Representation":
            var attributes = RepresentationAttributes()
            attributes.id = attributeDict["id"] ?? ""
            attributes.isVideo =
                (attributeDict["mimeType"] ?? "").contains("video")
                || currentAdaptationContentType == "video"
                || currentAdaptationMimeType.contains("video")
            currentRepresentation = attributes
        case "SegmentTemplate":
            inSegmentTemplate = true
            if var representation = currentRepresentation {
                representation.initialization = attributeDict["initialization"] ?? ""
                representation.media = attributeDict["media"] ?? ""
                representation.timescale = Int64(attributeDict["timescale"] ?? "") ?? 1
                representation.startNumber = Int64(attributeDict["startNumber"] ?? "") ?? 1
                currentRepresentation = representation
            }
        case "SegmentTimeline":
            inSegmentTimeline = true
        case "S":
            if inSegmentTimeline {
                let duration = Int64(attributeDict["d"] ?? "") ?? 0
                let repeatCount = Int64(attributeDict["r"] ?? "") ?? 0
                timelineEntryDuration = max(0, duration)
                timelineEntryCount = max(0, repeatCount) + 1
            }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "Representation":
            if var representation = currentRepresentation {
                representation.segmentDurationTotal += timelineEntryDuration * timelineEntryCount
                representation.segmentCount += timelineEntryCount
                timelineEntryDuration = 0
                timelineEntryCount = 0
                representations.append(representation)
            }
            currentRepresentation = nil
        case "SegmentTemplate":
            inSegmentTemplate = false
        case "SegmentTimeline":
            inSegmentTimeline = false
        default:
            break
        }
    }
}

#endif
