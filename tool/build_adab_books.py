#!/usr/bin/env python3
"""Builds assets/adab/ from seven OpenITI texts (pinned, see lib/.../adab_models.dart).

  python3 tool/build_adab_books.py <folder with uyun.txt, shir.txt...> assets/adab

The books' words are never changed. Only markup goes: page and milestone tags,
the printed edition's verse numbers and footnote calls (their notes aren't in
these files), and paragraph breaks that exist only because a page ended there.

Each output file has `@ch level title`, an optional `@loc`, `@h subheading`,
and a line for each paragraph. A verse keeps ` … ` between its two halves.
"""
import os
import re
import sys

BOOKS = ['uyun', 'shir', 'bukhala', 'kalila', 'kamil', 'bayan', 'iqd']

# Al-Bayan only has one real top heading, so its levels start one lower.
HEADING_SHIFT = {'bayan': 1}

PAGE = re.compile(r'PageV(\d+)P(\d+)')
MILESTONE = re.compile(r'\s*\bms\d+\b\s*')
FOOTNOTE = re.compile(r'«\s*\d+\s*»|\[\s*\d+\s*\]|\(\s*\d{1,2}\s*\)|(?<=[ء-ي])\d+')
VERSE_NUMBER = re.compile(r'(?<!\d)\d+\s*\*\s*')
VERSE_BREAK = re.compile(r'\s*(?:%~%|\.\.\.|…)\s*|(?<=\S)\s*\*\s+')
TAG = re.compile(r'</?[a-zA-Z][^>]*>')
SPACE_BEFORE = re.compile(r'\s+(?=[.,،؛:؟!»)\]])')
SPACE_AFTER = re.compile(r'(?<=[«(\[])\s+')
SPACES = re.compile(r'\s+')
PARAGRAPH_END = ('.', '!', '?', '؟', ':', '"', '»', '…')
JOINS_PREVIOUS = ('.', '،', ',', '؛', ':', '؟', '!', '»', ')')
HEADING = re.compile(r'^### (\|+|\$+)\s*(.*)$')


def clean(text):
    text = PAGE.sub(' ', text)
    text = MILESTONE.sub(' ', text)
    text = TAG.sub(' ', text).replace('$', '')
    text = FOOTNOTE.sub('', text)
    text = VERSE_NUMBER.sub('', text)
    text = VERSE_BREAK.sub(' … ', text).strip('* ')
    text = SPACES.sub(' ', text)
    text = SPACE_BEFORE.sub('', text)
    text = SPACE_AFTER.sub('', text)
    return text.strip()


def clean_title(text):
    title = clean(text).rstrip('.:،, ').strip()
    # The editors' square brackets around a whole heading.
    if title.startswith('[') and title.endswith(']'):
        title = title[1:-1].rstrip('.:،, ').strip()
    # The editor's running number on each poet.
    return re.sub(r'^\d+\s*-\s*', '', title)


def location(pages):
    if not pages:
        return None
    first, last = pages[0], pages[-1]
    if first == last:
        return f'ج{first[0]}، ص{first[1]}'
    if first[0] == last[0]:
        return f'ج{first[0]}، ص{first[1]}–{last[1]}'
    return f'ج{first[0]}، ص{first[1]} – ج{last[0]}، ص{last[1]}'


class Chapter:
    def __init__(self, level, title):
        self.level = level
        self.title = title
        self.items = []  # ('p' | 'h', text)
        self.pages = []

    def words(self):
        return sum(len(t.split()) for kind, t in self.items if kind == 'p')

    @property
    def has_text(self):
        return any(kind == 'p' for kind, _ in self.items)


def is_verse(text):
    return ' … ' in text


def parse(book, raw):
    _, _, body = raw.partition('#META#Header#End#')
    shift = HEADING_SHIFT.get(book, 0)
    chapters = []
    current = None
    paragraph = []
    after_page_end = False
    numbered = 0
    skipping = False  # end-of-volume notes the source marks as not the book.

    def flush():
        if not paragraph:
            return
        text = clean(' '.join(paragraph))
        paragraph.clear()
        if not text or current is None or skipping:
            return
        last = current.items[-1] if current.items else None
        # A footnote call on its own line left only the punctuation after it.
        if text.startswith(JOINS_PREVIOUS) and last and last[0] == 'p':
            joined = last[1] + (' ' + text if text.startswith(('،', '؛')) else text)
            current.items[-1] = ('p', SPACE_BEFORE.sub('', joined))
            return
        if re.search(r'[ء-ي]', text):
            current.items.append(('p', text))

    for line in body.splitlines():
        line = line.rstrip()
        heading = HEADING.match(line)
        if heading:
            flush()
            after_page_end = False
            marks, text = heading.groups()
            skipping = text.strip() in ('PARATEXT|', 'EDITOR|')
            if skipping:
                continue
            title = clean_title(text)
            level = 2 if marks.startswith('$') else len(marks) - shift
            if level <= 0:
                continue  # the empty heading above al-Bayan's real ones.
            if title == 'باب':
                numbered += 1
                title = f'باب {numbered}'
            if not title:
                continue
            if level >= 3:
                if current is not None:
                    current.items.append(('h', title))
                continue
            current = Chapter(level, title)
            chapters.append(current)
            continue

        if line.startswith('~~'):
            content = line[2:]
        elif line.startswith('# '):
            content = line[2:]
            joined = clean(' '.join(paragraph))
            # A page ended mid-sentence: the next paragraph continues it.
            continues = (
                after_page_end
                and joined
                and not joined.endswith(PARAGRAPH_END)
                and not is_verse(joined)
                and not is_verse(clean(content))
            )
            if not continues and PAGE.fullmatch(content.strip()) is None:
                flush()
        else:
            continue

        if current is not None and not skipping:
            for volume, page in PAGE.findall(content):
                mark = (int(volume), int(page))
                if not current.pages or current.pages[-1] != mark:
                    current.pages.append(mark)
        if clean(content):
            paragraph.append(content)
        after_page_end = bool(PAGE.search(content)) and not clean(
            PAGE.split(content)[-1]
        )
    flush()
    # A heading with no text and nothing under it (Kalila's opening basmala).
    return [
        c
        for i, c in enumerate(chapters)
        if c.has_text
        or (i + 1 < len(chapters) and chapters[i + 1].level > c.level)
    ]


def main(source, out):
    os.makedirs(out, exist_ok=True)
    index = []
    for book in BOOKS:
        with open(os.path.join(source, f'{book}.txt'), encoding='utf8') as f:
            chapters = parse(book, f.read())
        with open(os.path.join(out, f'{book}.txt'), 'w', encoding='utf8') as f:
            for c in chapters:
                f.write(f'@ch {c.level} {c.title}\n')
                if (loc := location(c.pages)) is not None:
                    f.write(f'@loc {loc}\n')
                for kind, text in c.items:
                    f.write(f'@h {text}\n' if kind == 'h' else f'{text}\n')
        words = sum(c.words() for c in chapters)
        readable = sum(1 for c in chapters if c.has_text)
        index.append(f'{book}|{words}|{readable}')
        print(book, 'chapters', readable, 'words', words)
    with open(os.path.join(out, 'index.txt'), 'w', encoding='utf8') as f:
        f.write('\n'.join(index) + '\n')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
