#ifndef SniffBrowser_Bridging_Header_h
#define SniffBrowser_Bridging_Header_h

// FFmpeg libav C API。
//
// 正式构建（GitHub Actions 已装配 vendor/FFmpegHeaders）时导入完整 libav 头文件；
// 本地开发无 FFmpeg 时 __has_include 自动跳过，保证项目可编译。

#if __has_include(<libavutil/avutil.h>)
#include <libavutil/avutil.h>
#include <libavutil/avassert.h>
#include <libavutil/dict.h>
#include <libavutil/error.h>
#include <libavutil/frame.h>
#include <libavutil/mem.h>
#include <libavutil/opt.h>
#include <libavutil/pixfmt.h>
#include <libavutil/rational.h>
#include <libavutil/samplefmt.h>
#endif

#if __has_include(<libavcodec/avcodec.h>)
#include <libavcodec/avcodec.h>
#include <libavcodec/codec.h>
#include <libavcodec/codec_par.h>
#include <libavcodec/packet.h>
#endif

#if __has_include(<libavformat/avformat.h>)
#include <libavformat/avformat.h>
#include <libavformat/avio.h>
#endif

#if __has_include(<libswscale/swscale.h>)
#include <libswscale/swscale.h>
#endif

#if __has_include(<libswresample/swresample.h>)
#include <libswresample/swresample.h>
#endif

#if __has_include(<libavfilter/avfilter.h>)
#include <libavfilter/avfilter.h>
#include <libavfilter/buffersink.h>
#include <libavfilter/buffersrc.h>
#endif

#endif /* SniffBrowser_Bridging_Header_h */
