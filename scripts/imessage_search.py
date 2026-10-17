#!/usr/bin/env python3
"""Search iMessage text exports for messages between people within a timeframe.

Export format (one message per block):

    %b %d, %Y %I:%M:%S %p[ optional suffix, e.g. (Read by you after 36 seconds)]
    {{ entity }}
    {{ message_body }}

Results are printed to the terminal (colorized when appropriate) or exported
to a self-contained, filterable HTML page with --html.
"""

import argparse
import importlib
import json
import os
import re
import sys
import webbrowser
from datetime import datetime, timedelta
from pathlib import Path

HEADER = re.compile(r'^([A-Z][a-z]{2} \d{1,2}, \d{4} \d{1,2}:\d{2}:\d{2} [AP]M)\b(.*)$')
TS_FMT = '%b %d, %Y %I:%M:%S %p'

# Modules needed only for specific features: {feature: [(module, pip package)]}
OPTIONAL_DEPS = {
    'html': [('jinja2', 'jinja2')],
}


def require(feature):
    """Import the modules a feature needs, or warn and exit gracefully if any are missing."""
    missing, modules = [], {}
    for module, package in OPTIONAL_DEPS[feature]:
        try:
            modules[module] = importlib.import_module(module)
        except ImportError:
            missing.append(package)
    if missing:
        print(f'Warning: --{feature} requires missing Python module(s): {", ".join(missing)}\n'
              f'Install with: {sys.executable} -m pip install {" ".join(missing)}', file=sys.stderr)
        sys.exit(2)
    return modules


# --- Date / time parsing --------------------------------------------------------------------------

def add_month(d):
    return d.replace(year=d.year + 1, month=1) if d.month == 12 else d.replace(month=d.month + 1)


def parse_range(s):
    """Return (start, end) where end is exclusive, covering the period the string names."""
    s = s.strip()
    if re.fullmatch(r'\d{4}', s):
        start = datetime(int(s), 1, 1)
        return start, start.replace(year=start.year + 1)
    if re.fullmatch(r'\d{4}-\d{1,2}', s):
        start = datetime.strptime(s, '%Y-%m')
        return start, add_month(start)
    for fmt, step in (('%Y-%m-%d %H:%M:%S', timedelta(seconds=1)),
                      ('%Y-%m-%d %H:%M', timedelta(minutes=1)),
                      ('%Y-%m-%d', timedelta(days=1)),
                      ('%b %d, %Y %I:%M:%S %p', timedelta(seconds=1)),
                      ('%b %d, %Y', timedelta(days=1)),
                      ('%b %Y', None)):
        try:
            start = datetime.strptime(s, fmt)
        except ValueError:
            continue
        return start, (start + step) if step else add_month(start)
    sys.exit(f'Unrecognized date: {s!r}')


def parse_time(s, inclusive_end=False):
    """Return seconds since midnight. An end time without seconds covers its whole minute (hour for '9pm')."""
    t = re.sub(r'\s+', '', s.strip().upper())
    for fmt, span in (('%H:%M:%S', 0), ('%H:%M', 59), ('%H', 3599),
                      ('%I:%M:%S%p', 0), ('%I:%M%p', 59), ('%I%p', 3599)):
        try:
            d = datetime.strptime(t, fmt)
        except ValueError:
            continue
        secs = d.hour * 3600 + d.minute * 60 + d.second
        return secs + span if inclusive_end else secs
    sys.exit(f'Unrecognized time: {s!r}')


# --- Parsing & filtering --------------------------------------------------------------------------

class Message:
    __slots__ = ('ts', 'suffix', 'entity', 'body', 'lines')

    def __init__(self, ts, suffix, lines):
        while len(lines) > 1 and not lines[-1].strip():
            lines.pop()
        self.ts = ts
        self.suffix = suffix.strip()
        self.lines = lines
        self.entity = lines[1].strip() if len(lines) > 1 else ''
        self.body = '\n'.join(lines[2:])

    @property
    def raw(self):
        return '\n'.join(self.lines)


def records(fh):
    cur = None
    for line in fh:
        line = line.rstrip('\n')
        m = HEADER.match(line)
        if m:
            if cur:
                yield Message(*cur)
            cur = (datetime.strptime(m.group(1), TS_FMT), m.group(2), [line])
        elif cur is not None:
            cur[2].append(line)
    if cur:
        yield Message(*cur)


class Filters:
    def __init__(self, args):
        self.people = {p.strip().lower() for p in args.person if p.strip()}
        self.start = self.end = None
        if args.on:
            self.start, self.end = parse_range(args.on)
        if args.date_from:
            self.start = parse_range(args.date_from)[0]
        if args.date_to:
            self.end = parse_range(args.date_to)[1]
        # --after/--before are exclusive at the exact instant given; --time-from/--time-to are inclusive.
        self.tstart = self.tend = None
        if args.time_from:
            self.tstart = parse_time(args.time_from)
        if args.after:
            self.tstart = (parse_time(args.after) + 1) % 86400
        if args.time_to:
            self.tend = parse_time(args.time_to, inclusive_end=True)
        if args.before:
            self.tend = (parse_time(args.before) - 1) % 86400
        self.rx = re.compile(args.match, re.I) if args.match else None

    def in_time_window(self, ts):
        if self.tstart is None and self.tend is None:
            return True
        secs = ts.hour * 3600 + ts.minute * 60 + ts.second
        lo = 0 if self.tstart is None else self.tstart
        hi = 86399 if self.tend is None else self.tend
        if lo <= hi:
            return lo <= secs <= hi
        return secs >= lo or secs <= hi  # window wraps past midnight, e.g. 10pm-2am

    def __call__(self, msg):
        if self.people and msg.entity.lower() not in self.people:
            return False
        if self.start and msg.ts < self.start:
            return False
        if self.end and msg.ts >= self.end:
            return False
        if not self.in_time_window(msg.ts):
            return False
        if self.rx and not self.rx.search(msg.body):
            return False
        return True


def sources(args):
    """Yield (label, path) pairs; label/path are None when reading stdin."""
    src = args.file
    if not args.dir or (src and src != '-'):
        yield (None, None) if src in (None, '', '-') else (src, os.path.expanduser(src))
    for d in args.dir:
        root = Path(os.path.expanduser(d))
        if not root.is_dir():
            print(f'Not a directory: {d}', file=sys.stderr)
            continue
        for p in sorted(root.rglob(args.glob)):
            if p.is_file():
                yield str(p), str(p)


def search(args, flt):
    """Yield (label, [matching messages]) per input source."""
    for label, path in sources(args):
        try:
            fh = sys.stdin if path is None else open(path, encoding='utf-8', errors='replace')
        except OSError as e:
            print(e, file=sys.stderr)
            continue
        with fh:
            yield label, [m for m in records(fh) if flt(m)]


# --- Terminal output ------------------------------------------------------------------------------

class Painter:
    RESET, BOLD, DIM = '\033[0m', '\033[1m', '\033[2m'
    FILE, TS, MATCH, ME = '\033[1;35m', '\033[33m', '\033[1;31m', '\033[1;32m'
    PEOPLE = ['\033[1;34m', '\033[1;36m', '\033[1;33m', '\033[1;35m', '\033[1;91m', '\033[1;94m']

    def __init__(self, enabled, rx):
        self.enabled, self.rx, self.people = enabled, rx, {}

    def __call__(self, code, text):
        return f'{code}{text}{self.RESET}' if self.enabled and text else text

    def person(self, name):
        key = name.lower()
        if key == 'me':
            return self.ME
        return self.people.setdefault(key, self.PEOPLE[len(self.people) % len(self.PEOPLE)])

    def highlight(self, line):
        if not (self.enabled and self.rx):
            return line
        return self.rx.sub(lambda m: self(self.MATCH, m.group(0)), line)

    def message(self, msg):
        m = HEADER.match(msg.lines[0])
        out = [self(self.TS, m.group(1)) + self(self.DIM, m.group(2))]
        if len(msg.lines) > 1:
            out.append(self(self.person(msg.entity), msg.lines[1]))
        out.extend(self.highlight(l) for l in msg.lines[2:])
        return '\n'.join(out)

    def file_header(self, label):
        rule = '=' * min(max(len(label) + 8, 40), 120)
        return '\n'.join(self(self.FILE, l) for l in (rule, f'==> {label} <==', rule))


def print_results(args, results, flt):
    if args.color == 'always':
        enabled = True
    elif args.color == 'never':
        enabled = False
    else:
        enabled = sys.stdout.isatty() and not os.environ.get('NO_COLOR')
    paint = Painter(enabled, flt.rx)
    total = 0
    for label, msgs in results:
        total += len(msgs)
        if args.count:
            if not label:
                print(len(msgs))
            elif msgs or not args.dir:
                print(f'{paint(paint.FILE, label)}: {paint(paint.BOLD, str(len(msgs)))}')
            continue
        if msgs and label:
            print(paint.file_header(label) + '\n')
        for msg in msgs:
            print(paint.message(msg) + '\n')
    return total


# --- HTML export ----------------------------------------------------------------------------------

def describe_filters(args):
    parts = []
    if args.person:
        parts.append('People: ' + ', '.join(args.person))
    if args.on:
        parts.append(f'On: {args.on}')
    if args.date_from:
        parts.append(f'From: {args.date_from}')
    if args.date_to:
        parts.append(f'To: {args.date_to}')
    if args.time_from:
        parts.append(f'Time from: {args.time_from}')
    if args.after:
        parts.append(f'After: {args.after}')
    if args.time_to:
        parts.append(f'Time to: {args.time_to}')
    if args.before:
        parts.append(f'Before: {args.before}')
    if args.match:
        parts.append(f'Match: /{args.match}/i')
    return parts


def export_html(args, results):
    jinja2 = require('html')['jinja2']
    conversations, people, total = [], set(), 0
    for label, msgs in results:
        if not msgs:
            continue
        total += len(msgs)
        conversations.append({
            'label': label or '(stdin)',
            'name': Path(label).stem if label else '(stdin)',
            'messages': [{
                'ts': m.ts.isoformat(),
                'day': m.ts.strftime('%A, %B %d, %Y'),
                'time': m.ts.strftime('%I:%M:%S %p').lstrip('0'),
                'suffix': m.suffix.strip('() '),
                'entity': m.entity,
                'body': m.body,
                'me': m.entity.lower() == 'me',
            } for m in msgs],
        })
        people.update(m.entity for m in msgs)

    template = jinja2.Environment(autoescape=True).from_string(HTML_TEMPLATE)
    html = template.render(
        title=args.title,
        generated=datetime.now().strftime('%b %d, %Y %I:%M %p'),
        filters=describe_filters(args),
        total=total,
        people=sorted(people, key=lambda p: (p.lower() != 'me', p.lower())),
        conversations=conversations,
        initial_regex=args.match or '',
    )
    out = Path(os.path.expanduser(args.html))
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html, encoding='utf-8')
    print(f'Wrote {total} message(s) from {len(conversations)} conversation(s) to {out}', file=sys.stderr)
    if args.open:
        webbrowser.open(out.resolve().as_uri())
    return total


HTML_TEMPLATE = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{{ title }}</title>
<style>
  :root {
    --bg: #f5f5f7; --panel: #ffffff; --text: #1d1d1f; --muted: #6e6e73; --border: #e3e3e8;
    --me: #0a84ff; --me-text: #ffffff; --them: #e9e9eb; --them-text: #1d1d1f;
    --mark: #ffd60a; --mark-text: #1d1d1f; --danger: #ff3b30; --accent: #0a84ff;
    --shadow: 0 1px 2px rgba(0,0,0,.06), 0 4px 16px rgba(0,0,0,.05);
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #000000; --panel: #1c1c1e; --text: #f5f5f7; --muted: #98989d; --border: #2c2c2e;
      --them: #2c2c2e; --them-text: #f5f5f7; --shadow: none;
    }
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--text);
         font: 15px/1.4 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif; }
  header.top { max-width: 860px; margin: 0 auto; padding: 32px 16px 12px; }
  header.top h1 { margin: 0 0 4px; font-size: 28px; letter-spacing: -.02em; }
  .meta { color: var(--muted); font-size: 13px; }
  .chips { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 10px; }
  .chip { font-size: 12px; padding: 3px 9px; border-radius: 999px; background: var(--panel);
          border: 1px solid var(--border); color: var(--muted); }
  .toolbar { position: sticky; top: 0; z-index: 10; background: color-mix(in srgb, var(--bg) 85%, transparent);
             backdrop-filter: saturate(180%) blur(16px); -webkit-backdrop-filter: saturate(180%) blur(16px);
             border-bottom: 1px solid var(--border); }
  .toolbar-inner { max-width: 860px; margin: 0 auto; padding: 10px 16px; display: flex; flex-wrap: wrap;
                   gap: 8px 14px; align-items: center; }
  .search { flex: 1 1 280px; position: relative; }
  .search input { width: 100%; font: 14px ui-monospace, SFMono-Regular, Menlo, monospace; padding: 9px 12px 9px 30px;
                  border-radius: 10px; border: 1px solid var(--border); background: var(--panel); color: var(--text);
                  outline: none; }
  .search input:focus { border-color: var(--accent); box-shadow: 0 0 0 3px color-mix(in srgb, var(--accent) 25%, transparent); }
  .search input.invalid { border-color: var(--danger); box-shadow: 0 0 0 3px color-mix(in srgb, var(--danger) 25%, transparent); }
  .search::before { content: "/"; position: absolute; left: 12px; top: 50%; transform: translateY(-50%);
                    color: var(--muted); font: 14px ui-monospace, monospace; }
  .toolbar label { font-size: 13px; color: var(--muted); display: inline-flex; gap: 5px; align-items: center;
                   cursor: pointer; user-select: none; }
  .people { display: flex; flex-wrap: wrap; gap: 6px; width: 100%; }
  .person { font-size: 12px; padding: 4px 10px; border-radius: 999px; border: 1px solid var(--border);
            background: var(--panel); color: var(--text); cursor: pointer; }
  .person[aria-pressed="false"] { opacity: .4; text-decoration: line-through; }
  .person .dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%; margin-right: 6px; }
  .status { font-size: 12px; color: var(--muted); width: 100%; }
  .status .err { color: var(--danger); }
  main { max-width: 860px; margin: 0 auto; padding: 16px 16px 64px; }
  details.convo { background: var(--panel); border: 1px solid var(--border); border-radius: 16px;
                  box-shadow: var(--shadow); margin-bottom: 20px; overflow: hidden; }
  details.convo > summary { list-style: none; cursor: pointer; padding: 14px 18px; display: flex; gap: 10px;
                            align-items: baseline; border-bottom: 1px solid var(--border); }
  details.convo > summary::-webkit-details-marker { display: none; }
  details.convo > summary::before { content: "▸"; color: var(--muted); transition: transform .15s; }
  details.convo[open] > summary::before { transform: rotate(90deg); }
  .convo-name { font-weight: 600; }
  .convo-path { color: var(--muted); font-size: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
                flex: 1; min-width: 0; }
  .convo-count { color: var(--muted); font-size: 12px; white-space: nowrap; }
  .thread { padding: 8px 18px 18px; }
  .day { text-align: center; color: var(--muted); font-size: 12px; font-weight: 600; margin: 18px 0 8px; }
  .msg { display: flex; flex-direction: column; align-items: flex-start; margin: 2px 0; }
  .msg.me { align-items: flex-end; }
  .sender { font-size: 11px; font-weight: 600; margin: 8px 12px 2px; }
  .bubble { max-width: min(75%, 560px); padding: 8px 13px; border-radius: 18px; background: var(--them);
            color: var(--them-text); white-space: pre-wrap; overflow-wrap: anywhere; }
  .msg.me .bubble { background: var(--me); color: var(--me-text); }
  .bubble:empty::after { content: "(no text)"; font-style: italic; opacity: .6; }
  .stamp { font-size: 11px; color: var(--muted); margin: 2px 12px 4px; }
  mark { background: var(--mark); color: var(--mark-text); border-radius: 3px; padding: 0 1px; }
  .hidden { display: none !important; }
  .empty { text-align: center; color: var(--muted); padding: 48px 0; }
  kbd { font: 11px ui-monospace, monospace; border: 1px solid var(--border); border-radius: 4px; padding: 0 4px; }
</style>
</head>
<body>
<header class="top">
  <h1>{{ title }}</h1>
  <div class="meta">{{ total }} message{{ '' if total == 1 else 's' }} across {{ conversations|length }}
    conversation{{ '' if conversations|length == 1 else 's' }} &middot; generated {{ generated }}</div>
  {% if filters %}<div class="chips">{% for f in filters %}<span class="chip">{{ f }}</span>{% endfor %}</div>{% endif %}
</header>

<div class="toolbar"><div class="toolbar-inner">
  <div class="search"><input id="q" type="search" placeholder="Filter messages by regex…  (press / to focus)"
       autocomplete="off" spellcheck="false" value="{{ initial_regex }}"></div>
  <label><input id="case" type="checkbox"> Match case</label>
  <label><input id="sender" type="checkbox"> Include sender</label>
  <label><input id="expand" type="checkbox" checked> Expand all</label>
  <div class="people" id="people"></div>
  <div class="status" id="status"></div>
</div></div>

<main id="main"></main>
<div class="empty hidden" id="empty">No messages match the current filters.</div>

<script id="data" type="application/json">{{ conversations|tojson }}</script>
<script id="people-data" type="application/json">{{ people|tojson }}</script>
<script>
(() => {
  const convos = JSON.parse(document.getElementById('data').textContent);
  const people = JSON.parse(document.getElementById('people-data').textContent);
  const $ = (id) => document.getElementById(id);
  const el = (tag, cls, text) => {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  };

  const colorFor = (name) => {
    if (name.toLowerCase() === 'me') return 'var(--me)';
    let h = 0;
    for (const c of name) h = (h * 31 + c.charCodeAt(0)) >>> 0;
    return `hsl(${h % 360} 65% 50%)`;
  };

  // Sender toggles
  const enabled = new Set(people.map((p) => p.toLowerCase()));
  for (const p of people) {
    const b = el('button', 'person');
    b.type = 'button';
    b.setAttribute('aria-pressed', 'true');
    const dot = el('span', 'dot');
    dot.style.background = colorFor(p);
    b.append(dot, p);
    b.addEventListener('click', () => {
      const key = p.toLowerCase();
      const on = enabled.has(key);
      on ? enabled.delete(key) : enabled.add(key);
      b.setAttribute('aria-pressed', String(!on));
      apply();
    });
    $('people').append(b);
  }

  // Render conversations once; filtering toggles visibility.
  const rows = [];
  const sections = [];
  for (const c of convos) {
    const det = el('details', 'convo');
    det.open = true;
    const sum = el('summary');
    const count = el('span', 'convo-count');
    sum.append(el('span', 'convo-name', c.name), el('span', 'convo-path', c.label), count);
    const thread = el('div', 'thread');
    det.append(sum, thread);
    const section = { det, count, days: [], total: c.messages.length };
    let day = null;
    for (const m of c.messages) {
      if (!day || day.label !== m.day) {
        day = { label: m.day, node: el('div', 'day', m.day), rows: [] };
        thread.append(day.node);
        section.days.push(day);
      }
      const node = el('div', 'msg' + (m.me ? ' me' : ''));
      const sender = el('div', 'sender', m.entity);
      sender.style.color = colorFor(m.entity);
      const bubble = el('div', 'bubble', m.body);
      const stamp = el('div', 'stamp', m.time + (m.suffix ? ' · ' + m.suffix : ''));
      stamp.title = m.ts;
      node.append(sender, bubble, stamp);
      thread.append(node);
      const row = { m, node, bubble, key: m.entity.toLowerCase() };
      day.rows.push(row);
      rows.push(row);
    }
    sections.push(section);
    $('main').append(det);
  }

  const highlight = (bubble, text, rx) => {
    if (!rx) { bubble.textContent = text; return; }
    bubble.textContent = '';
    let last = 0;
    rx.lastIndex = 0;
    for (let m; (m = rx.exec(text)); ) {
      if (m[0] === '') { rx.lastIndex++; continue; }
      bubble.append(text.slice(last, m.index), el('mark', null, m[0]));
      last = m.index + m[0].length;
    }
    bubble.append(text.slice(last));
  };

  function apply() {
    const q = $('q').value;
    let rx = null, error = null;
    if (q) {
      try { rx = new RegExp(q, 'g' + ($('case').checked ? '' : 'i')); }
      catch (e) { error = e.message; }
    }
    $('q').classList.toggle('invalid', !!error);
    const withSender = $('sender').checked;
    let shown = 0, shownConvos = 0;
    for (const s of sections) {
      let sShown = 0;
      for (const d of s.days) {
        let dShown = 0;
        for (const r of d.rows) {
          let ok = enabled.has(r.key);
          if (ok && rx) {
            rx.lastIndex = 0;
            const hay = withSender ? r.m.entity + '\n' + r.m.body : r.m.body;
            ok = rx.test(hay);
          }
          r.node.classList.toggle('hidden', !ok);
          if (ok) { dShown++; highlight(r.bubble, r.m.body, rx); }
        }
        d.node.classList.toggle('hidden', !dShown);
        sShown += dShown;
      }
      s.det.classList.toggle('hidden', !sShown);
      s.count.textContent = sShown === s.total ? `${s.total} messages` : `${sShown} of ${s.total} messages`;
      shown += sShown;
      if (sShown) shownConvos++;
    }
    $('empty').classList.toggle('hidden', shown > 0);
    const status = $('status');
    status.textContent = '';
    if (error) status.append(el('span', 'err', 'Invalid regex: ' + error));
    else status.append(`Showing ${shown} of ${rows.length} messages in ${shownConvos} conversation${shownConvos === 1 ? '' : 's'}`);
  }

  let timer;
  $('q').addEventListener('input', () => { clearTimeout(timer); timer = setTimeout(apply, 120); });
  $('case').addEventListener('change', apply);
  $('sender').addEventListener('change', apply);
  $('expand').addEventListener('change', (e) => sections.forEach((s) => { s.det.open = e.target.checked; }));
  document.addEventListener('keydown', (e) => {
    if (e.key === '/' && document.activeElement !== $('q')) { e.preventDefault(); $('q').focus(); $('q').select(); }
    if (e.key === 'Escape' && document.activeElement === $('q')) { $('q').value = ''; apply(); }
  });
  apply();
})();
</script>
</body>
</html>
'''


# --- CLI ------------------------------------------------------------------------------------------

def build_parser(prog):
    p = argparse.ArgumentParser(
        prog=prog,
        description='Search an iMessage text export for messages between people within a timeframe.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f'''Date formats: 2025 | 2025-07 | 2025-07-04 | 'Jul 2025' | 'Jul 04, 2025' | '2025-07-04 14:30[:00]'
Time formats: 21:00 | 21:00:15 | 9pm | '9:30 PM'

Examples:
  {prog} -f messages.txt -p Jim -p Me --on 2026-07-29
  {prog} -f messages.txt -p Jim -p Me --from 2025-07 --to 2026
  cat messages.txt | {prog} -p Jim -p Me --on 2025
  {prog} -d ~/imessage_export -p Jim -p Me --on 'Jul 2026'
  {prog} -f messages.txt --on 2026 --time-from 10pm --time-to 2am
  {prog} -d ~/imessage_export -p Jim -p Me --on 2026 --html ~/Desktop/jim.html --open''')

    src = p.add_argument_group('input')
    src.add_argument('-f', '--file', help="export file to search (omit or '-' to read stdin)")
    src.add_argument('-d', '--dir', action='append', default=[],
                     help='search files in this folder recursively (repeatable)')
    src.add_argument('-g', '--glob', default='*.txt', help='filename pattern used with --dir (default: %(default)s)')

    flt = p.add_argument_group('filters')
    flt.add_argument('-p', '--person', action='append', default=[],
                     help='sender to include (repeatable, case-insensitive; omit to match everyone)')
    flt.add_argument('--on', help='a year, month, or day')
    flt.add_argument('--from', dest='date_from', help='inclusive start date[time]')
    flt.add_argument('--to', dest='date_to', help='inclusive end; a bare day/month/year covers the whole period')
    start = flt.add_mutually_exclusive_group()
    start.add_argument('--time-from', help='only messages at/after this time of day')
    start.add_argument('--after', help='only messages strictly after this time of day')
    end = flt.add_mutually_exclusive_group()
    end.add_argument('--time-to', help='only messages at/before this time of day '
                                       '(wraps past midnight if earlier than the start time)')
    end.add_argument('--before', help='only messages strictly before this time of day')
    flt.add_argument('-m', '--match', help='only messages whose body matches this regex (case-insensitive)')

    out = p.add_argument_group('output')
    out.add_argument('-c', '--count', action='store_true', help='print only the number of matches, per file')
    out.add_argument('--color', choices=('auto', 'always', 'never'), default='auto',
                     help='colorize terminal output (default: auto = on a terminal and NO_COLOR unset)')
    out.add_argument('--no-color', dest='color', action='store_const', const='never', help='same as --color never')
    out.add_argument('--html', metavar='PATH', help='export matches to a filterable single-page HTML file')
    out.add_argument('--title', default='iMessage Conversations', help='page title for --html (default: %(default)s)')
    out.add_argument('--open', action='store_true', help='open the --html file in the default browser')
    return p


def main(argv=None):
    prog = os.environ.get('IMESSAGE_SEARCH_PROG') or Path(sys.argv[0]).name
    parser = build_parser(prog)
    args = parser.parse_args(argv)
    if args.match:
        try:
            re.compile(args.match)
        except re.error as e:
            parser.error(f'invalid --match regex: {e}')
    if args.open and not args.html:
        parser.error('--open requires --html')
    if args.html and args.count:
        parser.error('--html and --count cannot be combined')
    if (not args.file or args.file == '-') and not args.dir and sys.stdin.isatty():
        parser.print_help()
        return 0
    if args.html:
        require('html')  # fail fast before reading any input

    flt = Filters(args)
    results = search(args, flt)
    total = export_html(args, results) if args.html else print_results(args, results, flt)
    return 0 if total else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
    except BrokenPipeError:
        sys.stderr.close()
        sys.exit(0)
