import WebKit

@MainActor
enum WebPageThemeColorService {
  static let messageHandlerName = "sniffBrowserPageTheme"

  static let userScript = WKUserScript(
    source: scriptSource,
    injectionTime: .atDocumentStart,
    forMainFrameOnly: true
  )

  static func requestCurrentTheme(in webView: WKWebView) {
    webView.evaluateJavaScript(
      "window.__sniffBrowserReportTheme && window.__sniffBrowserReportTheme();"
    )
  }

  private static let scriptSource = """
    (() => {
      if (window.__sniffBrowserThemeInstalled) return;
      window.__sniffBrowserThemeInstalled = true;

      let timer = null;
      let lastValue = null;

      const isTransparent = value => {
        if (!value) return true;
        const normalized = String(value).trim().toLowerCase();
        return normalized === "transparent"
          || normalized === "rgba(0, 0, 0, 0)"
          || normalized === "rgba(0,0,0,0)";
      };

      const matchingThemeColors = () => {
        const values = [];
        const candidates = Array.from(
          document.querySelectorAll('meta[name="theme-color" i]')
        );
        for (const meta of candidates) {
          const media = meta.getAttribute("media");
          if (!media || !window.matchMedia || window.matchMedia(media).matches) {
            const content = meta.getAttribute("content");
            if (!isTransparent(content)) values.push(content);
          }
        }
        return values;
      };

      const topEdgeColors = () => {
        if (!document.elementFromPoint) return [];
        const width = Math.max(
          document.documentElement && document.documentElement.clientWidth || 0,
          window.innerWidth || 0
        );
        const samplePoints = [
          [Math.max(1, width * 0.5), 1],
          [Math.max(1, width * 0.18), 1],
          [Math.max(1, width * 0.82), 1]
        ];
        const values = [];
        for (const [x, y] of samplePoints) {
          let element = document.elementFromPoint(x, y);
          while (element) {
            const color = getComputedStyle(element).backgroundColor;
            if (!isTransparent(color)) {
              values.push(color);
              break;
            }
            element = element.parentElement;
          }
        }
        return values;
      };

      const detectedColors = () => {
        // 浏览器外围应衔接网页“顶边正在显示”的颜色，而不是页面较深处
        // 的 body 底色。其次采用站点声明的 theme-color，再回退 body/html。
        const values = [...topEdgeColors(), ...matchingThemeColors()];
        if (document.body) {
          const bodyColor = getComputedStyle(document.body).backgroundColor;
          if (!isTransparent(bodyColor)) values.push(bodyColor);
        }
        if (document.documentElement) {
          const htmlColor = getComputedStyle(
            document.documentElement
          ).backgroundColor;
          if (!isTransparent(htmlColor)) values.push(htmlColor);
        }
        if (values.length === 0) {
          const rootStyle = document.documentElement
            ? getComputedStyle(document.documentElement)
            : null;
          const schemes = String(rootStyle && rootStyle.colorScheme || "")
            .toLowerCase()
            .split(/\\s+/)
            .filter(Boolean);
          const prefersDark = Boolean(
            window.matchMedia
              && window.matchMedia("(prefers-color-scheme: dark)").matches
          );
          const usesDarkCanvas = schemes.includes("dark")
            && (!schemes.includes("light") || prefersDark);
          values.push(
            usesDarkCanvas ? "rgb(0, 0, 0)" : "rgb(255, 255, 255)"
          );
        }
        return values;
      };

      const report = () => {
        timer = null;
        const values = detectedColors();
        const serializedValue = JSON.stringify(values);
        if (serializedValue === lastValue) return;
        lastValue = serializedValue;
        try {
          window.webkit.messageHandlers.sniffBrowserPageTheme.postMessage(values);
        } catch (_) {}
      };

      const schedule = () => {
        if (timer !== null) clearTimeout(timer);
        timer = setTimeout(report, 160);
      };

      const observesThemeTarget = target => {
        if (target === document.body || target === document.documentElement) {
          return true;
        }
        return target instanceof HTMLMetaElement
          && String(target.getAttribute("name")).toLowerCase() === "theme-color";
      };

      const mutationAffectsTheme = mutation => {
        if (observesThemeTarget(mutation.target)) return true;
        if (mutation.type === "attributes"
            && mutation.target instanceof Element
            && (mutation.attributeName === "class"
              || mutation.attributeName === "style")) {
          return true;
        }
        const containsThemeMeta = node => {
          if (!(node instanceof Element)) return false;
          if (observesThemeTarget(node)) return true;
          return Boolean(
            node.querySelector
              && node.querySelector('meta[name="theme-color" i]')
          );
        };
        return Array.from(mutation.addedNodes || []).some(containsThemeMeta)
          || Array.from(mutation.removedNodes || []).some(containsThemeMeta);
      };

      const observedMediaQueries = new Map();
      const synchronizeMediaQueries = () => {
        if (!window.matchMedia) return;
        const pageQueries = Array.from(
            document.querySelectorAll('meta[name="theme-color" i][media]')
          )
          .map(meta => meta.getAttribute("media"))
          .filter(Boolean);
        const activeQueries = new Set([
          "(prefers-color-scheme: dark)",
          ...pageQueries
        ]);
        for (const [query, mediaQuery] of observedMediaQueries) {
          if (activeQueries.has(query)) continue;
          mediaQuery.removeEventListener("change", schedule);
          observedMediaQueries.delete(query);
        }
        for (const query of activeQueries) {
          if (observedMediaQueries.has(query)) continue;
          const mediaQuery = window.matchMedia(query);
          mediaQuery.addEventListener("change", schedule);
          observedMediaQueries.set(query, mediaQuery);
        }
      };

      const start = () => {
        synchronizeMediaQueries();
        report();
        if (!document.documentElement) return;
        const observer = new MutationObserver(mutations => {
          if (mutations.some(mutationAffectsTheme)) {
            synchronizeMediaQueries();
            schedule();
          }
        });
        observer.observe(document.documentElement, {
          attributes: true,
          childList: true,
          subtree: true,
          attributeFilter: ["content", "class", "style", "media"]
        });
      };

      window.__sniffBrowserReportTheme = report;
      if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", start, { once: true });
      } else {
        start();
      }
      window.addEventListener("load", schedule, { once: true });
      window.addEventListener("scroll", schedule, { passive: true });
      window.addEventListener("resize", schedule, { passive: true });
    })();
    """
}

@MainActor
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
  weak var delegate: WKScriptMessageHandler?

  init(delegate: WKScriptMessageHandler) {
    self.delegate = delegate
  }

  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    delegate?.userContentController(
      userContentController,
      didReceive: message
    )
  }
}
