#!/usr/bin/env python3
"""Annotate a list of Spanish words with Spanish definitions.

Input is one word per line (a file, stdin, or words given as arguments).
Output is one line per word, in the original order:

    {{ word }}: {{ definition }}

Definitions come from the Spanish Wiktionary, via the kaikki.org wiktextract
extract (CC BY-SA). Inflected forms are resolved to their lemma, e.g.

    abandonaba: (de abandonar) Dejar, desamparar a una persona, animal o cosa. ...

Lookup order per word: exact entry -> inflection pointer -> enclitic pronouns
stripped -> simplemma lemma (optional) -> capitalized (proper nouns) ->
accents removed. Hyphenated compounds are defined part by part.
"""

import argparse
import gzip
import importlib
import json
import os
import re
import shutil
import sys
import unicodedata
import urllib.request
from pathlib import Path

DUMP_URL = 'https://kaikki.org/eswiktionary/raw-wiktextract-data.jsonl.gz'
CACHE_DIR = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache')) / 'bert.zsh'
DEFAULT_DUMP = CACHE_DIR / 'eswiktionary.jsonl.gz'
INDEX_VERSION = 1
NO_DEF = '[sin definición]'

# Glosses that describe an inflection rather than a meaning, e.g. "Gerundio de abanicar, con ..."
FORM_GLOSS = re.compile(
    r'^(?:(?:Primera|Segunda|Tercera) persona|Gerundio|Participio|Infinitivo|Forma\b|'
    r'(?:Femenino|Masculino|Plural|Diminutivo|Aumentativo|Superlativo)\b)', re.I)
LEMMA_IN_GLOSS = re.compile(r'\bde ([a-záéíóúüñ]+)')
NOT_LEMMAS = {'indicativo', 'subjuntivo', 'imperativo', 'singular', 'plural', 'femenino', 'masculino'}
# Senses that just point elsewhere; used only when nothing better exists
WEAK_GLOSS = re.compile(r'^(?:Variante|Grafía|Forma alternativa|Sinónimo|Abreviatura)\b', re.I)

CLITICS = re.compile(r'(?:me|te|se|nos|os|lo|la|los|las|le|les)$')
STRIP_ACCENT = str.maketrans('áéíóú', 'aeiou')

# Modules needed only for specific features: {feature: [(module, pip package)]}
OPTIONAL_DEPS = {
    'lemmatize': [('simplemma', 'simplemma')],
}


def optional(feature):
    """Import the modules a feature needs, or warn and return None if any are missing."""
    missing, modules = [], {}
    for module, package in OPTIONAL_DEPS[feature]:
        try:
            modules[module] = importlib.import_module(module)
        except ImportError:
            missing.append(package)
    if missing:
        print(f'Warning: {feature} fallback disabled; missing Python module(s): {", ".join(missing)}\n'
              f'Install with: {sys.executable} -m pip install {" ".join(missing)}', file=sys.stderr)
        return None
    return modules


# --- Dictionary -----------------------------------------------------------------------------------

def download(url, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + '.part')
    print(f'Downloading {url} -> {dest}', file=sys.stderr)
    with urllib.request.urlopen(url) as r, open(tmp, 'wb') as f:
        total, done = int(r.headers.get('Content-Length') or 0), 0
        while chunk := r.read(1 << 20):
            f.write(chunk)
            done += len(chunk)
            if total and sys.stderr.isatty():
                print(f'\r  {done / 2**20:.0f}/{total / 2**20:.0f} MB', end='', file=sys.stderr)
    if sys.stderr.isatty():
        print(file=sys.stderr)
    tmp.replace(dest)


def clean(gloss):
    return re.sub(r'\s+', ' ', gloss).strip()


def build_index(dump):
    """Reduce the dump to {word: {'d': [definitions], 'l': [lemma candidates]}} for Spanish entries."""
    print(f'Indexing {dump} (one-time; cached afterwards) ...', file=sys.stderr)
    index = {}
    with gzip.open(dump, 'rt', encoding='utf-8') as f:
        for line in f:
            entry = json.loads(line)
            if entry.get('lang_code') != 'es' or not entry.get('word'):
                continue
            rec = index.setdefault(entry['word'], {'d': [], 'w': [], 'l': []})
            for sense in entry.get('senses') or []:
                glosses = [clean(g) for g in sense.get('glosses') or [] if clean(g)]
                if not glosses:
                    continue
                gloss = glosses[-1]  # the most specific gloss for nested senses
                form_of = [x['word'] for x in sense.get('form_of') or [] if x.get('word')]
                if form_of or 'form-of' in (sense.get('tags') or []) or FORM_GLOSS.match(gloss):
                    found = [w for w in reversed(LEMMA_IN_GLOSS.findall(gloss)) if w not in NOT_LEMMAS]
                    for lemma in form_of + found:
                        if lemma not in rec['l'] and lemma != entry['word']:
                            rec['l'].append(lemma)
                else:
                    bucket = rec['w'] if WEAK_GLOSS.match(gloss) else rec['d']
                    if gloss not in bucket:
                        bucket.append(gloss)
    for rec in index.values():
        rec['d'] += rec.pop('w')
    return index


def load_index(dump, rebuild=False):
    cache = dump.with_name(dump.name.split('.')[0] + '.index.json.gz')
    if not rebuild and cache.exists() and cache.stat().st_mtime >= dump.stat().st_mtime:
        with gzip.open(cache, 'rt', encoding='utf-8') as f:
            data = json.load(f)
        if data.get('version') == INDEX_VERSION:
            return data['index']
    index = build_index(dump)
    with gzip.open(cache, 'wt', encoding='utf-8') as f:
        json.dump({'version': INDEX_VERSION, 'index': index}, f, ensure_ascii=False)
    return index


# --- Lookup ---------------------------------------------------------------------------------------

class Definer:
    def __init__(self, index, senses=1, lemma_note=True, lemmatizer=None):
        self.index, self.senses, self.lemma_note, self.lemmatizer = index, senses, lemma_note, lemmatizer

    def resolve(self, word, depth=0):
        """Return (lemma or None, [definitions]) for an exact dictionary key, following inflection pointers."""
        rec = self.index.get(word)
        if not rec:
            return None
        if rec['d']:
            return None, rec['d']
        if depth < 2:
            for lemma in rec['l']:
                hit = self.resolve(lemma, depth + 1)
                if hit:
                    return hit[0] or lemma, hit[1]
        return None

    def strip_clitics(self, word):
        """abanicándose -> abanicando, dándoselo -> dando, abrirle -> abrir."""
        stem = word
        for _ in range(3):
            m = CLITICS.search(stem)
            if not m or m.start() < 2:
                break
            stem = stem[:m.start()]
            # Only verb-like stems: infinitives, gerunds, or imperatives that gained a written accent
            if re.search(r'(?:[aei]r|ír|ndo)$', stem) or stem != stem.translate(STRIP_ACCENT):
                yield stem
                yield stem.translate(STRIP_ACCENT)

    @staticmethod
    def derivations(word):
        """semillas -> semilla, astutamente -> astuta, cochinitos -> cochino, callecita -> calle."""
        if word.endswith('s'):
            yield word[:-1]
            if word.endswith('es'):
                yield word[:-2]
        if word.endswith('mente') and len(word) > 7:
            yield word[:-5]
        for suffix in ('ecit', 'cit', 'it'):
            m = re.fullmatch(rf'(.{{2,}}){suffix}([oa])s?', word)
            if not m:
                continue
            stem, gender = m.groups()
            if suffix == 'ecit':    # callecita -> calle, llavecitas -> llave
                yield stem + 'e'
            elif suffix == 'cit':   # cofrecito -> cofre, mecedorcito -> mecedor
                yield stem
            else:                   # batita -> bata, banquito -> banco, hormiguita -> hormiga, bigotito -> bigote
                yield stem + gender
                yield re.sub(r'qu$', 'c', re.sub(r'gu$', 'g', stem)) + gender
                yield stem + 'e'

    def candidates(self, word):
        yield word
        yield from self.strip_clitics(word)
        yield from self.derivations(word)
        if self.lemmatizer:
            yield self.lemmatizer.lemmatize(word, lang='es')
        yield word.capitalize()
        yield word.translate(STRIP_ACCENT)

    def lookup(self, word):
        """Return (lemma or None, [definitions]) or None."""
        for cand in self.candidates(word):
            hit = self.resolve(cand)
            if hit:
                lemma = hit[0] or (cand if cand.lower() != word else None)
                return lemma, hit[1]
        return None

    def format(self, lemma, defs):
        text = '; '.join(defs[:self.senses])
        return f'(de {lemma}) {text}' if lemma and self.lemma_note else text

    def define(self, word):
        """Return the definition text, or None if nothing matched."""
        hit = self.lookup(word)
        if hit:
            return self.format(*hit)
        parts = [p for p in word.split('-') if p]
        if len(parts) > 1:
            defs = [(p, self.lookup(p)) for p in parts]
            if any(h for _, h in defs):
                return ' | '.join(f'{p} — {self.format(*h) if h else NO_DEF}' for p, h in defs)
        return None


# --- Input ----------------------------------------------------------------------------------------

def repair(word):
    """Undo cp1251 mojibake (e.g. 'corazуn' -> 'corazón'); returns the word unchanged otherwise."""
    if not re.search('[Ѐ-ӿ]', word):
        return word
    try:
        return word.encode('cp1251').decode('cp1252')
    except (UnicodeEncodeError, UnicodeDecodeError):
        return word


def read_words(args):
    if args.words:
        raw = args.words
    elif args.file and args.file != '-':
        raw = Path(args.file).expanduser().read_text(encoding='utf-8').splitlines()
    else:
        raw = sys.stdin.read().splitlines()
    words, seen = [], set()
    for line in raw:
        word = repair(unicodedata.normalize('NFC', line.strip().lower()))
        if word and word not in seen:
            seen.add(word)
            words.append(word)
    return words, len([r for r in raw if r.strip()])


# --- CLI ------------------------------------------------------------------------------------------

def build_parser(prog):
    p = argparse.ArgumentParser(
        prog=prog,
        description='Annotate Spanish words with Spanish definitions as "word: definition".',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f'''Definitions: Spanish Wiktionary via {DUMP_URL} (CC BY-SA),
cached in {CACHE_DIR}. Run once with --download to fetch it (~100 MB).

Examples:
  {prog} --download abandonaba
  {prog} abandonaba abanicándose corazón
  {prog} -f spanish_diction.md -o definitions.md --unmatched missing.txt --stats
  {prog} -f spanish_diction.md --in-place
  cat words.txt | {prog} --senses 2''')

    src = p.add_argument_group('input')
    src.add_argument('words', nargs='*', help='words to define (instead of --file / stdin)')
    src.add_argument('-f', '--file', help="one word per line (omit or '-' to read stdin)")

    dic = p.add_argument_group('dictionary')
    dic.add_argument('--dict', type=Path, default=DEFAULT_DUMP, help='wiktextract dump path (default: %(default)s)')
    dic.add_argument('--download', action='store_true', help='download the dump if missing')
    dic.add_argument('--refresh', action='store_true', help='re-download the dump and rebuild the index')
    dic.add_argument('--rebuild-index', action='store_true', help='rebuild the cached index from the dump')
    dic.add_argument('--no-lemmatizer', action='store_true', help='skip the simplemma fallback')

    out = p.add_argument_group('output')
    out.add_argument('-o', '--output', help='write here instead of stdout')
    out.add_argument('-i', '--in-place', action='store_true', help='overwrite --file, keeping a .bak copy')
    out.add_argument('-n', '--senses', type=int, default=1, help='definitions per word, joined by "; " (default: %(default)s)')
    out.add_argument('--no-lemma', dest='lemma_note', action='store_false',
                     help='omit the "(de lemma)" prefix on inflected forms')
    out.add_argument('--unmatched', metavar='PATH', help='also write words without a definition here')
    out.add_argument('--stats', action='store_true', help='print coverage stats to stderr')
    return p


def main(argv=None):
    prog = os.environ.get('SPANISH_DEFINE_PROG') or Path(sys.argv[0]).name
    parser = build_parser(prog)
    args = parser.parse_args(argv)
    if args.in_place and (not args.file or args.file == '-'):
        parser.error('--in-place requires --file')
    if args.in_place and args.output:
        parser.error('--in-place and --output cannot be combined')
    if args.senses < 1:
        parser.error('--senses must be >= 1')
    if not args.words and (not args.file or args.file == '-') and sys.stdin.isatty():
        if args.download or args.refresh:
            if args.refresh or not args.dict.exists():
                download(DUMP_URL, args.dict)
            load_index(args.dict, rebuild=True)
            return 0
        parser.print_help()
        return 0

    if args.refresh or (args.download and not args.dict.exists()):
        download(DUMP_URL, args.dict)
    if not args.dict.exists():
        print(f'{prog}: dictionary not found at {args.dict}; rerun with --download', file=sys.stderr)
        return 2
    index = load_index(args.dict, rebuild=args.rebuild_index or args.refresh)
    deps = None if args.no_lemmatizer else optional('lemmatize')
    definer = Definer(index, args.senses, args.lemma_note, deps and deps['simplemma'])

    words, raw_count = read_words(args)
    lines, unmatched = [], []
    for word in words:
        text = definer.define(word)
        if text is None:
            unmatched.append(word)
        lines.append(f'{word}: {text or NO_DEF}')
    body = '\n'.join(lines) + '\n'

    if args.in_place:
        src = Path(args.file).expanduser()
        shutil.copy2(src, src.with_name(src.name + '.bak'))
        src.write_text(body, encoding='utf-8')
    elif args.output:
        Path(args.output).expanduser().write_text(body, encoding='utf-8')
    else:
        sys.stdout.write(body)
    if args.unmatched:
        Path(args.unmatched).expanduser().write_text('\n'.join(unmatched) + '\n' if unmatched else '', encoding='utf-8')
    if args.stats:
        matched = len(words) - len(unmatched)
        print(f'input lines: {raw_count}  unique words: {len(words)}  '
              f'defined: {matched} ({matched / max(len(words), 1):.1%})  unmatched: {len(unmatched)}', file=sys.stderr)
    return 0 if not unmatched else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
    except BrokenPipeError:
        sys.exit(0)
