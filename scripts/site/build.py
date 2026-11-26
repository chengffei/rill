#!/usr/bin/env python3
"""Builds the Rill website (docs/) from index.template.html in eight languages, as the app.

The template carries English and Simplified Chinese inline (<span lang="en"> / <span lang="zh">).
The other six languages are looked up by the English text in scripts/site/i18n/<lang>.json; a
missing entry stops the build instead of falling back to English. The head (title, description,
Open Graph, hreflang, JSON-LD) is generated per language, the FAQ structured data is parsed from
the page, and the sitemap is written too. Run: python3 scripts/site/build.py
"""
import datetime
import html
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).parent
TEMPLATE = HERE / "index.template.html"
SITE = "https://chengffei.github.io/rill/"
DOWNLOAD = "https://github.com/chengffei/rill/releases/latest"

VERSION = re.search(r"<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>",
                    (ROOT / "Resources/Info.plist").read_text()).group(1)
TODAY = datetime.date.today()

MONTHS = {
    "fr": ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"],
    "de": ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"],
    "es": ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"],
}
DATES = {
    "en": f"{TODAY:%-d %B %Y}",
    "zh": f"{TODAY.year} 年 {TODAY.month} 月 {TODAY.day} 日",
    "zh-Hant": f"{TODAY.year} 年 {TODAY.month} 月 {TODAY.day} 日",
    "ja": f"{TODAY.year}年{TODAY.month}月{TODAY.day}日",
    "ko": f"{TODAY.year}년 {TODAY.month}월 {TODAY.day}일",
    "fr": f"{TODAY.day} {MONTHS['fr'][TODAY.month - 1]} {TODAY.year}",
    "de": f"{TODAY.day}. {MONTHS['de'][TODAY.month - 1]} {TODAY.year}",
    "es": f"{TODAY.day} de {MONTHS['es'][TODAY.month - 1]} de {TODAY.year}",
}

# Order = order of the language menu. dir is the folder under docs (English at the root).
PAGES = {
    "en": dict(dir="", html_lang="en", og_locale="en_US", name="English",
        title="Rill — See Your Mac’s Power Draw, Live, in the Menu Bar",
        description="A free, open-source menu bar app for MacBook. Live watts from the charger, into the battery and used by the Mac, apps using significant energy, memory pressure, and 7 days of history. No special permissions.",
        og_description="Where your Mac’s power goes, live. A free, open-source menu bar app for MacBook.",
        app_description="A free, open-source macOS menu bar app that shows live charger, battery and system power, per-app energy and memory, and power history."),
    "zh": dict(dir="zh/", html_lang="zh-Hans", og_locale="zh_CN", name="简体中文",
        title="Rill — 在菜单栏实时查看 Mac 的功率",
        description="免费开源的 MacBook 菜单栏工具。实时显示充电器输入、电池充放电和整机功率，列出大量耗电的应用、内存压力，保留 7 天历史。不需要特殊权限。",
        og_description="电从哪来，用到了哪，实时看见。免费开源的 MacBook 菜单栏工具。",
        app_description="免费开源的 macOS 菜单栏工具，实时显示充电器、电池与整机功率，按应用统计能耗与内存，并保留功率历史。"),
}
# Other languages: title and descriptions from i18n/<lang>.json under "_meta".
OTHER = {
    "zh-Hant": dict(dir="zh-hant/", html_lang="zh-Hant", og_locale="zh_TW", name="繁體中文"),
    "ja": dict(dir="ja/", html_lang="ja", og_locale="ja_JP", name="日本語"),
    "ko": dict(dir="ko/", html_lang="ko", og_locale="ko_KR", name="한국어"),
    "fr": dict(dir="fr/", html_lang="fr", og_locale="fr_FR", name="Français"),
    "de": dict(dir="de/", html_lang="de", og_locale="de_DE", name="Deutsch"),
    "es": dict(dir="es/", html_lang="es", og_locale="es_ES", name="Español"),
}
for lang, page in OTHER.items():
    meta = json.loads((HERE / "i18n" / f"{lang}.json").read_text())["_meta"]
    page.update(meta)
    PAGES[lang] = page

# Screenshots: the Dashboard in each language (launched with -language <code>).
SHOT_CODE = {"en": "en", "zh": "zh-hans", "zh-Hant": "zh-hant", "ja": "ja", "ko": "ko", "fr": "fr", "de": "de", "es": "es"}
for lang, page in PAGES.items():
    code = SHOT_CODE[lang]
    page["shot"] = f"overview-{code}.png"
    page["history_shot"] = f"history-{code}.png"
    page["url"] = SITE + page["dir"]
    page["out"] = ROOT / "docs" / page["dir"] / "index.html"
    page["base"] = "../" if page["dir"] else ""
    page["updated"] = DATES[lang]
LANG_SPAN = r'<span lang="{}">(.*?)</span>'


def localize(text, lang):
    """只留本语言的文案。英文、简中直接取模板；其他语言按英文原文查译文表。"""
    if lang == "en":
        text = re.sub(LANG_SPAN.format("zh"), "", text, flags=re.S)
        return re.sub(LANG_SPAN.format("en"), r"\1", text, flags=re.S)
    if lang == "zh":
        text = re.sub(LANG_SPAN.format("en"), "", text, flags=re.S)
        return re.sub(LANG_SPAN.format("zh"), r"\1", text, flags=re.S)
    table = json.loads((HERE / "i18n" / f"{lang}.json").read_text())
    table.pop("_meta", None)
    missing = sorted({s for s in re.findall(LANG_SPAN.format("en"), text, re.S) if s not in table})
    assert not missing, f"{lang}: {len(missing)} untranslated, first: {missing[0][:60]!r}"
    text = re.sub(LANG_SPAN.format("zh"), "", text, flags=re.S)
    return re.sub(LANG_SPAN.format("en"), lambda m: table[m.group(1)], text, flags=re.S)


def language_menu(current):
    """导航里的语言菜单：当前语言作标题，展开列出其余七种；不依赖 JS"""
    links = []
    for lang, page in PAGES.items():
        if lang == current:
            continue
        href = page["base"] and "" or ""
        # 从当前页到目标页的相对路径：根页直接写目录名，子目录页先回上一级
        href = ("../" if PAGES[current]["dir"] else "") + page["dir"]
        if not href:
            href = "./" if not PAGES[current]["dir"] else "../"
        links.append(f'<a href="{href}" hreflang="{page["html_lang"]}" lang="{page["html_lang"]}">{page["name"]}</a>')
    return ('<details class="langs"><summary class="lang-toggle" aria-label="Language">'
            f'{PAGES[current]["name"]}</summary><div class="langs-menu">' + "".join(links) + "</div></details>")


def plain(fragment):
    return html.unescape(re.sub(r"<[^>]+>", "", fragment)).strip()


def faq_items(page_html):
    pattern = r"<details><summary>(.*?)</summary><p>(.*?)</p></details>"
    return [(plain(q), plain(a)) for q, a in re.findall(pattern, page_html, re.S)]


def head(lang, page, faq):
    esc = lambda s: html.escape(s, quote=True)
    app = {
        "@context": "https://schema.org",
        "@type": "SoftwareApplication",
        "name": "Rill",
        "description": page["app_description"],
        "applicationCategory": "UtilitiesApplication",
        "applicationSubCategory": "Power monitor",
        "operatingSystem": "macOS 26 or later",
        "softwareVersion": VERSION,
        "dateModified": TODAY.isoformat(),
        "inLanguage": page["html_lang"],
        "url": page["url"],
        "downloadUrl": DOWNLOAD,
        "screenshot": SITE + "images/" + page["shot"],
        "image": SITE + "images/icon.png",
        "license": "https://www.gnu.org/licenses/gpl-3.0.html",
        "isAccessibleForFree": True,
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
        "author": {"@type": "Person", "name": "Felix", "url": "https://github.com/chengffei"},
        "codeRepository": "https://github.com/chengffei/rill",
    }
    faq_ld = {
        "@context": "https://schema.org",
        "@type": "FAQPage",
        "inLanguage": page["html_lang"],
        "mainEntity": [
            {"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}}
            for q, a in faq
        ],
    }
    ld = lambda d: '<script type="application/ld+json">\n' + json.dumps(d, ensure_ascii=False, indent=2) + "\n</script>"
    alternates = [f'<link rel="alternate" hreflang="{p["html_lang"]}" href="{p["url"]}">' for p in PAGES.values()]
    alternates.append(f'<link rel="alternate" hreflang="x-default" href="{SITE}">')
    locales = [f'<meta property="og:locale:alternate" content="{p["og_locale"]}">' for l, p in PAGES.items() if l != lang]
    return "\n".join([
        f"<title>{esc(page['title'])}</title>",
        f'<meta name="description" content="{esc(page["description"])}">',
        f'<link rel="canonical" href="{page["url"]}">',
        *alternates,
        f'<link rel="alternate" type="text/plain" title="llms.txt" href="{SITE}llms.txt">',
        '<meta name="theme-color" content="#ffffff">',
        '<meta property="og:type" content="website">',
        '<meta property="og:site_name" content="Rill">',
        f'<meta property="og:url" content="{page["url"]}">',
        f'<meta property="og:title" content="{esc(page["title"])}">',
        f'<meta property="og:description" content="{esc(page["og_description"])}">',
        f'<meta property="og:image" content="{SITE}images/og.png">',
        '<meta property="og:image:width" content="1200">',
        '<meta property="og:image:height" content="630">',
        '<meta property="og:image:alt" content="Rill showing power flowing from the charger to the Mac">',
        f'<meta property="og:locale" content="{page["og_locale"]}">',
        *locales,
        '<meta name="twitter:card" content="summary_large_image">',
        f'<meta name="twitter:title" content="{esc(page["title"])}">',
        f'<meta name="twitter:description" content="{esc(page["og_description"])}">',
        f'<meta name="twitter:image" content="{SITE}images/og.png">',
        f'<link rel="icon" type="image/png" sizes="64x64" href="{page["base"]}images/favicon.png">',
        f'<link rel="apple-touch-icon" href="{page["base"]}images/apple-touch-icon.png">',
        ld(app),
        ld(faq_ld),
    ])


def sitemap():
    links = "".join(f'\n    <xhtml:link rel="alternate" hreflang="{p["html_lang"]}" href="{p["url"]}"/>' for p in PAGES.values())
    links += f'\n    <xhtml:link rel="alternate" hreflang="x-default" href="{SITE}"/>'
    urls = "".join(f"\n  <url>\n    <loc>{p['url']}</loc>\n    <lastmod>{TODAY.isoformat()}</lastmod>{links}\n  </url>" for p in PAGES.values())
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" '
            f'xmlns:xhtml="http://www.w3.org/1999/xhtml">{urls}\n</urlset>\n')


def main():
    template = TEMPLATE.read_text()
    for lang, page in PAGES.items():
        body = localize(template, lang)
        out = (body
               .replace("{{HTML_LANG}}", page["html_lang"])
               .replace("{{BASE}}", page["base"])
               .replace("{{LANG_TOGGLE}}", language_menu(lang))
               .replace("{{SHOT}}", page["shot"])
               .replace("{{HISTORY_SHOT}}", page["history_shot"])
               .replace("{{VERSION}}", VERSION)
               .replace("{{UPDATED}}", TODAY.isoformat())
               .replace("{{UPDATED_EN}}", page["updated"])
               .replace("{{UPDATED_ZH}}", page["updated"])
               .replace("{{UPDATED_L}}", page["updated"]))
        out = out.replace("{{HEAD}}", head(lang, page, faq_items(out)))
        assert "{{" not in out and "<span lang=" not in out, lang
        page["out"].parent.mkdir(parents=True, exist_ok=True)
        page["out"].write_text(out)
        print(f"{lang}: {page['out'].relative_to(ROOT)} ({len(out):,} bytes, {len(faq_items(out))} FAQ)")
    (ROOT / "docs/sitemap.xml").write_text(sitemap())
    print("sitemap: docs/sitemap.xml")


if __name__ == "__main__":
    main()
