import WebKit

enum ResourceSniffingScriptProvider {
    static let messageHandlerName = "sniffBrowserResourceBridge"
    static let bridgeName = "__sniffBrowserResourceBridgeV2"

    static var userScript: WKUserScript {
        WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }

    /// documentStart 只安装休眠 bootstrap。网络 Hook、DOM 监听和媒体事件
    /// 都要等用户明确调用 enable() 后才工作。
    static let source = #"""
    (() => {
      "use strict";
      const bridgeName = "__sniffBrowserResourceBridgeV2";
      const handler = window.webkit?.messageHandlers?.sniffBrowserResourceBridge;
      if (!handler || window[bridgeName]) return;

      const state = {
        enabled: false,
        queue: new Map(),
        flushTimer: 0,
        observerTimer: 0,
        observer: null,
        hooksInstalled: false,
        maximumCandidates: 500
      };
      const mediaEvents = ["loadedmetadata", "durationchange", "progress", "play", "canplay"];
      const mediaPattern = /\.(m3u8|mp4|mov|m4v|webm|ts|mpeg|mpg|mkv|mp3|m4a|aac|wav|flac|ogg|opus|vtt|srt|ass|pdf|txt|epub|docx?|xlsx?|pptx?|json|xml|zip|rar|7z|tar|gz|jpe?g|png|gif|webp|heic|avif|svg)(?:$|[?#])/i;
      // 仅匹配 URL 路径（不含查询参数）以媒体扩展名结尾的链接。
      // Google 等站点的 /imgres?imgurl=xxx.png、/url?q=xxx.png 跳转包装链接
      // 会在查询参数里带扩展名，但下载它返回的是 HTML 而非文件。
      const mediaPathPattern = /\.(m3u8|mp4|mov|m4v|webm|ts|mpeg|mpg|mkv|mp3|m4a|aac|wav|flac|ogg|opus|vtt|srt|ass|pdf|txt|epub|docx?|xlsx?|pptx?|json|xml|zip|rar|7z|tar|gz|jpe?g|png|gif|webp|heic|avif|svg)(?:$|[?#])/i;
      const ignoredPattern = /\.(js|css|woff2?|ttf|otf)(?:$|[?#])/i;
      const validSchemePattern = /^(https?:|blob:|file:)/i;
      const hasMediaPath = raw => {
        try {
          return mediaPathPattern.test(new URL(raw, document.baseURI).pathname);
        } catch (_) { return false; }
      };

      const safePost = payload => {
        if (!state.enabled) return;
        try { handler.postMessage(payload); } catch (_) {}
      };
      const absoluteURL = raw => {
        if (!raw || typeof raw !== "string" || raw.length > 8192) return null;
        try {
          const value = new URL(raw, document.baseURI).href;
          return validSchemePattern.test(value) ? value : null;
        } catch (_) { return null; }
      };
      const normalizedMIME = value => String(value || "")
        .split(";", 1)[0].trim().toLowerCase();
      const isLikelyResource = (url, mime, elementType) => {
        if (!url || ignoredPattern.test(url)) return false;
        const type = normalizedMIME(mime);
        if (type.startsWith("video/") || type.startsWith("audio/")
          || type.startsWith("image/") || type === "text/vtt"
          || type === "application/subrip"
          || type === "application/vnd.apple.mpegurl"
          || type === "application/x-mpegurl"
          || type === "application/pdf"
          || type === "application/octet-stream") return true;
        if (mediaPattern.test(url)) return true;
        return ["video", "audio", "source-video", "source-audio", "track", "img"]
          .includes(elementType || "");
      };
      const priority = item => {
        const value = `${item.mimeType || ""} ${item.url || ""}`;
        if (/video|m3u8|mp4|webm|audio|mp3|m4a|vtt|srt|pdf/i.test(value)) return 3;
        return item.elementType === "img" ? 2 : 1;
      };
      const scheduleFlush = () => {
        if (!state.enabled) return;
        clearTimeout(state.flushTimer);
        state.flushTimer = setTimeout(flush, 240);
      };
      const enqueue = item => {
        if (!state.enabled) return;
        const url = absoluteURL(item.url);
        if (!url || !isLikelyResource(url, item.mimeType, item.elementType)) return;
        const candidate = {
          url,
          mimeType: normalizedMIME(item.mimeType) || null,
          estimatedSize: Number(item.estimatedSize) > 0 ? Number(item.estimatedSize) : null,
          duration: Number(item.duration) > 0 && Number.isFinite(Number(item.duration)) ? Number(item.duration) : null,
          width: Number(item.width) > 0 ? Number(item.width) : null,
          height: Number(item.height) > 0 ? Number(item.height) : null,
          bitrate: Number(item.bitrate) > 0 ? Number(item.bitrate) : null,
          thumbnailURL: absoluteURL(item.thumbnailURL) || null,
          source: item.source || "dom",
          elementType: item.elementType || null,
          headers: item.headers || {}
        };
        const previous = state.queue.get(url);
        if (previous) {
          state.queue.set(url, { ...previous, ...Object.fromEntries(
            Object.entries(candidate).filter(([, value]) => value != null)
          )});
        } else if (state.queue.size < state.maximumCandidates) {
          state.queue.set(url, candidate);
        } else if (priority(candidate) > 1) {
          const lower = [...state.queue.entries()].find(([, value]) => priority(value) < priority(candidate));
          if (lower) { state.queue.delete(lower[0]); state.queue.set(url, candidate); }
        }
        scheduleFlush();
      };
      const flush = () => {
        if (!state.enabled || !state.queue.size) return;
        const values = [...state.queue.values()];
        state.queue.clear();
        for (let index = 0; index < values.length; index += 100) {
          safePost({
            kind: "batch",
            pageURL: String(location.href || ""),
            pageTitle: String(document.title || ""),
            candidates: values.slice(index, index + 100)
          });
        }
      };
      const pagePreview = () => {
        const metadata = document.querySelector(
          'meta[property="og:image:secure_url"],meta[property="og:image"],'
          + 'meta[name="twitter:image"],meta[itemprop="thumbnailUrl"]'
        )?.content;
        if (metadata) return metadata;
        const structuredData = Array.from(
          document.querySelectorAll('script[type="application/ld+json"]')
        );
        for (const script of structuredData) {
          try {
            const parsed = JSON.parse(script.textContent || '{}');
            const entries = Array.isArray(parsed) ? parsed : [parsed];
            for (const entry of entries) {
              const thumbnail = Array.isArray(entry?.thumbnailUrl)
                ? entry.thumbnailUrl[0]
                : entry?.thumbnailUrl;
              if (typeof thumbnail === 'string' && thumbnail) return thumbnail;
            }
          } catch (_) {}
        }
        return null;
      };
      const mediaItem = (element, source) => ({
        url: element.currentSrc || element.src,
        mimeType: element.getAttribute?.("type") || null,
        duration: element.duration,
        width: element.videoWidth,
        height: element.videoHeight,
        thumbnailURL: element instanceof HTMLVideoElement
          ? (element.poster || element.getAttribute?.("poster")
            || element.dataset?.poster || element.dataset?.thumbnail
            || pagePreview())
          : null,
        source,
        elementType: element instanceof HTMLVideoElement ? "video" : "audio"
      });
      const scanElement = (element, source) => {
        if (!state.enabled || !(element instanceof Element)) return;
        const tag = element.tagName.toLowerCase();
        if (tag === "video" || tag === "audio") {
          enqueue(mediaItem(element, source));
          element.querySelectorAll("source").forEach(child => scanElement(child, source));
        } else if (tag === "source") {
          const parentTag = element.parentElement?.tagName?.toLowerCase();
          enqueue({ url: element.src || element.getAttribute("src"), mimeType: element.type,
            thumbnailURL: parentTag === "video"
              ? (element.parentElement?.poster
                || element.parentElement?.dataset?.poster
                || element.parentElement?.dataset?.thumbnail
                || pagePreview()) : null,
            source, elementType: parentTag === "audio" ? "source-audio" : "source-video" });
        } else if (tag === "track") {
          enqueue({ url: element.src || element.getAttribute("src"), mimeType: "text/vtt", source, elementType: "track" });
        } else if (tag === "img") {
          enqueue({ url: element.currentSrc || element.src, width: element.naturalWidth,
            height: element.naturalHeight, source, elementType: "img" });
          String(element.srcset || "").split(",").forEach(value => enqueue({
            url: value.trim().split(/\s+/, 1)[0], source, elementType: "img"
          }));
        } else if (tag === "a" || tag === "link") {
          const raw = element.href || element.getAttribute("href");
          const mime = element.type || null;
          if (element.hasAttribute("download") || hasMediaPath(raw) || normalizedMIME(mime)) {
            enqueue({ url: raw, mimeType: mime, source, elementType: tag });
          }
        }
      };
      const scanDOM = source => document
        .querySelectorAll("video,audio,source,track,img,a[href],link[href]")
        .forEach(element => scanElement(element, source));
      const scanPerformance = source => {
        let entries = [];
        try { entries = performance.getEntriesByType("resource").slice(-500); } catch (_) {}
        entries.forEach(entry => {
          const initiator = String(entry.initiatorType || "").toLowerCase();
          if (["video", "audio", "img", "fetch", "xmlhttprequest", "link"].includes(initiator)
            || mediaPattern.test(String(entry.name || ""))) {
            enqueue({ url: entry.name, source: source === "manualScan" ? "manualScan" : "performance",
              elementType: initiator === "img" ? "img" : initiator });
          }
        });
      };
      const scanPlayerConfigurations = source => {
        document.querySelectorAll("[data-config]").forEach(element => {
          const raw = element.getAttribute("data-config");
          if (!raw || raw.length > 1_000_000) return;
          try {
            const config = JSON.parse(raw);
            const media = config?.video || config?.media || null;
            if (!media || typeof media !== "object") return;
            const url = media.url || media.src || media.file;
            if (!url) return;
            enqueue({
              url,
              mimeType: String(media.type || "").toLowerCase() === "hls"
                ? "application/vnd.apple.mpegurl" : (media.mimeType || null),
              duration: media.duration,
              width: media.width,
              height: media.height,
              thumbnailURL: media.poster || media.pic || media.thumbnail || pagePreview(),
              source,
              elementType: "source-video"
            });
          } catch (_) {}
        });
      };
      const scanEmbeddedHLSURLs = source => {
        let remaining = 2_000_000;
        const extract = raw => {
          if (!raw || remaining <= 0) return;
          const text = String(raw).slice(0, remaining)
            .replace(/\\\//g, "/").replace(/&amp;/g, "&");
          remaining -= text.length;
          const matches = text.match(/https?:\/\/[^\s"'<>]+?\.m3u8(?:\?[^\s"'<>]*)?/gi) || [];
          matches.slice(0, 50).forEach(url => enqueue({
            url,
            mimeType: "application/vnd.apple.mpegurl",
            thumbnailURL: pagePreview(),
            source,
            elementType: "source-video"
          }));
        };
        document.querySelectorAll("script:not([src])").forEach(script => extract(script.textContent));
        document.querySelectorAll("[data-media],[data-source],[data-video]").forEach(element => {
          for (const attribute of element.attributes) extract(attribute.value);
        });
      };
      const scan = (reason = "dom", scanID = null) => {
        if (!state.enabled) return false;
        const source = reason === "manualScan" ? "manualScan" : "dom";
        scanDOM(source);
        scanPerformance(source);
        scanPlayerConfigurations(source);
        scanEmbeddedHLSURLs(source);
        document.querySelectorAll("video,audio").forEach(element => enqueue(
          mediaItem(element, source === "manualScan" ? "manualScan" : "mediaEvent")
        ));
        clearTimeout(state.flushTimer);
        flush();
        safePost({ kind: "scanComplete", scanID, pageURL: String(location.href || ""),
          pageTitle: String(document.title || "") });
        return true;
      };
      const mediaHandler = event => {
        if (state.enabled && (event.target instanceof HTMLVideoElement || event.target instanceof HTMLAudioElement)) {
          enqueue(mediaItem(event.target, "mediaEvent"));
        }
      };
      const installHooksOnce = () => {
        if (state.hooksInstalled) return;
        state.hooksInstalled = true;
        const originalFetch = window.fetch;
        if (typeof originalFetch === "function") {
          window.fetch = function(...args) {
            return originalFetch.apply(this, args).then(response => {
              if (state.enabled) {
                try {
                  const type = response.headers.get("content-type");
                  const length = response.headers.get("content-length");
                  enqueue({ url: response.url || (typeof args[0] === "string" ? args[0] : args[0]?.url),
                    mimeType: type, estimatedSize: length, source: "fetch",
                    headers: { "content-type": type || "", "content-length": length || "" } });
                } catch (_) {}
              }
              return response;
            });
          };
        }
        const metadata = new WeakMap();
        const originalOpen = XMLHttpRequest.prototype.open;
        const originalSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.open = function(method, url, ...rest) {
          try { metadata.set(this, { url: String(url || "") }); } catch (_) {}
          return originalOpen.call(this, method, url, ...rest);
        };
        XMLHttpRequest.prototype.send = function(...args) {
          const item = metadata.get(this) || {};
          if (!item.installed) {
            item.installed = true;
            metadata.set(this, item);
            this.addEventListener("loadend", () => {
              if (!state.enabled) return;
              try {
                const type = this.getResponseHeader("content-type");
                const length = this.getResponseHeader("content-length");
                enqueue({ url: this.responseURL || item.url, mimeType: type,
                  estimatedSize: length, source: "xhr",
                  headers: { "content-type": type || "", "content-length": length || "" } });
              } catch (_) {}
            });
          }
          return originalSend.apply(this, args);
        };
      };
      const startObserver = () => {
        state.observer?.disconnect();
        state.observer = new MutationObserver(records => {
          clearTimeout(state.observerTimer);
          state.observerTimer = setTimeout(() => {
            if (!state.enabled) return;
            records.forEach(record => {
              if (record.target instanceof Element) scanElement(record.target, "mutationObserver");
              record.addedNodes.forEach(node => {
                if (!(node instanceof Element)) return;
                scanElement(node, "mutationObserver");
                node.querySelectorAll?.("video,audio,source,track,img,a[href],link[href]")
                  .forEach(element => scanElement(element, "mutationObserver"));
              });
            });
          }, 180);
        });
        state.observer.observe(document.documentElement || document, {
          subtree: true, childList: true, attributes: true,
          attributeFilter: ["src", "href", "srcset", "type"]
        });
      };
      const enable = () => {
        if (state.enabled) return true;
        state.enabled = true;
        installHooksOnce();
        startObserver();
        mediaEvents.forEach(name => document.addEventListener(name, mediaHandler, true));
        safePost({ kind: "scriptReady", pageURL: String(location.href || ""),
          pageTitle: String(document.title || "") });
        return true;
      };
      const disable = () => {
        state.enabled = false;
        clearTimeout(state.flushTimer);
        clearTimeout(state.observerTimer);
        state.queue.clear();
        state.observer?.disconnect();
        state.observer = null;
        mediaEvents.forEach(name => document.removeEventListener(name, mediaHandler, true));
        return true;
      };
      const dispose = () => disable();
      window[bridgeName] = Object.freeze({ enable, disable, dispose, scan,
        isEnabled: () => state.enabled });
    })();
    """#

    static let enableInvocation = """
    (() => window.\(bridgeName)?.enable?.() === true)();
    """

    static let disableInvocation = """
    (() => window.\(bridgeName)?.disable?.() === true)();
    """

    static func manualScanInvocation(scanID: UUID) -> String {
        """
        (() => window.\(bridgeName)?.scan?.("manualScan", "\(scanID.uuidString)") === true)();
        """
    }

    static func incrementalScanInvocation(reason: String) -> String {
        let safeReason = reason.replacingOccurrences(of: "\"", with: "")
        return """
        (() => window.\(bridgeName)?.scan?.("\(safeReason)") === true)();
        """
    }

    static func enableAndIncrementalScanInvocation(reason: String) -> String {
        let safeReason = reason.replacingOccurrences(of: "\"", with: "")
        return """
        (() => {
          const bridge = window.\(bridgeName);
          if (!bridge || bridge.enable?.() !== true) return false;
          return bridge.scan?.("\(safeReason)") === true;
        })();
        """
    }
}
