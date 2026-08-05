#!/usr/bin/env python3
"""Render iOS-style content blocking center previews to PNG (Playwright + Chromium)."""

from __future__ import annotations

import pathlib

from playwright.sync_api import sync_playwright

OUT_DIR = pathlib.Path(__file__).resolve().parent


def esc(text: str) -> str:
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


CSS = """
:root {
  --bg: #F2F2F7;
  --card: #FFFFFF;
  --separator: rgba(60,60,67,0.29);
  --label: #000000;
  --secondary: rgba(60,60,67,0.6);
  --tertiary: rgba(60,60,67,0.3);
  --blue: #007AFF;
  --green: #34C759;
  --indigo: #5856D6;
  --orange: #FF9500;
  --red: #FF3B30;
  --teal: #30B0C7;
  --purple: #AF52DE;
  --pink: #FF2D55;
  --nav: rgba(249,249,249,0.86);
}
* { box-sizing: border-box; -webkit-font-smoothing: antialiased; }
html, body { margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display",
    "PingFang SC", "Helvetica Neue", sans-serif;
  background: var(--bg);
  color: var(--label);
  width: 390px;
}
.screen { position: relative; background: var(--bg); padding-bottom: 70px; }

/* Status bar */
.statusbar {
  position: sticky; top: 0; z-index: 20;
  display: flex; align-items: center; justify-content: space-between;
  height: 47px; padding: 0 26px 0 32px;
  background: var(--nav); backdrop-filter: blur(24px); -webkit-backdrop-filter: blur(24px);
  font-size: 15px; font-weight: 600; color: var(--label);
}
.statusbar .time { font-size: 16px; font-weight: 700; }
.statusbar .icons { display: flex; align-items: center; gap: 6px; }
.pill { width: 18px; height: 11px; border: 1.5px solid currentColor; border-radius: 3px; position: relative; }
.pill::after { content:""; position:absolute; inset:1.5px; right:3px; background: currentColor; border-radius: 1px; }
.batt { width: 24px; height: 12px; border: 1.5px solid currentColor; border-radius: 3px; position: relative; }
.batt::after { content:""; position:absolute; left:1.5px; top:1.5px; bottom:1.5px; width:60%; background: currentColor; border-radius: 1px; }

/* Nav bar */
.navbar {
  position: sticky; top: 47px; z-index: 19;
  background: var(--nav); backdrop-filter: blur(24px); -webkit-backdrop-filter: blur(24px);
  padding: 4px 16px 10px;
}
.navrow { display: flex; align-items: center; gap: 8px; height: 32px; }
.back {
  color: var(--blue); font-size: 17px; font-weight: 400;
  display: flex; align-items: center; gap: 2px;
}
.back svg { width: 12px; height: 20px; }
.navtitle { font-size: 34px; font-weight: 800; letter-spacing: -0.3px; margin-top: 6px; }
.navtitle.small { font-size: 26px; font-weight: 800; }
.navaction { margin-left: auto; color: var(--blue); font-size: 17px; }

/* Grouped sections */
.section { margin: 18px 16px 0; }
.section:first-of-type { margin-top: 10px; }
.section-header {
  font-size: 13px; font-weight: 600; color: var(--secondary);
  text-transform: uppercase; letter-spacing: 0.2px;
  margin: 0 16px 7px; text-transform: none; font-weight: 500;
}
.group {
  background: var(--card); border-radius: 10px;
  overflow: hidden;
}
.row {
  display: flex; align-items: center; gap: 12px;
  min-height: 44px; padding: 9px 16px;
  position: relative;
}
.row + .row::before {
  content: ""; position: absolute; left: 60px; right: 0; top: 0;
  height: 0.5px; background: var(--separator);
}
.row .icon {
  width: 29px; height: 29px; border-radius: 6.5px;
  display: flex; align-items: center; justify-content: center;
  flex: none;
}
.row .icon svg { width: 18px; height: 18px; }
.row .text { flex: 1; min-width: 0; }
.row .title { font-size: 17px; line-height: 1.25; }
.row .subtitle { font-size: 13px; color: var(--secondary); margin-top: 1px; }
.row .value { color: var(--secondary); font-size: 17px; }
.row .chev { color: rgba(60,60,67,0.28); flex: none; }
.chev svg { width: 9px; height: 16px; display: block; }

.switch {
  width: 51px; height: 31px; border-radius: 16px; flex: none;
  background: var(--green); position: relative;
  box-shadow: inset 0 0 0 0.5px rgba(0,0,0,0.08);
}
.switch::after {
  content: ""; position: absolute; top: 2px; left: 22px;
  width: 27px; height: 27px; border-radius: 50%;
  background: #fff; box-shadow: 0 1px 3px rgba(0,0,0,0.25);
}
.switch.off { background: rgba(120,120,128,0.32); }
.switch.off::after { left: 2px; }

/* Stats cards */
.stats { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; padding: 12px; background: var(--card); border-radius: 10px; }
.stat { background: rgba(120,120,128,0.08); border-radius: 12px; padding: 12px 14px; }
.stat .num { font-size: 20px; font-weight: 800; letter-spacing: -0.3px; }
.stat .lbl { font-size: 12px; color: var(--secondary); margin-top: 3px; }
.stat .ic { width: 22px; height: 22px; margin-bottom: 6px; }

.footer { font-size: 13px; color: var(--secondary); margin: 8px 20px 0; line-height: 1.35; }
.section + .footer { margin-top: 6px; }

/* Small colored dot badges */
.badge {
  font-size: 12px; font-weight: 600; color: var(--blue);
  background: rgba(0,122,255,0.12); border-radius: 7px;
  padding: 2px 8px; flex: none;
}
.badge.gray { color: var(--secondary); background: rgba(120,120,128,0.12); }

/* Search */
.search {
  margin: 10px 16px 0; height: 36px; border-radius: 10px;
  background: rgba(120,120,128,0.12);
  display: flex; align-items: center; gap: 8px; padding: 0 12px;
}
.search svg { width: 16px; height: 16px; color: var(--secondary); }
.search span { color: var(--secondary); font-size: 17px; }

/* Editor */
.editor {
  margin: 10px 16px 0; border-radius: 12px; overflow: hidden;
  background: #1E1E24; color: #D7D7E2;
  font-family: "SF Mono", ui-monospace, Menlo, monospace; font-size: 12px;
  line-height: 1.7; padding: 14px 14px 18px;
}
.editor .ln { color: #6B6B76; display: inline-block; width: 22px; text-align: right; margin-right: 12px; user-select: none; }
.k { color: #FF7AB2; } .s { color: #A8E28C; } .c { color: #5B5B66; } .f { color: #82AAFF; } .n { color: #DCDCAA; }

/* Buttons */
.btn {
  display: flex; align-items: center; justify-content: center; gap: 6px;
  height: 44px; border-radius: 12px; font-size: 17px; font-weight: 600;
  background: var(--blue); color: #fff; margin-top: 10px;
}
.btn.secondary { background: rgba(120,120,128,0.12); color: var(--blue); }
.btn.danger { background: rgba(120,120,128,0.12); color: var(--red); }

/* Log rows */
.logrow { display: flex; align-items: center; gap: 10px; min-height: 48px; padding: 8px 16px; position: relative; }
.logrow + .logrow::before { content:""; position:absolute; left:60px; right:0; top:0; height:0.5px; background: var(--separator); }
.logrow .icon { width: 26px; height: 26px; border-radius: 6px; display:flex; align-items:center; justify-content:center; flex:none; }
.logrow .icon svg { width: 15px; height: 15px; }
.logrow .text { flex:1; min-width:0; }
.logrow .url { font-size: 15px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.logrow .meta { font-size: 12px; color: var(--secondary); margin-top: 1px; }
.tag { font-size: 11px; font-weight: 600; padding: 2px 6px; border-radius: 6px; flex: none; }
.tag.blocked { color: var(--red); background: rgba(255,59,48,0.12); }
.tag.ok { color: var(--green); background: rgba(52,199,89,0.12); }
.tag.miss { color: var(--secondary); background: rgba(120,120,128,0.12); }

/* Dark */
body.dark {
  --bg: #000000;
  --card: #1C1C1E;
  --separator: rgba(84,84,88,0.6);
  --label: #FFFFFF;
  --secondary: rgba(235,235,245,0.6);
  --tertiary: rgba(235,235,245,0.3);
  --blue: #0A84FF;
  --nav: rgba(22,22,24,0.86);
}
body.dark .switch.off { background: rgba(120,120,128,0.32); }
body.dark .chev { color: rgba(235,235,245,0.2); }
"""


ICONS = {
    "shield": '<svg viewBox="0 0 24 24" fill="none"><path d="M12 3l7 3v5c0 4.6-3 8.4-7 10-4-1.6-7-5.4-7-10V6l7-3z" fill="currentColor"/><path d="M9.2 11.8l2 2 3.6-3.8" stroke="#fff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    "shield.slash": '<svg viewBox="0 0 24 24" fill="none"><path d="M12 3l7 3v5c0 4.6-3 8.4-7 10-4-1.6-7-5.4-7-10V6l7-3z" fill="currentColor"/><path d="M8 12.2l3 3 4.6-5" stroke="#fff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" opacity=".55"/></svg>',
    "hand": '<svg viewBox="0 0 24 24" fill="none"><path d="M8 11V5.5a1.4 1.4 0 012.8 0V10M10.8 10V4.8a1.4 1.4 0 012.8 0V10M13.6 10V6a1.4 1.4 0 012.8 0v5.5c0 3.5-1.3 5.7-3.3 7.2-1 .8-2.3 1.2-3.7 1.2-3 0-5-1.6-5.6-4.6L3 11.2a1.4 1.4 0 012.6-.9l.9 1.9" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    "person2": '<svg viewBox="0 0 24 24" fill="none"><circle cx="9" cy="8" r="3.4" fill="currentColor"/><path d="M2.5 19c.6-3 3-4.6 6.5-4.6S14.9 16 15.5 19" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/><circle cx="17" cy="9" r="2.6" fill="currentColor"/><path d="M17.6 14.6c2.6.3 3.9 1.9 4.2 4" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></svg>',
    "globe.badge": '<svg viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="1.9"/><path d="M3.5 12h17M12 3c2.8 2.6 4.2 5.6 4.2 9S14.8 18.4 12 21c-2.8-2.6-4.2-5.6-4.2-9S9.2 5.6 12 3z" stroke="currentColor" stroke-width="1.7"/></svg>',
    "list": '<svg viewBox="0 0 24 24" fill="none"><path d="M5 6.5h14M5 12h14M5 17.5h9" stroke="currentColor" stroke-width="2.1" stroke-linecap="round"/></svg>',
    "gauge": '<svg viewBox="0 0 24 24" fill="none"><path d="M4 15a8 8 0 1116 0" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/><path d="M12 15l4-4.5" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><circle cx="12" cy="15" r="1.6" fill="currentColor"/></svg>',
    "gearshape": '<svg viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="3.1" stroke="currentColor" stroke-width="1.9"/><path d="M12 3.5l.9 2.3 2.5-.4 1.2 2.1 2.4.8-.2 2.5 2 .8-1 2.2 1 2.2-2 .8.2 2.5-2.4.8-1.2 2.1-2.5-.4-.9 2.3-2.2-.4-.9-2.3-2.4.4-1.2-2.1-2.4-.8.2-2.5-2-.8 1-2.2-1-2.2 2-.8-.2-2.5 2.4-.8 1.2-2.1 2.4.4.9-2.3 2.2.4z" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/></svg>',
    "arrow.up.down": '<svg viewBox="0 0 24 24" fill="none"><path d="M7 4v16M7 4L4 7.5M7 4l3 3.5M17 20V4M17 20l-3-3.5M17 20l3-3.5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    "magnify": '<svg viewBox="0 0 24 24" fill="none"><circle cx="11" cy="11" r="6.5" stroke="currentColor" stroke-width="2"/><path d="M16 16l4.5 4.5" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
    "plus": '<svg viewBox="0 0 24 24" fill="none"><path d="M12 5v14M5 12h14" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></svg>',
    "doc": '<svg viewBox="0 0 24 24" fill="none"><path d="M7 3.5h7l4 4V20.5H7z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M14 3.5V8h4M10 13h5M10 16.5h5" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>',
    "chevron": '<svg viewBox="0 0 12 20" fill="none"><path d="M2 2l7.5 8L2 18" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    "check": '<svg viewBox="0 0 24 24" fill="none"><path d="M4.5 12.5l5 5 10-11" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    "arrow.cw": '<svg viewBox="0 0 24 24" fill="none"><path d="M20 12a8 8 0 11-2.3-5.7M20 3v4.5h-4.5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    "trash": '<svg viewBox="0 0 24 24" fill="none"><path d="M4.5 7h15M9 7V4.8h6V7M6.5 7l.8 13h9.4l.8-13M10 11v5.5M14 11v5.5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    "img": '<svg viewBox="0 0 24 24" fill="none"><rect x="3.5" y="4.5" width="17" height="15" rx="2" stroke="currentColor" stroke-width="1.8"/><circle cx="9" cy="10" r="1.7" fill="currentColor"/><path d="M4 17l5-5 4 4 3-3 4 4" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    "doc2": '<svg viewBox="0 0 24 24" fill="none"><path d="M7 3.5h7l4 4V20.5H7z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M14 3.5V8h4M10 13h5M10 16.5h5" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>',
    "css": '<svg viewBox="0 0 24 24" fill="none"><path d="M4.5 3.5h15l-1.4 14.2L12 21.5l-6.1-3.8z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M8.5 9h7l-.3 4.5-3.2 1.5-3.2-1.5" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    "js": '<svg viewBox="0 0 24 24" fill="none"><path d="M4 3.5h16l-1.2 14.8L12 21.5l-6.8-3.2z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M9.5 9l1 7M14.5 9l-1 7M10.5 12.5h3" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    "link": '<svg viewBox="0 0 24 24" fill="none"><path d="M10 14l4-4M7.5 16.5l-1.7 1.7a3.2 3.2 0 01-4.5-4.5L5.4 9.6a3.2 3.2 0 014.5 0M16.5 7.5l1.7-1.7a3.2 3.2 0 014.5 4.5l-4.1 4.1a3.2 3.2 0 01-4.5 0" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
}


def icon(name: str, color: str = "currentColor") -> str:
    svg = ICONS[name]
    return f'<span class="icon" style="background:{color}1f;color:{color}">{svg}</span>'


def switch_html(on: bool = True) -> str:
    return f'<span class="switch{" off" if not on else ""}"></span>'


def page(title: str, body: str, dark: bool = False, small_title: bool = False,
         right: str = "") -> str:
    cls = "dark" if dark else ""
    return f"""<!DOCTYPE html><html><head><meta charset="utf-8"><style>{CSS}</style></head>
<body class="{cls}"><div class="screen">
<div class="statusbar"><span class="time">9:41</span><span>内容拦截</span>
<span class="icons"><span class="pill"></span><span class="batt"></span></span></div>
<div class="navbar"><div class="navrow">
<span class="back"><svg viewBox="0 0 12 20" fill="none"><path d="M9.5 2L2 10l7.5 8" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>设置</span>
<span class="navaction">{right}</span>
</div><div class="navtitle{' small' if small_title else ''}">{esc(title)}</div></div>
{body}</div></body></html>"""


def section_header(text: str) -> str:
    return f'<div class="section-header">{esc(text)}</div>'


def group(rows: str) -> str:
    return f'<div class="group">{rows}</div>'


def row(text: str, sub: str = "", value: str = "", ic: str = "",
        color: str = "#007AFF", sw: bool | None = None, chev: bool = True) -> str:
    icon_html = icon(ic, color) if ic else ""
    sw_html = switch_html(sw) if sw is not None else ""
    value_html = f'<span class="value">{esc(value)}</span>' if value else ""
    chev_html = '<span class="chev"><svg viewBox="0 0 9 16" fill="none"><path d="M1.5 1.5l6 6.5-6 6.5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg></span>' if chev else ""
    sub_html = f'<div class="subtitle">{esc(sub)}</div>' if sub else ""
    return (f'<div class="row">{icon_html}<div class="text"><div class="title">{esc(text)}</div>'
            f'{sub_html}</div>{value_html}{sw_html}{chev_html}</div>')


def footer(text: str) -> str:
    return f'<div class="footer">{esc(text)}</div>'


# ---------------------------------------------------------------- main screen

def main_screen(dark: bool = False) -> str:
    stats = f"""
    <div class="stats">
      <div class="stat"><svg class="ic" viewBox="0 0 24 24" fill="none"><path d="M12 3l7 3v5c0 4.6-3 8.4-7 10-4-1.6-7-5.4-7-10V6l7-3z" fill="#34C759"/><path d="M9.2 11.8l2 2 3.6-3.8" stroke="#fff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg><div class="num">12,438</div><div class="lbl">已拦截</div></div>
      <div class="stat"><svg class="ic" viewBox="0 0 24 24" fill="none"><path d="M4 12.5l6-7 4 4 6-6" stroke="#007AFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><path d="M4 19h16" stroke="#007AFF" stroke-width="2" stroke-linecap="round"/></svg><div class="num">186 MB</div><div class="lbl">节省流量</div></div>
      <div class="stat"><svg class="ic" viewBox="0 0 24 24" fill="none"><path d="M13 3l-7 10h6l-1 8 7-10h-6l1-8z" fill="#FF9500"/></svg><div class="num">31%</div><div class="lbl">平均提速</div></div>
      <div class="stat"><svg class="ic" viewBox="0 0 24 24" fill="none"><path d="M6 4h12l1.5 3.5L12 20 4.5 7.5z" stroke="#8E8E93" stroke-width="1.8" stroke-linejoin="round"/><path d="M4.5 7.5h15" stroke="#8E8E93" stroke-width="1.6"/></svg><div class="num">64,281</div><div class="lbl">当前规则</div></div>
    </div>"""

    rules_rows = "".join([
        row("广告过滤", "AdGuard Base · EasyList 等 6 个规则", ic="shield", color="#007AFF", sw=True),
        row("隐私保护", "追踪器、指纹、Cookie 与统计", ic="hand", color="#34C759", sw=True),
        row("社交媒体过滤", "自动隐藏分享、评论与推荐内容", ic="person2", color="#5856D6", sw=True),
        row("恶意网站", "恶意软件、钓鱼、挖矿与诈骗", ic="globe.badge", color="#FF3B30", sw=True),
        row("Cookie 拦截", "拒绝 Cookie、隐藏横幅、阻止 SDK", ic="doc2", color="#FF9500", sw=True),
        row("DNS 拦截", "黑名单、白名单、DoH/DoT", ic="link", color="#30B0C7", sw=True),
        row("自定义规则", "16 条 · 命中 1,024 次", ic="css", color="#AF52DE", value="16", sw=True),
    ])

    update_rows = "".join([
        row("立即更新", "AdGuard Base v2.4.81.60 · 中文 v2.1.63.4", ic="arrow.cw", color="#007AFF"),
        row("自动更新", "每 5 天 · 后台自动下载", ic="gearshape", color="#8E8E93", value="5 天"),
    ])

    log_rows = "".join([
        row("请求日志", "今日 1,024 条 · 拦截 68 条", ic="list", color="#30B0C7"),
        row("性能统计", "过滤器命中 · 网站排行 · 资源类型", ic="gauge", color="#FF2D55"),
    ])

    body = f"""
    <div class="section">
      {section_header("")}
      <div class="group">{row("内容拦截", "过滤广告、追踪器、恶意网站、Cookie 横幅及其他网页垃圾内容。", ic="shield", color="#007AFF", sw=True, chev=False)}</div>
      {stats}
      {footer("开启后立即生效，新规则无需重启浏览器。")}
    </div>
    <div class="section">
      {section_header("规则管理")}
      <div class="group">{rules_rows}</div>
    </div>
    <div class="section">
      {section_header("更新规则")}
      <div class="group">{update_rows}</div>
      <div class="section" style="margin:14px 0 0">
        {section_header("网站白名单")}
        <div class="group">{row("白名单网站", "3 个网站 · 不执行任何过滤", ic="shield.slash", color="#8E8E93", value="3")}</div>
      </div>
      <div class="section" style="margin:14px 0 0">
        {section_header("日志与统计")}
        <div class="group">{log_rows}</div>
      </div>
      <div class="section" style="margin:14px 0 0">
        {section_header("高级")}
        <div class="group">{row("高级设置", "开发者模式 · 调试 · 导入导出", ic="gearshape", color="#8E8E93")}</div>
      </div>
    </div>
    """
    return page("内容拦截", body, dark=dark)


# ---------------------------------------------------------------- ad filter page

def adfilter_screen(dark: bool = False) -> str:
    rules = [
        ("AdGuard Base", "广告过滤基础规则，覆盖全球主流站点", "21,403 条", "今天 08:12", "AdGuard", "GPL-3.0", "2.4.81.60", True),
        ("EasyList", "经典广告过滤规则，AdGuard 的基础之一", "12,048 条", "5 天前", "EasyList", "CC BY-SA 3.0", "2026.08.01", True),
        ("EasyPrivacy", "阻止追踪器与用户画像收集", "8,421 条", "5 天前", "EasyList", "CC BY-SA 3.0", "2026.08.01", True),
        ("AdGuard Mobile", "移动端专用广告规则", "6,205 条", "3 天前", "AdGuard", "GPL-3.0", "1.3.12", True),
        ("AdBlock Warning Removal", "隐藏反广告拦截提示", "512 条", "12 天前", "AdBlock", "GPL-3.0", "1.2.4", True),
        ("Chinese Filter", "中文网站广告与元素隐藏规则", "6,020 条", "今天 08:12", "AdGuard", "GPL-3.0", "2.1.63.4", False),
    ]
    rows = []
    for name, desc, count, updated, author, lic, ver, on in rules:
        sub = f"{desc} · {count} · {updated}"
        rows.append(row(name, sub, ic="shield", color="#007AFF", sw=on))
    body = f"""
    <div class="section">
      <div class="group">{rows[0]}</div>
    </div>
    <div class="section">
      {section_header("官方规则列表")}
      <div class="group">{"".join(rows[1:])}</div>
      {footer("每个规则可独立开关与排序；点击查看详情、更新日志与许可证。")}
    </div>
    """
    return page("广告过滤", body, dark=dark, right="编辑")


# ---------------------------------------------------------------- custom rules page

def custom_screen(dark: bool = False) -> str:
    items = [
        ("隐藏站内推广", "hl365.com##.article-top-banner", True, 42, "12:04"),
        ("屏蔽随机广告域名", "||ydsplay.com^", True, 96, "11:52"),
        ("隐藏水平横幅", "##.horizontal-banner", True, 31, "10:41"),
        ("允许支付域名", "@@||alipay.com^", True, 8, "昨天"),
        ("视频网站去广告", "||vcdn.example.com/ad/", False, 0, "7 月 28 日"),
    ]
    rows = []
    for name, content, on, hits, when in items:
        sub = f'<span style="font-family:ui-monospace,Menlo,monospace;font-size:12px;color:#8E8E93">{esc(content)}</span> · 命中 {hits}'
        rows.append(row(name, sub, ic="doc", color="#AF52DE", sw=on))
    body = f"""
    <div class="search"><svg viewBox="0 0 24 24" fill="none"><circle cx="11" cy="11" r="6.5" stroke="currentColor" stroke-width="2"/><path d="M16 16l4.5 4.5" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg><span>搜索规则</span></div>
    <div class="section" style="margin-top:12px">
      {section_header("自定义规则 · 5")}
      <div class="group">{"".join(rows)}</div>
      {footer("支持长按排序、多选批量操作；点击规则进入编辑器。")}
    </div>
    """
    return page("自定义规则", body, dark=dark, right='<svg viewBox="0 0 24 24" fill="none" style="width:22px;height:22px;display:inline-block;vertical-align:-4px"><path d="M12 5v14M5 12h14" stroke="#007AFF" stroke-width="2.2" stroke-linecap="round"/></svg>')


# ---------------------------------------------------------------- editor page

def editor_screen(dark: bool = False) -> str:
    body = f"""
    <div class="section">
      {section_header("规则类型")}
      <div class="group">
        {row("元素隐藏", "css-display-none", ic="css", color="#AF52DE", sw=True, chev=False)}
      </div>
    </div>
    <div class="editor">
      <div><span class="ln">1</span><span class="c">// 隐藏 hl365 站内推广横幅</span></div>
      <div><span class="ln">2</span><span class="f">hl365.com</span>##<span class="s">.article-top-banner</span></div>
      <div><span class="ln">3</span></div>
      <div><span class="ln">4</span><span class="c">// 拦截随机广告域名</span></div>
      <div><span class="ln">5</span><span class="k">||</span><span class="n">ydsplay.com</span><span class="k">^</span></div>
    </div>
    {footer("语法已校验通过 · 自动补全建议：hl365.com##.horizontal-banner")}
    <div class="section" style="margin-top:14px">
      <div class="group">
        {row("命中次数", "42", ic="gauge", color="#8E8E93", chev=False)}
        {row("最后命中", "12:04", ic="arrow.cw", color="#8E8E93", chev=False)}
      </div>
    </div>
    <div class="section" style="margin-top:14px">
      <div class="btn">保存</div>
      <div class="btn danger">删除规则</div>
    </div>
    """
    return page("编辑规则", body, dark=dark, small_title=True, right="模板")


# ---------------------------------------------------------------- update page

def update_screen(dark: bool = False) -> str:
    body = f"""
    <div class="section">
      <div class="group">
        {row("当前版本", "AdGuard Base 2.4.81.60 · 中文 2.1.63.4", ic="doc", color="#007AFF", chev=False)}
        {row("更新时间", "今天 08:12", ic="arrow.cw", color="#34C759", chev=False)}
        {row("规则数量", "64,281 条", ic="list", color="#5856D6", chev=False)}
      </div>
    </div>
    <div class="section">
      {section_header("自动更新")}
      <div class="group">
        {row("自动更新", "超过设定天数后，在后台静默下载并应用", ic="gearshape", color="#8E8E93", sw=True, chev=False)}
        {row("更新周期", value="5 天", ic="arrow.cw", color="#FF9500")}
      </div>
      {footer("可选：每天 / 3 天 / 5 天 / 7 天 / 关闭。后台自动下载不会重载当前页面。")}
    </div>
    <div class="section">
      {section_header("更新日志 · v2.4.81.60")}
      <div class="group">
        {row("新增中文站广告规则 3,000+ 条", "", ic="check", color="#34C759", chev=False)}
        {row("优化移动端广告拦截性能", "", ic="check", color="#34C759", chev=False)}
        {row("修复部分站点误拦截", "", ic="check", color="#34C759", chev=False)}
      </div>
    </div>
    <div class="section" style="margin-top:16px">
      <div class="btn"><svg viewBox="0 0 24 24" fill="none" style="width:18px;height:18px"><path d="M20 12a8 8 0 11-2.3-5.7M20 3v4.5h-4.5" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>立即更新</div>
      <div class="btn secondary">恢复默认规则</div>
      <div class="btn danger">清除规则缓存</div>
    </div>
    """
    return page("更新规则", body, dark=dark)


# ---------------------------------------------------------------- log page

def log_screen(dark: bool = False) -> str:
    logs = [
        ("img", "#FF3B30", "https://ydsplay.com/game/banner/285.png", "ydsplay.com", "Image · 1.2 MB", "已拦截", "blocked", "||ydsplay.com^", "4.2 ms"),
        ("css", "#5856D6", "https://hl365.com/assets/style.css", "hl365.com", "CSS · 96 KB", "放行", "ok", "—", "3.1 ms"),
        ("js", "#FF9500", "https://ajxbs.top/stat.js?channel=he", "ajxbs.top", "JS · 41 KB", "已拦截", "blocked", "||ajxbs.top^", "2.8 ms"),
        ("doc2", "#007AFF", "https://hl365.com/archives/217154.html", "hl365.com", "Document · 254 KB", "放行", "ok", "—", "186 ms"),
        ("img", "#34C759", "https://pic.uforxk.cn/hc237/a.gif", "pic.uforxk.cn", "Image · 8 KB", "放行", "ok", "—", "1.9 ms"),
        ("link", "#30B0C7", "https://ws://ads.sng.link/rt?p=1", "ads.sng.link", "WebSocket", "已拦截", "blocked", "||sng.link^", "0.8 ms"),
    ]
    rows = []
    for icn, color, url, dom, typ, status, tag, rule, dur in logs:
        rows.append(f"""
        <div class="logrow">
          <span class="icon" style="background:{color}1f;color:{color}">{ICONS[icn]}</span>
          <div class="text"><div class="url">{esc(url)}</div>
          <div class="meta">{esc(dom)} · {esc(typ)} · {esc(dur)} · {esc(rule)}</div></div>
          <span class="tag {tag}">{esc(status)}</span>
        </div>""")
    body = f"""
    <div class="search"><svg viewBox="0 0 24 24" fill="none"><circle cx="11" cy="11" r="6.5" stroke="currentColor" stroke-width="2"/><path d="M16 16l4.5 4.5" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg><span>搜索 URL 或域名</span></div>
    <div class="section" style="margin-top:12px">
      {section_header("请求日志 · 今日 1,024 · 拦截 68")}
      <div class="group">{"".join(rows)}</div>
      {footer("点击任意条目查看请求头、响应头与命中规则详情。")}
    </div>
    """
    return page("请求日志", body, dark=dark, right="暂停")


def render_all() -> None:
    screens = [
        ("content-blocking-home-light.png", main_screen(False)),
        ("content-blocking-home-dark.png", main_screen(True)),
        ("ad-filter-light.png", adfilter_screen(False)),
        ("custom-rules-light.png", custom_screen(False)),
        ("rule-editor-light.png", editor_screen(False)),
        ("update-rules-light.png", update_screen(False)),
        ("request-log-light.png", log_screen(False)),
    ]
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(
            viewport={"width": 390, "height": 844},
            device_scale_factor=3,
        )
        for filename, html in screens:
            page.set_content(html)
            page.screenshot(
                path=str(OUT_DIR / filename),
                full_page=True,
            )
            print("rendered", filename)
        browser.close()


if __name__ == "__main__":
    render_all()
