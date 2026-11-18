"""Building blocks of a report page, `output/<REPORT>/<REPORT>.html`. Figures and videos are linked by paths
relative to that folder, so the page opens from disk in a browser."""
import csv
import html
import json
import os
import tomllib
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
REPORT = os.environ["REPORT"]
HERE = PROJECT / "output" / REPORT
CONFIG = tomllib.loads((PROJECT / "reports" / REPORT / "report.toml").read_text())

CSS = """
:root { --fg: #1d2433; --muted: #5b6475; --line: #d9dee7; --soft: #f4f6f9; --accent: #1f5f99; }
* { box-sizing: border-box; }
body { margin: 0; background: #fff; color: var(--fg);
       font: 16px/1.55 system-ui, -apple-system, "Segoe UI", Roboto, "Noto Sans", sans-serif; }
main { max-width: 1060px; margin: 0 auto; padding: 32px 16px 96px; }
h1 { font-size: 1.85rem; line-height: 1.2; margin: 0 0 .3rem; }
h2 { font-size: 1.35rem; margin: 2.8rem 0 .8rem; padding-top: 1.2rem; border-top: 1px solid var(--line); }
h3 { font-size: 1.08rem; margin: 2rem 0 .5rem; }
p, li { max-width: 46rem; }
a { color: var(--accent); }
.meta { color: var(--muted); margin: 0 0 1.2rem; }
nav.toc { background: var(--soft); border-radius: 6px; padding: .7rem 1rem; font-size: .95rem; }
nav.toc ul.plain { margin: .2rem 0; padding-left: 1.3rem; list-style: none; }
nav.toc ol { margin: .2rem 0; padding-left: 1.3rem; }
figure { margin: 1.4rem 0 1.8rem; }
figure img, figure video { display: block; width: 100%; height: auto; border: 1px solid var(--line); border-radius: 4px; }
figure.fit img, figure video { width: auto; max-width: 100%; max-height: 90vh; margin: 0 auto; }
figcaption { color: var(--muted); font-size: .92rem; margin-top: .45rem; max-width: 46rem; }
figcaption b { color: var(--fg); }
table { border-collapse: collapse; font-size: .92rem; margin: .8rem 0 1.4rem; }
caption { text-align: left; color: var(--muted); padding-bottom: .4rem; }
caption b { color: var(--fg); }
th, td { padding: .32rem .65rem; border-bottom: 1px solid var(--line); text-align: left; vertical-align: top; }
th { background: var(--soft); font-weight: 600; }
td.num, th.num { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
.wide { overflow-x: auto; }
.switch { display: flex; flex-wrap: wrap; gap: .4rem; margin: .4rem 0 .6rem; align-items: center; }
.switch button { font: inherit; font-size: .9rem; padding: .25rem .8rem; border: 1px solid var(--line);
                 border-radius: 999px; background: #fff; cursor: pointer; }
.switch button.on { background: var(--accent); border-color: var(--accent); color: #fff; }
.switch select { font: inherit; font-size: .9rem; padding: .2rem .4rem; }
ol.summary li { margin-bottom: .45rem; }
"""

SWITCH_JS = """
document.querySelectorAll('[data-videos]').forEach(fig => {
  const sources = JSON.parse(fig.dataset.videos), video = fig.querySelector('video');
  let variable = Object.keys(sources)[0], part = fig.querySelector('select')?.value;
  const show = () => { video.src = sources[variable][part ?? Object.keys(sources[variable])[0]]; };
  fig.querySelectorAll('button').forEach(b => b.onclick = () => {
    fig.querySelectorAll('button').forEach(x => x.classList.toggle('on', x === b));
    variable = b.dataset.variable; show();
  });
  fig.querySelector('select')?.addEventListener('change', e => { part = e.target.value; show(); });
});
"""


def read(name):
    """A CSV of the report's `tables/`, or else of its `data/`."""
    path = HERE / "tables" / name
    with open(path if path.exists() else HERE / "data" / name) as f:
        return list(csv.DictReader(f))


def signed(x, digits=2):
    return f"{float(x):+.{digits}f}".replace("-", "−")


def plain(x, digits=2):
    return f"{float(x):.{digits}f}".replace("-", "−")


def thousands(n):
    return f"{int(n):,}".replace(",", " ")


class Page:
    """An HTML page built in order. `figures` names every figure and video in the order they appear, so the
    text can link one (`fig`) before it is placed."""

    def __init__(self, title, meta, figures):
        self.title, self.meta = title, meta
        self.number = {key: n + 1 for n, key in enumerate(figures)}
        self.body, self.sections = [], []
        self.sub, self.sub_of = 0, 0

    def fig(self, key):
        return f'<a href="#fig-{key}">Fig. {self.number[key]}</a>'

    def h2(self, anchor, text, numbered=True):
        """A section; an unnumbered one stays out of the count and heads the contents list."""
        self.sections.append((anchor, text, numbered))
        n = sum(1 for *_, num in self.sections if num)
        self.body.append(f'<h2 id="{anchor}">{f"{n}. " if numbered else ""}{text}</h2>')

    def h3(self, text):
        """A subsection, numbered within a numbered section (3.1, 3.2, ...)."""
        if self.sections and self.sections[-1][2]:
            n = sum(1 for *_, num in self.sections if num)
            self.sub = self.sub + 1 if self.sub_of == n else 1
            self.sub_of = n
            text = f"{n}.{self.sub} {text}"
        self.body.append(f"<h3>{text}</h3>")

    def p(self, text):
        self.body.append(f"<p>{text}</p>")

    def items(self, items, ordered=False, cls=""):
        tag = "ol" if ordered else "ul"
        attr = f' class="{cls}"' if cls else ""
        self.body.append(f"<{tag}{attr}>" + "".join(f"<li>{i}</li>" for i in items) + f"</{tag}>")

    def table(self, header, rows, caption="", numeric=()):
        """`numeric` holds the indices of right-aligned columns."""
        cell = lambda tag, i, c: f'<{tag}{" class=num" if i in numeric else ""}>{c}</{tag}>'  # noqa: E731
        head = "<tr>" + "".join(cell("th", i, h) for i, h in enumerate(header)) + "</tr>"
        body = "".join("<tr>" + "".join(cell("td", i, c) for i, c in enumerate(r)) + "</tr>" for r in rows)
        cap = f"<caption>{caption}</caption>" if caption else ""
        self.body.append(f'<div class="wide"><table>{cap}{head}{body}</table></div>')

    def _caption(self, key, text):
        return f"<figcaption><b>Fig. {self.number[key]}.</b> {text}</figcaption>"

    def figure(self, key, path, caption, fit=False):
        """An image; clicking it opens the full-size file. `fit` keeps a tall image within the window's height."""
        cls = ' class="fit"' if fit else ""
        self.body.append(f'<figure id="fig-{key}"{cls}><a href="{path}"><img src="{path}" alt="Fig. {self.number[key]}" '
                         f'loading="lazy"></a>{self._caption(key, caption)}</figure>')

    def video(self, key, path, caption):
        self.body.append(f'<figure id="fig-{key}"><video controls preload="metadata" src="{path}"></video>'
                         f"{self._caption(key, caption)}</figure>")

    def video_switch(self, key, sources, parts, caption):
        """Videos chosen with a button per variable and, with more than one part, a menu of parts.
        `sources[variable label][part label]` is a path; `parts` lists the part labels in order."""
        buttons = "".join(f'<button data-variable="{html.escape(v)}"{" class=on" if i == 0 else ""}>{v}</button>'
                          for i, v in enumerate(sources))
        menu = ("<select>" + "".join(f"<option>{p}</option>" for p in parts) + "</select>") if len(parts) > 1 else ""
        first = sources[next(iter(sources))][parts[0]]
        self.body.append(f"<figure id=\"fig-{key}\" data-videos='{html.escape(json.dumps(sources))}'>"
                         f'<div class="switch">{buttons}{menu}</div>'
                         f'<video controls preload="metadata" src="{first}"></video>{self._caption(key, caption)}</figure>')

    def write(self, path):
        link = lambda a, t: f'<a href="#{a}">{t}</a>'  # noqa: E731
        plain = "".join(f"<li>{link(a, t)}</li>" for a, t, num in self.sections if not num)
        toc = ("".join(f"<ul class=plain>{plain}</ul>" for _ in [0] if plain)
               + "<ol>" + "".join(f"<li>{link(a, t)}</li>" for a, t, num in self.sections if num) + "</ol>")
        Path(path).write_text(
            f'<!doctype html><html lang="en"><head><meta charset="utf-8">'
            f'<meta name="viewport" content="width=device-width, initial-scale=1">'
            f"<title>{self.title}</title><style>{CSS}</style></head><body><main>"
            f'<h1>{self.title}</h1><p class="meta">{self.meta}</p>'
            f'<nav class="toc">{toc}</nav>' + "\n".join(self.body) +
            f"</main><script>{SWITCH_JS}</script></body></html>\n")
