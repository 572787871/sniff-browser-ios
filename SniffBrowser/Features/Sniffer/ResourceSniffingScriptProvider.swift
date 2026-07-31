import WebKit

enum ResourceSniffingScriptProvider {
    static let messageHandlerName = "sniffBrowserResourceBridge"
    static let bridgeName = "__sniffBrowserResourceBridgeV1"

    static var userScript: WKUserScript {
        WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }

    static let source = #"""
    (() => {
      "use strict";
      const bridgeName = "__sniffBrowserResourceBridgeV1";
      const handler = window.webkit?.messageHandlers?.sniffBrowserResourceBridge;
      if (!handler) return;
      const safePost = payload => {
        try { handler.postMessage(payload); } catch (_) {}
      };
      if (window[bridgeName]) {
        safePost({
          kind: "scriptReady",
          pageURL: String(location.href || ""),
          pageTitle: String(document.title || "")
        });
        return;
      }

      const state = {
        queue: new Map(),
        flushTimer: 0,
        observerTimer: 0,
        maximumCandidates: 500
      };
      const mediaPattern = /\.(m3u8|mp4|mov|m4v|webm|ts|mpeg|mpg|mkv|mp3|m4a|aac|wav|flac|ogg|opus|vtt|srt|ass|pdf|txt|epub|docx?|xlsx?|pptx?|json|xml|zip|rar|7z|tar|gz|jpe?g|png|gif|webp|heic|avif|svg)(?:$|[?#])/i;
      const ignoredPattern = /\.(js|css|woff2?|ttf|otf)(?:$|[?#])/i;
      const validSchemePattern = /^(https?:|blob:|file:)/i;

      const absoluteURL = raw => {
        if (!raw || typeof raw !== "string" || raw.length > 8192) return null;
        try {
          const value = new URL(raw, document.baseURI).href;
          return validSchemePattern.test(value) ? value : null;
        } catch (_) {
          return null;
        }
      };
      const normalizedMIME = value => String(value || "")
        .split(";", 1)[0].trim().toLowerCase();
      const isLikelyResource = (url, mime, elementType) => {
        if (!url || ignoredPattern.test(url)) return false;
        const type = normalizedMIME(mime);
        if (
          type.startsWith("video/") || type.startsWith("audio/")
          || type.startsWith("image/") || type === "text/vtt"
          || type === "application/subrip"
          || type === "application/vnd.apple.mpegurl"
          || type === "application/x-mpegurl"
          || type === "application/pdf"
          || type === "application/octet-stream"
        ) return true;
        if (mediaPattern.test(url)) return true;
        return ["video", "audio", "source-video", "source-audio", "track", "img"]
          .includes(elementType || "");
      };
      const priority = item => {
        const value = `${item.mimeType || ""} ${item.url || ""}`;
        if (/video|m3u8|mp4|webm|audio|mp3|m4a|vtt|srt|pdf/i.test(value)) return 3;
        if ((item.elementType || "") === "img") return 2;
        return 1;
      };
      const enqueue = item => {
        const url = absoluteURL(item.url);
        if (!url || !isLikelyResource(url, item.mimeType, item.elementType)) return;
        const candidate = {
          url,
          mimeType: normalizedMIME(item.mimeType) || null,
          estimatedSize: Number(item.estimatedSize) > 0
            ? Number(item.estimatedSize) : null,
          duration: Number(item.duration) > 0 && Number.isFinite(Number(item.duration))
            ? Number(item.duration) : null,
          width: Number(item.width) > 0 ? Number(item.width) : null,
          height: Number(item.height) > 0 ? Number(item.height) : null,
          bitrate: Number(item.bitrate) > 0 ? Number(item.bitrate) : null,
          source: item.source || "dom",
          elementType: item.elementType || null,
          headers: item.headers || {}
        };
        const previous = state.queue.get(url);
        if (previous) {
          state.queue.set(url, {
            ...previous,
            ...Object.fromEntries(
              Object.entries(candidate).filter(([, value]) => value != null)
            )
          });
        } else if (state.queue.size < state.maximumCandidates) {
          state.queue.set(url, candidate);
        } else if (priority(candidate) > 1) {
          const lower = [...state.queue.entries()].find(([, value]) => priority(value) < priority(candidate));
          if (lower) {
            state.queue.delete(lower[0]);
            state.queue.set(url, candidate);
          }
        }
        scheduleFlush();
      };
      const flush = () => {
        if (!state.queue.size) return;
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
      const scheduleFlush = () => {
        clearTimeout(state.flushTimer);
        state.flushTimer = setTimeout(flush, 240);
      };
      const mediaItem = (element, source) => ({
        url: element.currentSrc || element.src,
        mimeType: element.getAttribute?.("type") || null,
        duration: element.duration,
        width: element.videoWidth,
        height: element.videoHeight,
        source,
        elementType: element instanceof HTMLVideoElement ? "video" : "audio"
      });
      const scanElement = (element, source) => {
        if (!(element instanceof Element)) return;
        const tag = element.tagName.toLowerCase();
        if (tag === "video" || tag === "audio") {
          enqueue(mediaItem(element, source));
          element.querySelectorAll("source").forEach(child => scanElement(child, source));
          return;
        }
        if (tag === "source") {
          const parentTag = element.parentElement?.tagName?.toLowerCase();
          enqueue({
            url: element.src || element.getAttribute("src"),
            mimeType: element.type,
            source,
            elementType: parentTag === "audio" ? "source-audio" : "source-video"
          });
          return;
        }
        if (tag === "track") {
          enqueue({
            url: element.src || element.getAttribute("src"),
            mimeType: "text/vtt",
            source,
            elementType: "track"
          });
          return;
        }
        if (tag === "img") {
          enqueue({
            url: element.currentSrc || element.src,
            mimeType: null,
            width: element.naturalWidth,
            height: element.naturalHeight,
            source,
            elementType: "img"
          });
          String(element.srcset || "").split(",").forEach(value => {
            enqueue({
              url: value.trim().split(/\s+/, 1)[0],
              source,
              elementType: "img"
            });
          });
          return;
        }
        if (tag === "a" || tag === "link") {
          const raw = element.href || element.getAttribute("href");
          const mime = element.type || null;
          if (element.hasAttribute("download") || mediaPattern.test(String(raw || "")) || normalizedMIME(mime)) {
            enqueue({ url: raw, mimeType: mime, source, elementType: tag });
          }
        }
      };
      const scanDOM = source => {
        document.querySelectorAll("video,audio,source,track,img,a[href],link[href]")
          .forEach(element => scanElement(element, source));
      };
      const scanPerformance = source => {
        let entries = [];
        try { entries = performance.getEntriesByType("resource").slice(-500); } catch (_) {}
        entries.forEach(entry => {
          const initiator = String(entry.initiatorType || "").toLowerCase();
          if (
            ["video", "audio", "img", "fetch", "xmlhttprequest", "link"].includes(initiator)
            || mediaPattern.test(String(entry.name || ""))
          ) {
            enqueue({
              url: entry.name,
              source: source === "manualScan" ? "manualScan" : "performance",
              elementType: initiator === "img" ? "img" : initiator
            });
          }
        });
      };
      const scan = (reason = "dom", scanID = null) => {
        const source = reason === "manualScan" ? "manualScan" : "dom";
        scanDOM(source);
        scanPerformance(source);
        document.querySelectorAll("video,audio").forEach(element => {
          enqueue(mediaItem(element, source === "manualScan" ? "manualScan" : "mediaEvent"));
        });
        clearTimeout(state.flushTimer);
        flush();
        safePost({
          kind: "scanComplete",
          scanID,
          pageURL: String(location.href || ""),
          pageTitle: String(document.title || "")
        });
        return true;
      };

      const originalFetch = window.fetch;
      if (typeof originalFetch === "function" && !originalFetch.__sniffBrowserWrapped) {
        const wrappedFetch = function(...args) {
          return originalFetch.apply(this, args).then(response => {
            try {
              const type = response.headers.get("content-type");
              const length = response.headers.get("content-length");
              enqueue({
                url: response.url || (typeof args[0] === "string" ? args[0] : args[0]?.url),
                mimeType: type,
                estimatedSize: length,
                source: "fetch",
                headers: {
                  "content-type": type || "",
                  "content-length": length || "",
                  "accept-ranges": response.headers.get("accept-ranges") || ""
                }
              });
            } catch (_) {}
            return response;
          });
        };
        Object.defineProperty(wrappedFetch, "__sniffBrowserWrapped", { value: true });
        window.fetch = wrappedFetch;
      }

      const xhrMetadata = new WeakMap();
      const originalOpen = XMLHttpRequest.prototype.open;
      const originalSend = XMLHttpRequest.prototype.send;
      if (!originalOpen.__sniffBrowserWrapped) {
        const wrappedOpen = function(method, url, ...rest) {
          try { xhrMetadata.set(this, { url: String(url || "") }); } catch (_) {}
          return originalOpen.call(this, method, url, ...rest);
        };
        Object.defineProperty(wrappedOpen, "__sniffBrowserWrapped", { value: true });
        XMLHttpRequest.prototype.open = wrappedOpen;
        XMLHttpRequest.prototype.send = function(...args) {
          if (!xhrMetadata.get(this)?.installed) {
            const metadata = xhrMetadata.get(this) || {};
            metadata.installed = true;
            xhrMetadata.set(this, metadata);
            this.addEventListener("loadend", () => {
              try {
                const type = this.getResponseHeader("content-type");
                const length = this.getResponseHeader("content-length");
                enqueue({
                  url: this.responseURL || metadata.url,
                  mimeType: type,
                  estimatedSize: length,
                  source: "xhr",
                  headers: {
                    "content-type": type || "",
                    "content-length": length || "",
                    "accept-ranges": this.getResponseHeader("accept-ranges") || ""
                  }
                });
              } catch (_) {}
            }, { once: true });
          }
          return originalSend.apply(this, args);
        };
      }

      const observer = new MutationObserver(records => {
        clearTimeout(state.observerTimer);
        state.observerTimer = setTimeout(() => {
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
      observer.observe(document.documentElement || document, {
        subtree: true,
        childList: true,
        attributes: true,
        attributeFilter: ["src", "href", "srcset", "type"]
      });

      ["loadedmetadata", "durationchange", "progress", "play", "canplay"]
        .forEach(eventName => {
          document.addEventListener(eventName, event => {
            if (event.target instanceof HTMLVideoElement || event.target instanceof HTMLAudioElement) {
              enqueue(mediaItem(event.target, "mediaEvent"));
            }
          }, true);
        });

      window[bridgeName] = Object.freeze({ scan });
      safePost({
        kind: "scriptReady",
        pageURL: String(location.href || ""),
        pageTitle: String(document.title || "")
      });
      if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", () => scan("dom"), { once: true });
      } else {
        scan("dom");
      }
    })();
    """#

    static func manualScanInvocation(scanID: UUID) -> String {
        """
        (() => {
          const bridge = window.\(bridgeName);
          if (!bridge || typeof bridge.scan !== "function") { return false; }
          return bridge.scan("manualScan", "\(scanID.uuidString)");
        })();
        """
    }

    static func incrementalScanInvocation(reason: String) -> String {
        let safeReason = reason.replacingOccurrences(of: "\"", with: "")
        return """
        (() => {
          const bridge = window.\(bridgeName);
          if (!bridge || typeof bridge.scan !== "function") { return false; }
          return bridge.scan("\(safeReason)");
        })();
        """
    }
}
