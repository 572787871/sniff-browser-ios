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
        sentSignatures: new Map(),
        flushTimer: 0,
        observerTimer: 0,
        observer: null,
        hooksInstalled: false,
        capturedVideoFrames: new WeakMap(),
        maximumCandidates: 500
      };
      const mediaEvents = [
        "loadedmetadata", "loadeddata", "durationchange", "progress",
        "play", "canplay", "seeked"
      ];
      const lazyImageURLAttributes = [
        "z-image-loader-url", "data-src", "data-original", "data-lazy-src",
        "data-original-src", "data-actualsrc"
      ];
      const lazyImageSrcsetAttributes = ["data-srcset", "data-lazy-srcset"];
      const mediaPattern = /\.(m3u8|mp4|mov|m4v|webm|ts|mpeg|mpg|mkv|mp3|m4a|aac|wav|flac|ogg|opus|vtt|srt|ass|pdf|txt|epub|docx?|xlsx?|pptx?|json|xml|zip|rar|7z|tar|gz|jpe?g|png|gif|webp|heic|avif|svg)(?:$|[?#])/i;
      // 仅匹配 URL 路径（不含查询参数）以媒体扩展名结尾的链接。
      // Google 等站点的 /imgres?imgurl=xxx.png、/url?q=xxx.png 跳转包装链接
      // 会在查询参数里带扩展名，但下载它返回的是 HTML 而非文件。
      const mediaPathPattern = /\.(m3u8|mp4|mov|m4v|webm|ts|mpeg|mpg|mkv|mp3|m4a|aac|wav|flac|ogg|opus|vtt|srt|ass|pdf|txt|epub|docx?|xlsx?|pptx?|json|xml|zip|rar|7z|tar|gz|jpe?g|png|gif|webp|heic|avif|svg)(?:$|[?#])/i;
      const ignoredPattern = /\.(js|css|woff2?|ttf|otf)(?:$|[?#])/i;
      const validSchemePattern = /^(https?:|blob:|file:|data:image\/)/i;
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
        if (!raw || typeof raw !== "string") return null;
        const isInlineImage = /^data:image\//i.test(raw);
        if (raw.length > (isInlineImage ? 1500000 : 8192)) return null;
        if (isInlineImage) return raw;
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
      const candidateSignature = candidate => {
        const thumbnail = String(candidate.thumbnailURL || "");
        const thumbnailSignature = thumbnail.startsWith("data:image/")
          ? `inline:${thumbnail.length}:${thumbnail.slice(-32)}`
          : thumbnail;
        return JSON.stringify([
          candidate.mimeType, candidate.estimatedSize, candidate.duration,
          candidate.width, candidate.height, candidate.bitrate,
          thumbnailSignature, candidate.source, candidate.elementType
        ]);
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
          const merged = { ...previous, ...Object.fromEntries(
            Object.entries(candidate).filter(([, value]) => value != null)
          )};
          state.queue.set(url, merged);
        } else if (state.sentSignatures.get(url) === candidateSignature(candidate)) {
          return;
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
        const maximumCount = 40;
        const maximumApproximateLength = 1700000;
        let batch = [];
        let approximateLength = 0;
        const postBatch = () => {
          if (!batch.length) return;
          batch.forEach(candidate => {
            if (!state.sentSignatures.has(candidate.url)
              && state.sentSignatures.size >= 1000) {
              state.sentSignatures.delete(state.sentSignatures.keys().next().value);
            }
            state.sentSignatures.set(
              candidate.url,
              candidateSignature(candidate)
            );
          });
          safePost({
            kind: "batch",
            pageURL: String(location.href || ""),
            pageTitle: String(document.title || ""),
            candidates: batch
          });
          batch = [];
          approximateLength = 0;
        };
        values.forEach(candidate => {
          const candidateLength = String(candidate.url || "").length
            + String(candidate.thumbnailURL || "").length + 512;
          if (batch.length >= maximumCount
            || (batch.length && approximateLength + candidateLength > maximumApproximateLength)) {
            postBatch();
          }
          batch.push(candidate);
          approximateLength += candidateLength;
        });
        postBatch();
      };
      const videoFrameDataURL = element => {
        if (!(element instanceof HTMLVideoElement)) return null;
        const cached = state.capturedVideoFrames.get(element);
        if (cached) return cached;
        const width = Number(element.videoWidth || 0);
        const height = Number(element.videoHeight || 0);
        if (element.readyState < 2 || width < 2 || height < 2) return null;
        try {
          const maximumDimension = 320;
          const scale = Math.min(
            1,
            maximumDimension / width,
            maximumDimension / height
          );
          const canvas = document.createElement("canvas");
          canvas.width = Math.max(2, Math.round(width * scale));
          canvas.height = Math.max(2, Math.round(height * scale));
          const context = canvas.getContext("2d", { alpha: false });
          if (!context) return null;
          context.drawImage(element, 0, 0, canvas.width, canvas.height);
          const dataURL = canvas.toDataURL("image/jpeg", 0.68);
          if (!dataURL || dataURL.length > 180000) return null;
          state.capturedVideoFrames.set(element, dataURL);
          return dataURL;
        } catch (_) {
          // Cross-origin media can taint a canvas. Native AVFoundation remains
          // the bounded fallback and the live page must never be disturbed.
          return null;
        }
      };
      const mediaItem = (element, source) => ({
        url: element.currentSrc || element.src,
        mimeType: element.getAttribute?.("type") || null,
        duration: element.duration,
        width: element.videoWidth,
        height: element.videoHeight,
        thumbnailURL: element instanceof HTMLVideoElement
          ? (videoFrameDataURL(element) || element.poster || element.getAttribute?.("poster")
            || element.dataset?.poster || element.dataset?.thumbnail)
          : null,
        source,
        elementType: element instanceof HTMLVideoElement ? "video" : "audio"
      });
      const enqueueImageURL = (element, raw, source) => {
        const value = String(raw || "").trim();
        if (!value) return;
        const dataMIME = value.match(/^data:([^;,]+)[;,]/i)?.[1] || null;
        enqueue({
          url: value,
          mimeType: dataMIME,
          width: element.naturalWidth,
          height: element.naturalHeight,
          source,
          elementType: "img"
        });
      };
      const scanImageSrcset = (element, raw, source) => String(raw || "")
        .split(",")
        .forEach(value => enqueueImageURL(
          element,
          value.trim().split(/\s+/, 1)[0],
          source
        ));
      const scanImageElement = (element, source) => {
        enqueueImageURL(element, element.currentSrc || element.src, source);
        scanImageSrcset(element, element.srcset, source);
        lazyImageURLAttributes.forEach(attribute => {
          enqueueImageURL(element, element.getAttribute(attribute), source);
        });
        lazyImageSrcsetAttributes.forEach(attribute => {
          scanImageSrcset(element, element.getAttribute(attribute), source);
        });
      };
      const scanBackgroundImage = (element, source) => {
        if (!(element instanceof Element)) return;
        let background = "";
        try { background = getComputedStyle(element).backgroundImage || ""; } catch (_) {}
        const matches = background.matchAll(/url\(\s*(["']?)(.*?)\1\s*\)/gi);
        for (const match of matches) {
          enqueueImageURL(element, match[2], source);
        }
      };
      const scanElement = (element, source) => {
        if (!state.enabled || !(element instanceof Element)) return;
        const tag = element.tagName.toLowerCase();
        if (tag === "video" || tag === "audio") {
          enqueue(mediaItem(element, source));
          element.querySelectorAll("source").forEach(child => scanElement(child, source));
        } else if (tag === "source") {
          const parentTag = element.parentElement?.tagName?.toLowerCase();
          if (parentTag === "picture") {
            scanImageSrcset(element, element.srcset, source);
            scanImageSrcset(element, element.getAttribute("data-srcset"), source);
            scanImageSrcset(element, element.getAttribute("data-lazy-srcset"), source);
          } else {
            enqueue({ url: element.src || element.getAttribute("src"), mimeType: element.type,
              thumbnailURL: parentTag === "video"
                ? (element.parentElement?.poster
                  || element.parentElement?.dataset?.poster
                  || element.parentElement?.dataset?.thumbnail) : null,
              source, elementType: parentTag === "audio" ? "source-audio" : "source-video" });
          }
        } else if (tag === "track") {
          enqueue({ url: element.src || element.getAttribute("src"), mimeType: "text/vtt", source, elementType: "track" });
        } else if (tag === "img") {
          scanImageElement(element, source);
        } else if (tag === "a" || tag === "link") {
          const raw = element.href || element.getAttribute("href");
          const mime = element.type || null;
          if (element.hasAttribute("download") || hasMediaPath(raw) || normalizedMIME(mime)) {
            enqueue({ url: raw, mimeType: mime, source, elementType: tag });
          }
        }
        scanBackgroundImage(element, source);
      };
      const scanDOM = source => document
        .querySelectorAll("video,audio,source,track,img,a[href],link[href]")
        .forEach(element => scanElement(element, source));
      const scanCSSBackgrounds = source => {
        Array.from(document.querySelectorAll("*")).slice(0, 2000)
          .forEach(element => scanBackgroundImage(element, source));
      };
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
            const configuredVideo = element.querySelector?.("video");
            enqueue({
              url,
              mimeType: String(media.type || "").toLowerCase() === "hls"
                ? "application/vnd.apple.mpegurl" : (media.mimeType || null),
              duration: media.duration,
              width: media.width,
              height: media.height,
              thumbnailURL: videoFrameDataURL(configuredVideo)
                || media.poster || media.pic || media.thumbnail || null,
              // A URL declared as the player's primary video is a stronger
              // signal than pre-roll playlists observed through Performance.
              // Rank it like a real media event so its preview is generated
              // before large advertisement streams.
              source: "mediaEvent",
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
        if (reason === "manualScan") state.sentSignatures.clear();
        scanDOM(source);
        scanCSSBackgrounds(source);
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
          attributeFilter: [
            "src", "href", "srcset", "type", "style", "class",
            ...lazyImageURLAttributes, ...lazyImageSrcsetAttributes
          ]
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
        state.sentSignatures.clear();
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

}
