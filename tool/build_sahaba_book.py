#!/usr/bin/env python3
"""Builds assets/sahaba/ from two OpenITI texts (pinned, see the URLs below).

  python3 tool/build_sahaba_book.py riyad.txt sifat.txt assets/sahaba

The books' words are never changed. Only markup goes: page and milestone tags,
footnote numbers glued to a word (their notes aren't in these files), and
paragraph breaks that exist only because a printed page ended there.

Riyad: https://raw.githubusercontent.com/OpenITI/0700AH/3d8ff4e7b035aaa4ca5dda52c7322645f3401dcf/data/0694MuhibbDinTabari/0694MuhibbDinTabari.RiyadNadira/0694MuhibbDinTabari.RiyadNadira.Shamela0008657-ara1.completed
Sifat: https://raw.githubusercontent.com/OpenITI/0600AH/ea4bdc6517a49d07106f223aa0869aa7c21b9589/data/0597IbnJawzi/0597IbnJawzi.SifatSafwa/0597IbnJawzi.SifatSafwa.Shamela0012031-ara1.mARkdown
"""
import os
import re
import sys

TEN = [
    ('abu-bakr', 'أبو بكر الصديق'),
    ('umar', 'عمر بن الخطاب'),
    ('uthman', 'عثمان بن عفان'),
    ('ali', 'علي بن أبي طالب'),
    ('talha', 'طلحة بن عبيد الله'),
    ('zubayr', 'الزبير بن العوام'),
    ('abd-al-rahman', 'عبد الرحمن بن عوف'),
    ('saad', 'سعد بن أبي وقاص'),
    ('said', 'سعيد بن زيد'),
    ('abu-ubayda', 'أبو عبيدة بن الجراح'),
]
TEN_GROUP = 'العشرة المبشرون بالجنة'

# Each class of Sifat al-Safwa, by how its heading starts.
CLASSES = [
    ('فمن الطبقة الأولى', 'الطبقة الأولى: السابقون وأهل بدر'),
    ('و من الطبقة الثانية', 'الطبقة الثانية: من لم يشهد بدراً'),
    ('ومن الطبقة الثالثة', 'الطبقة الثالثة: من شهد الخندق وما بعدها'),
    ('من الطبقة الرابعة', 'الطبقة الرابعة: من أسلم عند الفتح وبعده'),
    ('ومن الطبقة الخامسة', 'الطبقة الخامسة: صغار الصحابة'),
    ('ذكر المصطفيات', 'الصحابيات'),
]

PAGE = re.compile(r'PageV(\d+)P(\d+)')
MILESTONE = re.compile(r'ms\d+')
FOOTNOTE_CALL = re.compile(r'(?<=[ء-ي])\d+')
SPACES = re.compile(r'\s+')
PARAGRAPH_END = ('.', '!', '?', '؟', ':', '"', '»')


def clean(text):
    text = PAGE.sub(' ', text)
    text = MILESTONE.sub(' ', text)
    text = text.replace('%~%', ' … ').replace('$', '')
    text = FOOTNOTE_CALL.sub('', text)
    return SPACES.sub(' ', text).strip()


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
        self.paragraphs = []
        self.pages = []


def chapters(lines, heading_level, first_title='أول الترجمة'):
    """Splits the lines of one person into chapters."""
    result = [Chapter(1, first_title)]
    paragraph = []
    after_page_end = False
    waiting_for_page = []  # chapters whose last page is the next marker.

    def flush():
        if paragraph:
            text = clean(' '.join(paragraph))
            if text:
                result[-1].paragraphs.append(text)
            paragraph.clear()

    def add_page(volume, page):
        if volume == 0 and page == 0:
            return
        for chapter in waiting_for_page + [result[-1]]:
            if not chapter.pages or chapter.pages[-1] != (volume, page):
                chapter.pages.append((volume, page))
        waiting_for_page.clear()

    for raw in lines:
        raw = raw.rstrip()
        if raw.startswith('### '):
            flush()
            after_page_end = False
            level = heading_level(raw)
            title = clean(re.sub(r'^###\s*[|$]+\s*', '', raw)).rstrip(':،, ')
            if title:
                waiting_for_page.append(result[-1])
                result.append(Chapter(level, title))
            continue

        if raw.startswith('~~'):
            body = raw[2:]
        elif raw.startswith('# '):
            body = raw[2:]
            joined = ' '.join(paragraph).strip()
            continues = (
                after_page_end
                and clean(joined)
                and not clean(joined).endswith(PARAGRAPH_END)
            )
            if not continues and PAGE.fullmatch(body.strip()) is None:
                flush()
        else:
            continue

        marks = [(int(a), int(b)) for a, b in PAGE.findall(body)]
        for volume, page in marks:
            add_page(volume, page)
        if clean(body):
            paragraph.append(body)
        # A page ended with no sentence end: the next paragraph continues it.
        after_page_end = bool(PAGE.search(body)) and not clean(
            PAGE.split(body)[-1]
        )
    flush()
    # Empty first chapters go; other empty ones head the chapters under them.
    return [c for c in result if c.paragraphs or c is not result[0]]


def slice_lines(data, start, end):
    return data[start:end].decode('utf8', 'ignore').splitlines()


def write_person(out, person, books):
    path = os.path.join(out, f'{person}.txt')
    with open(path, 'w', encoding='utf8') as f:
        for book, chs in books:
            f.write(f'@book {book}\n')
            for c in chs:
                f.write(f'@ch {c.level} {c.title}\n')
                if (loc := location(c.pages)) is not None:
                    f.write(f'@loc {loc}\n')
                for p in c.paragraphs:
                    f.write(p + '\n')


def words(chs):
    return sum(len(p.split()) for c in chs for p in c.paragraphs)


def main(riyad_path, sifat_path, out):
    os.makedirs(out, exist_ok=True)
    riyad = open(riyad_path, 'rb').read()
    sifat = open(sifat_path, 'rb').read()

    # Riyad: Part Two has one "الباب" per person, in the same order as TEN.
    part_two = riyad.index('### | القسم الثاني'.encode())
    bab = [m.start() for m in re.finditer(rb'^### \|\| ', riyad, re.M) if m.start() > part_two]
    assert len(bab) == 10, len(bab)
    bab.append(len(riyad))

    def riyad_level(raw):
        return 2 if raw.startswith('### ||||') else 1

    # Sifat: from "ذكر المشهورين" up to the Tabi'in.
    begin = sifat.index('### | ذكر المشهورين'.encode())
    end = sifat.index('### | ذكر المصطفين من التابعين'.encode())

    ten_at = [
        m.start()
        for m in re.finditer(rb'^### \|\| \d+- ', sifat[begin:end], re.M)
    ]
    assert len(ten_at) == 10, len(ten_at)
    ten_at = [begin + x for x in ten_at]
    classes_at = sifat.index('### | ذكر المشهورين'.encode(), begin + 10)
    ten_at.append(classes_at)

    def sifat_level(raw):
        return 1

    index = []
    for i, (pid, name) in enumerate(TEN):
        lines = slice_lines(riyad, bab[i], bab[i + 1])[1:]
        r = chapters(lines, riyad_level, first_title='مدخل')
        lines = slice_lines(sifat, ten_at[i], ten_at[i + 1])[1:]
        s = chapters(lines, sifat_level)
        write_person(out, pid, [('riyad', r), ('sifat', s)])
        index.append((pid, name, TEN_GROUP, words(r), words(s)))

    # The classes: every "### $ 12- name" is a person.
    group = None
    tail = sifat[classes_at:end]
    marks = list(re.finditer(rb'^### (\|\||\$+) ?(.*)$', tail, re.M))
    for k, m in enumerate(marks):
        kind = m.group(1)
        title = m.group(2).decode('utf8', 'ignore').strip()
        if kind == b'||':
            group = next((label for key, label in CLASSES if title.startswith(key)), None)
            assert group is not None, title
            continue
        number = re.match(r'(\d+)\s*-\s*', title)
        assert number is not None, title
        name = clean(title[number.end():]).rstrip('.:،, ')
        name = re.sub(r'\s*(رضي|رضى) الله (عنه|عنها|عنهم|عنهما)\s*$', '', name).rstrip('.:،, ')
        start = classes_at + m.end()
        stop = classes_at + marks[k + 1].start() if k + 1 < len(marks) else end
        s = chapters(slice_lines(sifat, start, stop), sifat_level, first_title='ترجمته')
        pid = f's{number.group(1)}'
        write_person(out, pid, [('sifat', s)])
        index.append((pid, name, group, 0, words(s)))

    with open(os.path.join(out, 'index.txt'), 'w', encoding='utf8') as f:
        for pid, name, grp, rw, sw in index:
            f.write(f'{pid}|{name}|{grp}|{rw}|{sw}\n')
    for row in index[:10]:
        print(row)
    print('people', len(index), 'words', sum(r[3] + r[4] for r in index))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3])
