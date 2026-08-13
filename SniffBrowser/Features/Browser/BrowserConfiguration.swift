import WebKit

@MainActor
enum BrowserConfiguration {
  static func makeWebViewConfiguration(
    isPrivate: Bool = false
  ) -> WKWebViewConfiguration {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = isPrivate ? .nonPersistent() : .default()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    configuration.allowsInlineMediaPlayback = true
    // Modern players often pause the main video for a pre-roll or source
    // negotiation, then resume it asynchronously after the original tap.
    // Treat that continuation as part of the page's playback flow instead of
    // requiring a second user gesture.
    configuration.mediaTypesRequiringUserActionForPlayback = []
    configuration.preferences.isElementFullscreenEnabled = true
    configuration.userContentController.addUserScript(
      WebPageThemeColorService.userScript
    )
    configuration.userContentController.addUserScript(
      ResourceSniffingScriptProvider.userScript
    )
    configuration.userContentController.addUserScript(
      WebVideoLongPressScriptProvider.userScript
    )
    return configuration
  }
}

/// Detects an intentional long press on the webpage's current video without
/// moving or resizing WKWebView. The script resolves the player's real HTTP
/// media URL (including `data-config` backed HLS players) instead of sending a
/// temporary `blob:` playback handle to the download system.
enum WebVideoLongPressScriptProvider {
  static let messageHandlerName = "sniffBrowserVideoLongPress"

  static var userScript: WKUserScript {
    WKUserScript(
      source: source,
      injectionTime: .atDocumentEnd,
      forMainFrameOnly: true
    )
  }

  static let source = #"""
  (() => {
    "use strict";
    if (window.__sniffBrowserVideoLongPressInstalled) return;
    window.__sniffBrowserVideoLongPressInstalled = true;

    let timer = 0;
    let activeVideo = null;
    let startX = 0;
    let startY = 0;
    let suppressContextMenuUntil = 0;

    const absoluteHTTPURL = raw => {
      if (!raw || typeof raw !== "string" || raw.length > 8192) return null;
      try {
        const value = new URL(raw, document.baseURI).href;
        return /^https?:/i.test(value) ? value : null;
      } catch (_) { return null; }
    };

    const videoAt = (target, x, y) => {
      if (target instanceof HTMLVideoElement) return target;
      let node = target instanceof Element ? target : null;
      for (let depth = 0; node && depth < 8; depth += 1, node = node.parentElement) {
        const nested = node.querySelector?.("video");
        if (nested instanceof HTMLVideoElement) return nested;
      }
      const candidates = Array.from(document.querySelectorAll("video"));
      return candidates.find(video => {
        const rect = video.getBoundingClientRect();
        return rect.width > 20 && rect.height > 20
          && x >= rect.left && x <= rect.right
          && y >= rect.top && y <= rect.bottom;
      }) || null;
    };

    const parseConfig = video => {
      const nearby = [];
      let node = video;
      for (let depth = 0; node && depth < 10; depth += 1, node = node.parentElement) {
        if (node.hasAttribute?.("data-config")) nearby.push(node);
      }
      document.querySelectorAll("[data-config]").forEach(element => {
        if (!nearby.includes(element) && element.contains(video)) nearby.push(element);
      });
      if (!nearby.length) {
        const all = document.querySelectorAll("[data-config]");
        if (all.length === 1) nearby.push(all[0]);
      }
      for (const element of nearby) {
        const raw = element.getAttribute("data-config");
        if (!raw || raw.length > 1_000_000) continue;
        try {
          const config = JSON.parse(raw);
          const media = config?.video || config?.media || null;
          if (media && typeof media === "object") return media;
        } catch (_) {}
      }
      return null;
    };

    const payloadFor = video => {
      const config = parseConfig(video);
      const configuredURL = absoluteHTTPURL(config?.url || config?.src || config?.file);
      const elementURLs = [
        video.currentSrc,
        video.src,
        ...Array.from(video.querySelectorAll("source")).map(source => source.src)
      ].map(absoluteHTTPURL).filter(Boolean);
      const url = configuredURL || elementURLs[0] || null;
      if (!url) return null;
      const declaredType = String(config?.type || config?.mimeType
        || video.getAttribute("type") || "").toLowerCase();
      const isHLS = declaredType === "hls" || /mpegurl/.test(declaredType)
        || /\.m3u8(?:$|[?#])/i.test(url);
      const finite = value => Number.isFinite(Number(value)) && Number(value) > 0
        ? Number(value) : null;
      return {
        url,
        mimeType: isHLS ? "application/vnd.apple.mpegurl"
          : (declaredType || "video/mp4"),
        pageURL: String(location.href || ""),
        pageTitle: String(document.title || ""),
        thumbnailURL: absoluteHTTPURL(
          config?.poster || config?.pic || config?.thumbnail || video.poster
        ),
        duration: finite(config?.duration) || finite(video.duration),
        width: finite(config?.width) || finite(video.videoWidth),
        height: finite(config?.height) || finite(video.videoHeight)
      };
    };

    const cancel = () => {
      clearTimeout(timer);
      timer = 0;
      activeVideo = null;
    };

    document.addEventListener("touchstart", event => {
      cancel();
      if (event.touches.length !== 1) return;
      const touch = event.touches[0];
      const video = videoAt(event.target, touch.clientX, touch.clientY);
      if (!video) return;
      activeVideo = video;
      startX = touch.clientX;
      startY = touch.clientY;
      timer = setTimeout(() => {
        const payload = payloadFor(activeVideo);
        cancel();
        if (!payload) return;
        suppressContextMenuUntil = Date.now() + 1500;
        try {
          window.webkit?.messageHandlers?.sniffBrowserVideoLongPress
            ?.postMessage(payload);
        } catch (_) {}
      }, 520);
    }, { capture: true, passive: true });

    document.addEventListener("touchmove", event => {
      if (!timer || event.touches.length !== 1) return;
      const touch = event.touches[0];
      if (Math.hypot(touch.clientX - startX, touch.clientY - startY) > 12) cancel();
    }, { capture: true, passive: true });
    document.addEventListener("touchend", cancel, { capture: true, passive: true });
    document.addEventListener("touchcancel", cancel, { capture: true, passive: true });
    document.addEventListener("contextmenu", event => {
      if (Date.now() < suppressContextMenuUntil || activeVideo) {
        event.preventDefault();
        event.stopPropagation();
      }
    }, true);
  })();
  """#
}
