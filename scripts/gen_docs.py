"""Make Doxygen-style HTML documentation for the app's Swift code.

Doxygen doesn't read Swift, so this does its job for this project, the same way
the Android app's scripts/gen_docs.py does for Kotlin, with the same look:

* a page per type (struct, class, enum, protocol, actor), with its member table
  and the full documentation of every member, its extensions included
* a page per file, with its top-level declarations, and its source code,
  coloured, with line numbers and the names linked to their documentation
* a page per folder (App, Data, Domain, UI, Tests)
* type list, type index, all members, file list, and a search box

Documentation comes from Swift's doc comments (/// and /** ... */), with
- Parameter, - Parameters, - Returns and - Throws read as Doxygen reads @param.

    python scripts/gen_docs.py

The site is written to docs/html; open docs/html/index.html.
"""

import html
import json
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIRS = [ROOT / "App" / "Sources", ROOT / "Tests"]
OUT = ROOT / "docs" / "html"
REPO_URL = "https://github.com/Kastoria-Dev-Core/astiko-ktel-kastorias-ios"

KEYWORDS = {
    "actor", "any", "as", "associatedtype", "async", "await", "break", "case", "catch", "class", "continue",
    "convenience", "default", "defer", "deinit", "didSet", "do", "dynamic", "else", "enum", "extension",
    "fallthrough", "false", "fileprivate", "final", "for", "func", "get", "guard", "if", "import", "in",
    "indirect", "init", "inout", "internal", "is", "lazy", "let", "mutating", "nil", "nonisolated", "open",
    "operator", "override", "private", "protocol", "public", "repeat", "required", "rethrows", "return", "self",
    "Self", "set", "some", "static", "struct", "subscript", "super", "switch", "throw", "throws", "true", "try",
    "typealias", "unowned", "var", "weak", "where", "while", "willSet",
}
MODIFIERS = {
    "public", "private", "fileprivate", "internal", "open", "static", "final", "lazy", "mutating", "nonisolated",
    "override", "required", "convenience", "weak", "unowned", "indirect", "dynamic", "class",
}
TYPE_KINDS = {"struct", "class", "enum", "protocol", "actor", "extension"}
MEMBER_KINDS = {"func", "init", "var", "let", "case", "typealias", "subscript"}
FOLDERS = {
    "App": "The app's entry, the shared container and the text in two languages",
    "Data": "The data and the services: the network, live buses, announcements, settings, location",
    "Domain": "The logic, with no UI: timetables, bus estimates, live trips, the journey planner, search",
    "UI": "The screens and the pieces they share",
    "Tests": "Unit tests, run on the iPhone simulator by CI",
}


def esc(s):
    return html.escape(s, quote=True)


def safe(s):
    return re.sub(r"[^A-Za-z0-9]+", "_", s).strip("_")


# ---------------------------------------------------------------- tokens

class Token:
    __slots__ = ("kind", "text", "start", "end", "line")

    def __init__(self, kind, text, start, end, line):
        self.kind = kind  # id, num, str, op, attr, comment
        self.text = text
        self.start = start
        self.end = end
        self.line = line


def tokenize(src):
    """Swift tokens, comments included (kind "comment"), so the source page can colour them"""
    out = []
    i = 0
    line = 1
    n = len(src)
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
            continue
        if c.isspace():
            i += 1
            continue
        start, start_line = i, line
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(Token("comment", src[i:j], i, j, line))
            i = j
            continue
        if src.startswith("/*", i):
            depth = 0
            j = i
            while j < n:
                if src.startswith("/*", j):
                    depth += 1
                    j += 2
                elif src.startswith("*/", j):
                    depth -= 1
                    j += 2
                    if depth == 0:
                        break
                else:
                    j += 1
            text = src[i:j]
            out.append(Token("comment", text, i, j, line))
            line += text.count("\n")
            i = j
            continue
        if c == '"' or (c == "#" and re.match(r'#+"', src[i:])):
            hashes = 0
            j = i
            while src[j] == "#":
                hashes += 1
                j += 1
            multi = src.startswith('"""', j)
            quote = '"""' if multi else '"'
            j += len(quote)
            close = quote + "#" * hashes
            depth = 0
            while j < n:
                if src[j] == "\\" and depth == 0 and src.startswith("\\" + "#" * hashes, j):
                    k = j + 1 + hashes
                    if k < n and src[k] == "(":
                        # \( interpolation ): skip to its closing bracket
                        depth = 1
                        j = k + 1
                        while j < n and depth:
                            if src[j] == "(":
                                depth += 1
                            elif src[j] == ")":
                                depth -= 1
                            elif src[j] == '"':
                                # A string inside the interpolation
                                j += 1
                                while j < n and src[j] != '"':
                                    j += 2 if src[j] == "\\" else 1
                            j += 1
                        continue
                    j = k + 1
                    continue
                if src.startswith(close, j):
                    j += len(close)
                    break
                if not multi and src[j] == "\n":
                    break
                j += 1
            text = src[i:j]
            out.append(Token("str", text, i, j, line))
            line += text.count("\n")
            i = j
            continue
        if c.isdigit():
            m = re.match(r"0x[0-9A-Fa-f_]+|\d[\d_]*(\.\d[\d_]*)?([eE][+-]?\d+)?", src[i:])
            j = i + m.end()
            out.append(Token("num", src[i:j], i, j, line))
            i = j
            continue
        if c == "@":
            m = re.match(r"@[A-Za-z_][A-Za-z0-9_]*", src[i:])
            if m:
                j = i + m.end()
                out.append(Token("attr", src[i:j], i, j, line))
                i = j
                continue
        if c == "`":
            j = src.find("`", i + 1)
            j = n if j < 0 else j + 1
            out.append(Token("id", src[i + 1:j - 1], i, j, line))
            i = j
            continue
        if c.isalpha() or c == "_" or c == "$":
            m = re.match(r"[\w$]+", src[i:])
            j = i + m.end()
            out.append(Token("id", src[i:j], i, j, line))
            i = j
            continue
        m = re.match(r"\.\.\.|\.\.<|->|==|!=|<=|>=|&&|\|\||\?\?|[-+*/%]=|.", src[i:], re.S)
        j = i + m.end()
        out.append(Token("op", src[i:j], i, j, line))
        i = j
        del start, start_line
    return out


# ---------------------------------------------------------------- doc comments

class Doc:
    """A doc comment split the way Doxygen shows it: brief, text, parameters, returns, throws"""

    def __init__(self, raw):
        self.raw = raw
        self.params = {}
        self.returns = ""
        self.throws = ""
        body = []
        mode = None
        for ln in raw.split("\n"):
            s = ln.strip()
            m = re.match(r"-\s*Parameter\s+(\w+)\s*:\s*(.*)", s)
            if m:
                self.params[m.group(1)] = m.group(2)
                mode = ("param", m.group(1))
                continue
            if re.match(r"-\s*Parameters\s*:", s):
                mode = "params"
                continue
            m = re.match(r"-\s*(\w+)\s*:\s*(.*)", s)
            if mode == "params" and m and m.group(1) not in ("Returns", "Throws"):
                self.params[m.group(1)] = m.group(2)
                mode = ("param", m.group(1))
                continue
            m = re.match(r"-\s*Returns\s*:\s*(.*)", s)
            if m:
                self.returns = m.group(1)
                mode = "returns"
                continue
            m = re.match(r"-\s*Throws\s*:\s*(.*)", s)
            if m:
                self.throws = m.group(1)
                mode = "throws"
                continue
            if mode and s and not s.startswith("-"):
                if isinstance(mode, tuple):
                    self.params[mode[1]] += " " + s
                    continue
                if mode == "returns":
                    self.returns += " " + s
                    continue
                if mode == "throws":
                    self.throws += " " + s
                    continue
            mode = None if not s else mode
            body.append(ln)
        self.text = "\n".join(body).strip()
        paragraphs = re.split(r"\n\s*\n", self.text)
        self.brief = " ".join(paragraphs[0].split()) if paragraphs and paragraphs[0] else ""
        self.paragraphs = [p for p in paragraphs if p.strip()]


def doc_comment_text(comments):
    """The text of the /// lines or the /** */ block right above a declaration"""
    lines = []
    for c in comments:
        t = c.text
        if t.startswith("///"):
            lines.append(t[3:][1:] if t[3:4] == " " else t[3:])
        elif t.startswith("/**"):
            inner = t[3:-2]
            for ln in inner.split("\n"):
                ln = ln.strip()
                if ln.startswith("*"):
                    ln = ln[1:][1:] if ln[1:2] == " " else ln[1:]
                lines.append(ln)
    return "\n".join(lines).strip()


# ---------------------------------------------------------------- declarations

class Decl:
    def __init__(self, kind, name, src_file, line):
        self.kind = kind
        self.name = name
        self.file = src_file
        self.line = line
        self.end_line = line
        self.signature = ""
        self.modifiers = []
        self.attributes = []
        self.inherits = ""
        self.doc = Doc("")
        self.parent = None  # the type it's in
        self.members = []
        self.extensions = []  # for types: the extension Decls that add to it
        self.page = ""
        self.anchor = ""
        self.name_tok = None

    @property
    def is_type(self):
        return self.kind in TYPE_KINDS

    @property
    def visibility(self):
        for v in ("private", "fileprivate"):
            if v in self.modifiers:
                return v
        return ""

    @property
    def url(self):
        return f"{self.page}#{self.anchor}" if self.anchor else self.page

    @property
    def scope(self):
        return self.parent.name if self.parent else self.file.name

    @property
    def title(self):
        return self.name + ("()" if self.kind in ("func", "init", "subscript") else "")


class SourceFile:
    def __init__(self, path):
        self.path = path
        self.rel = path.relative_to(ROOT).as_posix()
        self.name = path.name
        parts = path.relative_to(ROOT).parts
        self.folder = "Tests" if parts[0] == "Tests" else parts[2] if len(parts) > 3 else parts[1]
        self.src = path.read_text(encoding="utf-8")
        self.tokens = tokenize(self.src)
        self.code = [t for t in self.tokens if t.kind != "comment"]
        self.decls = []  # top level, types and extensions included
        self.all = []
        self.imports = []
        self.page = "file_" + safe(self.rel) + ".html"
        self.src_page = "src_" + safe(self.rel) + ".html"
        self.lines = self.src.count("\n") + 1


def parse(f):
    """Finds the declarations of a file: types, extensions and their members, and top-level ones.
    Declarations inside function and property bodies are left out."""
    toks = f.tokens
    stack = []  # one entry per open "{": the Decl whose body it is, or None for code
    pending = None  # a type Decl waiting for its "{"
    i = 0
    n = len(toks)

    def comments_before(k):
        out = []
        j = k - 1
        while j >= 0 and toks[j].kind == "comment":
            out.insert(0, toks[j])
            j -= 1
        # Only doc comments count, and only the ones right above
        docs = [c for c in out if c.text.startswith("///") or c.text.startswith("/**")]
        return docs

    def in_code():
        return any(s is None for s in stack)

    while i < n:
        t = toks[i]
        if t.kind == "comment":
            i += 1
            continue
        if t.kind == "op" and t.text == "{":
            stack.append(pending if pending is not None else None)
            pending = None
            i += 1
            continue
        if t.kind == "op" and t.text == "}":
            if stack:
                closed = stack.pop()
                if closed is not None:
                    closed.end_line = t.line
            i += 1
            continue
        if in_code() or t.kind not in ("id", "attr"):
            i += 1
            continue
        if t.kind == "id" and t.text == "import" and not stack:
            j = i + 1
            name = []
            while j < n and toks[j].line == t.line and toks[j].kind != "comment":
                name.append(toks[j].text)
                j += 1
            f.imports.append("".join(name))
            i = j
            continue
        # A declaration: attributes and modifiers, then its keyword
        start = i
        attributes, modifiers = [], []
        j = i
        while j < n:
            tj = toks[j]
            if tj.kind == "attr":
                a = tj.text
                if j + 1 < n and toks[j + 1].text == "(" and toks[j + 1].start == tj.end:
                    depth, k = 0, j + 1
                    while k < n:
                        if toks[k].text == "(":
                            depth += 1
                        elif toks[k].text == ")":
                            depth -= 1
                            if depth == 0:
                                break
                        k += 1
                    a = f.src[tj.start:toks[k].end]
                    j = k
                attributes.append(a)
                j += 1
                continue
            if tj.kind == "id" and tj.text in MODIFIERS and j + 1 < n and toks[j + 1].kind == "id" and (
                    toks[j + 1].text in MODIFIERS or toks[j + 1].text in TYPE_KINDS | MEMBER_KINDS):
                modifiers.append(tj.text)
                j += 1
                if j < n and toks[j].text == "(":  # private(set)
                    j += 3
                continue
            if tj.kind == "id" and tj.text in ("private", "fileprivate") and j + 1 < n and toks[j + 1].text == "(":
                modifiers.append(tj.text)
                j += 4
                continue
            break
        if j >= n:
            break
        kw = toks[j]
        parent = stack[-1] if stack else None
        if kw.kind != "id" or kw.text not in TYPE_KINDS | MEMBER_KINDS or (kw.text == "case" and (parent is None or parent.kind != "enum")):
            i = j + 1 if j > i else i + 1
            continue
        kind = kw.text
        # The name
        k = j + 1
        if kind == "init":
            name = "init"
        elif kind == "subscript":
            name = "subscript"
        else:
            if k >= n:
                break
            name = toks[k].text
            if kind == "func" and toks[k].kind == "op":
                # An operator function: func < (a, b)
                name = toks[k].text
        d = Decl(kind, name, f, kw.line)
        d.modifiers = modifiers
        d.attributes = attributes
        d.name_tok = k if kind not in ("init", "subscript") else j
        d.doc = Doc(doc_comment_text(comments_before(start)))
        # The signature: up to the body, the value, or the end of the line. It starts after the name,
        # so an operator function's name (func <) isn't read as a bracket
        e = k if kind in ("init", "subscript") else k + 1
        depth = 0
        while e < n:
            te = toks[e]
            if te.kind == "comment":
                break
            if te.text in ("(", "[", "<") and te.kind == "op":
                depth += 1
            elif te.text in (")", "]", ">") and te.kind == "op":
                depth -= 1
            elif depth <= 0 and te.text in ("{", "}"):
                break
            elif depth <= 0 and te.text == "=" and kind in ("var", "let", "case"):
                break
            elif depth <= 0 and te.line != toks[e - 1].line and e > k and kind not in ("func", "init"):
                break
            e += 1
        sig_end = toks[e - 1].end if e > j else kw.end
        d.signature = " ".join(f.src[toks[start].start:sig_end].split())
        if attributes:
            # Attributes go above the signature, like Doxygen's annotations
            sig = f.src[kw.start if not modifiers else toks[j - len(modifiers)].start:sig_end]
            d.signature = " ".join(sig.split())
        if kind in TYPE_KINDS:
            m = re.search(r":\s*(.+)$", d.signature)
            d.inherits = m.group(1).strip() if m else ""
        d.parent = parent
        f.all.append(d)
        if parent is not None:
            parent.members.append(d)
        else:
            f.decls.append(d)
        if kind in TYPE_KINDS:
            # Its body is the next "{"
            pending = d
            i = e
            continue
        # Members: a body after them is code, so skip over it with the bracket stack
        if e < n and toks[e].text == "{":
            stack.append(None)
            i = e + 1
            continue
        i = e if e > i else i + 1
    return f


# ---------------------------------------------------------------- the project

class Project:
    def __init__(self):
        self.files = []
        for d in SOURCE_DIRS:
            for p in sorted(d.rglob("*.swift")):
                self.files.append(parse(SourceFile(p)))
        # Types by name, with their extensions folded in
        self.types = {}
        for f in self.files:
            for d in f.all:
                if d.kind in TYPE_KINDS - {"extension"}:
                    self.types.setdefault(d.name, d)
        self.orphan_extensions = []
        for f in self.files:
            for d in f.decls:
                if d.kind == "extension":
                    base = d.name.split(".")[-1]
                    if base in self.types:
                        self.types[base].extensions.append(d)
                    else:
                        self.orphan_extensions.append(d)
        # Pages and anchors
        for name, t in self.types.items():
            t.page = "type_" + safe(name) + ".html"
            t.anchor = ""
            for e in t.extensions:
                e.page = t.page
                e.anchor = f"ext_{safe(e.file.name)}_{e.line}"
            for m in self.members_of(t):
                m.page = t.page
                m.anchor = f"{safe(m.name) or 'op'}_{m.line}_{safe(m.file.name)}"
        for e in self.orphan_extensions:
            e.page = "ext_" + safe(e.name) + ".html"
            for m in e.members:
                m.page = e.page
                m.anchor = f"{safe(m.name) or 'op'}_{m.line}"
        for f in self.files:
            for d in f.decls:
                if d.kind not in TYPE_KINDS:
                    d.page = f.page
                    d.anchor = f"{safe(d.name) or 'op'}_{d.line}"
            for d in f.all:
                # Nested types get their own page too
                if d.kind in TYPE_KINDS - {"extension"} and not d.page:
                    d.page = "type_" + safe((d.parent.name + "." if d.parent else "") + d.name) + ".html"
                    for m in d.members:
                        m.page = d.page
                        m.anchor = f"{safe(m.name) or 'op'}_{m.line}"
        self.commit, self.commit_date = "", ""
        try:
            out = subprocess.run(["git", "log", "-1", "--format=%h %cs"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.split()
            self.commit, self.commit_date = out[0], out[1]
        except Exception:
            pass
        self.version = ""
        m = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', (ROOT / "project.yml").read_text(encoding="utf-8"))
        if m:
            self.version = m.group(1)

    def members_of(self, t):
        out = list(t.members)
        for e in t.extensions:
            out += e.members
        return out

    def all_decls(self):
        for f in self.files:
            yield from f.all

    def documented(self):
        """Declarations that should have a doc comment, and the ones that do"""
        want = [d for d in self.all_decls() if d.visibility == "" and d.kind != "extension" and d.file.folder != "Tests"
                and not (d.kind in ("var", "let") and d.parent is None and d.name.startswith("_"))
                and d.name not in ("body", "id")]
        have = [d for d in want if d.doc.text]
        return want, have


# ---------------------------------------------------------------- style, the same as the Android app's docs

CSS = r"""
:root {
  --page-bg: #ffffff; --page-fg: #1c1c1c; --page-link: #3d578c; --page-visited: #4665a2;
  --muted: #5a5a5a; --border: #a8b8d9; --border-soft: #d5ddec; --header-bg: #f9fafc;
  --title-grad-a: #f9fafc; --title-grad-b: #e2e8f2; --tab-bg: #e8eef7; --tab-active: #ffffff;
  --tab-fg: #283a5d; --nav-bg: #f9fafc; --nav-sel: #c4cfe5; --memproto-bg: #e2e8f2;
  --memproto-border: #a8b8d9; --memdoc-bg: #ffffff; --memtitle-bg: #dfe5f1; --memsep: #dee4f0;
  --member-bg: #f9fafc; --fragment-bg: #fbfcfd; --fragment-border: #c4cfe5; --lineno: #888;
  --kw: #008000; --type: #604020; --str: #002080; --num: #a0522d; --com: #800000; --ann: #9b4dca;
  --label-bg: #728dc1; --label-fg: #fff; --graph-node: #ffffff; --graph-self: #bfbfbf; --graph-edge: #63b8ff;
  --graph-text: #000; --hl: #ffffcc; --search-bg: #ffffff; --shadow: 0 2px 6px rgba(0,0,0,.15);
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --page-bg: #1c1d1f; --page-fg: #d2dbde; --page-link: #90a5ce; --page-visited: #a3b4d7;
    --muted: #a0a4a8; --border: #4a5466; --border-soft: #2f3542; --header-bg: #252628;
    --title-grad-a: #252628; --title-grad-b: #2c3038; --tab-bg: #283041; --tab-active: #1c1d1f;
    --tab-fg: #c6cfe0; --nav-bg: #212224; --nav-sel: #354360; --memproto-bg: #2a3040;
    --memproto-border: #4a5466; --memdoc-bg: #1c1d1f; --memtitle-bg: #2c3446; --memsep: #2f3542;
    --member-bg: #212328; --fragment-bg: #17181a; --fragment-border: #3a4150; --lineno: #777;
    --kw: #7bc87b; --type: #d0a77a; --str: #8fb3ff; --num: #e0a070; --com: #d0807a; --ann: #c79bf2;
    --label-bg: #4f6290; --label-fg: #eef; --graph-node: #2a2d33; --graph-self: #4a5060; --graph-edge: #4f8fd0;
    --graph-text: #d2dbde; --hl: #3a3a20; --search-bg: #2a2c30; --shadow: 0 2px 8px rgba(0,0,0,.5);
  }
}
:root[data-theme="dark"] {
  --page-bg: #1c1d1f; --page-fg: #d2dbde; --page-link: #90a5ce; --page-visited: #a3b4d7;
  --muted: #a0a4a8; --border: #4a5466; --border-soft: #2f3542; --header-bg: #252628;
  --title-grad-a: #252628; --title-grad-b: #2c3038; --tab-bg: #283041; --tab-active: #1c1d1f;
  --tab-fg: #c6cfe0; --nav-bg: #212224; --nav-sel: #354360; --memproto-bg: #2a3040;
  --memproto-border: #4a5466; --memdoc-bg: #1c1d1f; --memtitle-bg: #2c3446; --memsep: #2f3542;
  --member-bg: #212328; --fragment-bg: #17181a; --fragment-border: #3a4150; --lineno: #777;
  --kw: #7bc87b; --type: #d0a77a; --str: #8fb3ff; --num: #e0a070; --com: #d0807a; --ann: #c79bf2;
  --label-bg: #4f6290; --label-fg: #eef; --graph-node: #2a2d33; --graph-self: #4a5060; --graph-edge: #4f8fd0;
  --graph-text: #d2dbde; --hl: #3a3a20; --search-bg: #2a2c30; --shadow: 0 2px 8px rgba(0,0,0,.5);
}
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body { background: var(--page-bg); color: var(--page-fg); font: 14px/1.45 Roboto, "Segoe UI", Arial, sans-serif; }
a { color: var(--page-link); text-decoration: none; }
a:visited { color: var(--page-visited); }
a:hover { text-decoration: underline; }
a.el { font-weight: bold; }
code, pre, .memname, .memItemLeft, .memItemRight, .memTemplParams { font-family: "JetBrains Mono", Consolas, "DejaVu Sans Mono", monospace; }
code { font-size: 0.92em; }
#top { border-bottom: 1px solid var(--border); background: var(--header-bg); }
#titlearea { display: flex; align-items: center; gap: 14px; padding: 10px 16px; }
#projectlogo img { width: 48px; height: 48px; display: block; }
#projectname { font: 300 26px/1.2 Tahoma, Arial, sans-serif; }
#projectnumber { font-size: 50%; color: var(--muted); margin-left: 6px; }
#projectbrief { font-size: 13px; color: var(--muted); }
#theme-toggle { margin-left: auto; border: 1px solid var(--border); background: var(--tab-bg); color: var(--tab-fg); border-radius: 4px; padding: 4px 9px; cursor: pointer; font: inherit; }
.tabs, .tabs2 { display: flex; flex-wrap: wrap; align-items: stretch; margin: 0; padding: 0 8px; list-style: none; background: var(--tab-bg); border-top: 1px solid var(--border-soft); }
.tabs li, .tabs2 li { display: block; }
.tabs a, .tabs2 a { display: block; padding: 7px 13px; color: var(--tab-fg); font-weight: bold; font-size: 13px; text-shadow: 0 1px 1px rgba(255,255,255,.4); }
.tabs2 a { font-weight: normal; font-size: 12.5px; padding: 5px 12px; }
.tabs li.current a, .tabs2 li.current a { background: var(--tab-active); color: var(--page-link); }
.tabs li.search { margin-left: auto; position: relative; padding: 4px 0; }
#searchbox { width: 220px; max-width: 46vw; padding: 4px 10px; border: 1px solid var(--border); border-radius: 12px; background: var(--search-bg); color: var(--page-fg); font: inherit; }
#searchresults { position: absolute; right: 0; top: 34px; z-index: 50; width: 420px; max-width: 92vw; max-height: 70vh; overflow: auto; background: var(--search-bg); border: 1px solid var(--border); box-shadow: var(--shadow); display: none; }
#searchresults a { display: block; padding: 5px 10px; border-bottom: 1px solid var(--border-soft); font-weight: normal; }
#searchresults a:hover, #searchresults a.sel { background: var(--nav-sel); text-decoration: none; }
#searchresults .sk { color: var(--muted); font-size: 12px; margin-left: 6px; }
#searchresults .none { padding: 8px 10px; color: var(--muted); }
#layout { display: flex; align-items: stretch; min-height: calc(100vh - 120px); }
#side-nav { width: 280px; flex: none; background: var(--nav-bg); border-right: 1px solid var(--border-soft); overflow: auto; max-height: calc(100vh - 0px); position: sticky; top: 0; font-size: 13px; padding: 6px 0 20px; }
#side-nav ul { list-style: none; margin: 0; padding-left: 14px; }
#side-nav > ul { padding-left: 4px; }
#side-nav li > div { display: flex; align-items: center; white-space: nowrap; padding: 2px 6px 2px 0; border-radius: 3px; }
#side-nav li > div.selected { background: var(--nav-sel); }
#side-nav .arrow { width: 16px; flex: none; text-align: center; cursor: pointer; color: var(--muted); user-select: none; font-size: 10px; }
#side-nav .closed > ul { display: none; }
#side-nav a { color: var(--page-fg); font-weight: normal; overflow: hidden; text-overflow: ellipsis; }
#nav-toggle { display: none; }
#doc-content { flex: 1; min-width: 0; }
div.header { background: linear-gradient(var(--title-grad-a), var(--title-grad-b)); border-bottom: 1px solid var(--border-soft); padding: 4px 18px 6px; }
div.summary { float: right; font-size: 12px; padding-top: 6px; }
div.headertitle { padding: 5px 0; }
div.title { font: 400 22px/28px Tahoma, Arial, sans-serif; margin: 6px 0 4px; }
div.ingroups { font-size: 12px; color: var(--muted); }
div.contents { padding: 10px 18px 30px; max-width: 1180px; }
h2.groupheader { border-bottom: 1px solid var(--border); color: var(--tab-fg); font-size: 150%; font-weight: normal; margin-top: 1.6em; padding-bottom: 4px; }
h2.groupheader a { color: inherit; }
.mdh { color: var(--tab-fg); }
p { margin: .6em 0; }
.textblock { max-width: 900px; }
.textblock img { max-width: 100%; }
table.memberdecls { border-spacing: 0; width: 100%; margin-top: 6px; }
table.memberdecls td { padding: 3px 6px; vertical-align: top; }
.memItemLeft, .memItemRight { background: var(--member-bg); border-top: 1px solid var(--memsep); font-size: 13px; }
.memItemLeft { text-align: right; white-space: nowrap; color: var(--muted); width: 1%; }
.memItemRight { width: 99%; }
.mdescLeft, .mdescRight { background: var(--member-bg); font-size: 12.5px; color: var(--muted); padding-bottom: 6px !important; }
.memSeparator { height: 1px; padding: 0 !important; }
.memItemRight .params { color: var(--muted); font-weight: normal; }
.memtitle { display: inline-block; margin: 26px 0 0; padding: 6px 12px 4px 8px; background: var(--memtitle-bg); border: 1px solid var(--memproto-border); border-bottom: none; border-radius: 4px 4px 0 0; font: 400 15px/1.3 Tahoma, Arial, sans-serif; }
.memtitle .permalink { margin-right: 6px; color: var(--muted); }
.memitem { border: 1px solid var(--memproto-border); border-radius: 0 4px 4px 4px; overflow: hidden; margin-bottom: 8px; box-shadow: var(--shadow); }
.memproto { background: var(--memproto-bg); padding: 7px 10px; border-bottom: 1px solid var(--memproto-border); overflow-x: auto; }
table.mlabels { width: 100%; border-spacing: 0; }
table.mlabels td.mlabels-left { width: 100%; }
td.mlabels-right { vertical-align: bottom; white-space: nowrap; text-align: right; }
span.mlabel { background: var(--label-bg); color: var(--label-fg); border-radius: 3px; padding: 1px 6px; margin-left: 4px; font-size: 11px; white-space: nowrap; }
table.memname { border-spacing: 0; font-size: 13.5px; }
table.memname td { padding: 1px 0; vertical-align: top; white-space: nowrap; }
td.memname { font-weight: bold; }
td.paramname { color: #602020; font-style: italic; padding-left: 6px !important; }
:root[data-theme="dark"] td.paramname { color: #e0a4a4; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) td.paramname { color: #e0a4a4; } }
td.paramtype { padding-left: 4px !important; }
.annotations { color: var(--ann); font-size: 12.5px; margin-bottom: 2px; }
.memdoc { background: var(--memdoc-bg); padding: 6px 14px 10px; }
.memdoc .definition, p.definition { font-size: 12.5px; color: var(--muted); }
dl.params, dl.retval, dl.section { margin: 8px 0; }
dl.section dt, dl.params dt { font-weight: bold; }
dl.section dd, dl.params dd { margin-left: 22px; }
dl.note { border-left: 4px solid #d0c000; padding-left: 8px; }
dl.see { border-left: 4px solid #4caf50; padding-left: 8px; }
dl.todo { border-left: 4px solid #e08000; padding-left: 8px; }
table.params, table.fieldtable, table.doxtable, table.directory { border-collapse: collapse; margin: 4px 0; }
table.params td { padding: 2px 10px 2px 0; vertical-align: top; }
table.params td.paramname { white-space: nowrap; }
table.fieldtable, table.doxtable { border: 1px solid var(--border); box-shadow: var(--shadow); }
table.fieldtable th, table.doxtable th { background: var(--memtitle-bg); text-align: left; padding: 5px 10px; border-bottom: 1px solid var(--border); }
table.fieldtable td, table.doxtable td { padding: 4px 10px; border-top: 1px solid var(--border-soft); vertical-align: top; }
table.directory { width: 100%; }
table.directory td { padding: 3px 8px; border-top: 1px solid var(--border-soft); vertical-align: top; }
table.directory tr:nth-child(even) td { background: var(--member-bg); }
table.directory td.entry { white-space: nowrap; }
table.directory td.desc { color: var(--muted); }
.icon { display: inline-block; width: 16px; height: 16px; line-height: 16px; border-radius: 3px; background: var(--label-bg); color: var(--label-fg); font: bold 10px/16px Arial, sans-serif; text-align: center; margin-right: 5px; vertical-align: 1px; }
.icon.f { background: #7a9a4a; } .icon.p { background: #a07040; } .icon.d { background: #c0a040; } .icon.i { background: #8a6dbf; } .icon.o { background: #3f8f8f; } .icon.e { background: #b05050; }
div.fragment { background: var(--fragment-bg); border: 1px solid var(--fragment-border); padding: 6px 10px; overflow-x: auto; margin: 6px 0; }
div.fragment pre { margin: 0; font-size: 12.5px; }
.srccode { background: var(--fragment-bg); border: 1px solid var(--fragment-border); overflow-x: auto; font: 12.5px/1.5 "JetBrains Mono", Consolas, monospace; }
.srccode .line { white-space: pre; padding-right: 12px; }
.srccode .line:target { background: var(--hl); }
.srccode .lineno { display: inline-block; width: 52px; padding-right: 10px; margin-right: 10px; text-align: right; color: var(--lineno); border-right: 1px solid var(--fragment-border); user-select: none; }
.srccode .lineno a { color: var(--lineno); font-weight: normal; }
a.code { color: var(--page-link); font-weight: normal; }
a.code.hl_decl { font-weight: bold; }
.keyword { color: var(--kw); font-weight: 600; }
.typename { color: var(--type); }
.stringliteral { color: var(--str); }
.numberliteral { color: var(--num); }
.comment { color: var(--com); font-style: italic; }
.annotation, .annotation a { color: var(--ann) !important; }
.qindex { text-align: center; margin: 10px 0 14px; font-size: 15px; }
.qindex a { padding: 0 4px; font-weight: bold; }
.classindex { columns: 4 200px; column-gap: 26px; }
.classindex .ah { font-size: 20px; font-weight: bold; color: var(--tab-fg); border-bottom: 1px solid var(--border); margin: 12px 0 4px; break-after: avoid; }
.classindex div.item { break-inside: avoid; padding: 1px 0; }
.classindex .scope { color: var(--muted); font-size: 12px; }
ul.memberlist { list-style: none; padding-left: 10px; }
ul.memberlist li { padding: 1px 0; }
.letter { font-size: 18px; font-weight: bold; color: var(--tab-fg); margin: 16px 0 4px; }
.hierarchy ul { list-style: none; padding-left: 22px; border-left: 1px dotted var(--border); margin: 2px 0 2px 6px; }
.hierarchy > ul { border-left: none; padding-left: 0; margin-left: 0; }
.hierarchy li { padding: 2px 0; }
.hierarchy .ext { color: var(--muted); }
.graph { overflow-x: auto; margin: 8px 0 12px; }
.graph svg text { font: 12px Arial, sans-serif; fill: var(--graph-text); }
.graph svg .node rect { fill: var(--graph-node); stroke: var(--page-fg); stroke-width: 1; }
.graph svg .node.self rect { fill: var(--graph-self); }
.graph svg .node.ext rect { stroke: var(--muted); stroke-dasharray: 3 2; }
.graph svg .node a:hover rect { stroke: var(--page-link); stroke-width: 2; }
.graph svg path.edge { stroke: var(--graph-edge); fill: none; stroke-width: 1.2; }
.graph svg .arrow { fill: var(--graph-edge); }
.dyncontent .legend { font-size: 12px; color: var(--muted); }
details.graphbox > summary { cursor: pointer; color: var(--page-link); margin: 6px 0; }
.statgrid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 8px; margin: 10px 0 20px; }
.statgrid div { border: 1px solid var(--border-soft); background: var(--member-bg); padding: 8px 10px; border-radius: 4px; }
.statgrid b { display: block; font-size: 20px; color: var(--tab-fg); }
.statgrid span { color: var(--muted); font-size: 12px; }
.navpath { border-top: 1px solid var(--border-soft); background: var(--tab-bg); padding: 5px 18px; font-size: 12.5px; }
.navpath a { color: var(--tab-fg); }
.navpath .sep { color: var(--muted); margin: 0 5px; }
address.footer { text-align: right; padding: 8px 18px 14px; color: var(--muted); font-style: normal; font-size: 12px; }
.coverage { display: inline-block; width: 120px; height: 8px; background: var(--border-soft); border-radius: 4px; overflow: hidden; vertical-align: middle; margin-right: 6px; }
.coverage i { display: block; height: 100%; background: #6aa84f; }
.undoc { color: var(--muted); font-style: italic; }
.fromcomment { font-size: 11px; color: var(--muted); }
@media (max-width: 860px) {
  #side-nav { display: none; position: fixed; z-index: 40; left: 0; top: 0; bottom: 0; max-height: none; box-shadow: var(--shadow); }
  body.nav-open #side-nav { display: block; }
  #nav-toggle { display: inline-block; border: 1px solid var(--border); background: var(--tab-bg); color: var(--tab-fg); border-radius: 4px; padding: 4px 9px; font: inherit; cursor: pointer; }
  #titlearea { padding: 8px 16px; flex-wrap: wrap; }
  #projectname { font-size: 20px; }
  div.contents, div.header { padding-left: 16px; padding-right: 16px; }
  div.summary { float: none; }
  .memItemLeft { white-space: normal; }
  .tabs li.search { margin-left: 0; width: 100%; padding: 4px 8px 6px; }
  #searchbox { width: 100%; max-width: none; }
  #searchresults { left: 0; right: auto; width: 100%; }
}
"""

JS = r"""
(function () {
  var root = document.documentElement;
  try { var t = localStorage.getItem('doc-theme'); if (t) root.setAttribute('data-theme', t); } catch (e) {}
  window.toggleTheme = function () {
    var dark = root.getAttribute('data-theme') === 'dark' ||
      (!root.getAttribute('data-theme') && window.matchMedia('(prefers-color-scheme: dark)').matches);
    var next = dark ? 'light' : 'dark';
    root.setAttribute('data-theme', next);
    try { localStorage.setItem('doc-theme', next); } catch (e) {}
  };
  document.addEventListener('DOMContentLoaded', function () {
    buildTree();
    var nt = document.getElementById('nav-toggle');
    if (nt) nt.onclick = function () { document.body.classList.toggle('nav-open'); };
    setupSearch();
  });

  function here() {
    var p = location.pathname.split('/').pop() || 'index.html';
    return p;
  }

  function buildTree() {
    var nav = document.getElementById('side-nav');
    if (!nav || !window.NAVTREE) return;
    var current = here();
    var opened = {};
    try { opened = JSON.parse(sessionStorage.getItem('doc-nav') || '{}'); } catch (e) {}
    function contains(node) {
      if (node[1] === current) return true;
      return (node[2] || []).some(contains);
    }
    function make(node, depth, key) {
      var li = document.createElement('li');
      var row = document.createElement('div');
      var kids = node[2] || [];
      var arrow = document.createElement('span');
      arrow.className = 'arrow';
      row.appendChild(arrow);
      var a = document.createElement(node[1] ? 'a' : 'span');
      if (node[1]) a.href = node[1];
      a.textContent = node[0];
      a.title = node[0];
      row.appendChild(a);
      li.appendChild(row);
      if (node[1] === current) row.className = 'selected';
      if (kids.length) {
        var ul = document.createElement('ul');
        var open = opened[key] !== undefined ? opened[key] : (depth < 1 || contains(node));
        if (contains(node)) open = true;
        li.className = open ? '' : 'closed';
        arrow.textContent = open ? '▼' : '▶';
        arrow.onclick = function () {
          var closed = li.classList.toggle('closed');
          arrow.textContent = closed ? '▶' : '▼';
          opened[key] = !closed;
          try { sessionStorage.setItem('doc-nav', JSON.stringify(opened)); } catch (e) {}
        };
        kids.forEach(function (k, i) { ul.appendChild(make(k, depth + 1, key + '/' + i)); });
        li.appendChild(ul);
      }
      return li;
    }
    var ul = document.createElement('ul');
    window.NAVTREE.forEach(function (n, i) { ul.appendChild(make(n, 0, '' + i)); });
    nav.appendChild(ul);
    var sel = nav.querySelector('.selected');
    // Scroll the tree only, not the page
    if (sel) nav.scrollTop = sel.offsetTop - nav.clientHeight / 2;
  }

  function fold(s) {
    return s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
  }

  function setupSearch() {
    var box = document.getElementById('searchbox');
    var res = document.getElementById('searchresults');
    if (!box || !window.SEARCHDATA) return;
    var data = window.SEARCHDATA.map(function (d) { return { d: d, f: fold(d[0]) }; });
    var sel = -1;
    function show() {
      var q = fold(box.value.trim());
      res.innerHTML = '';
      sel = -1;
      if (!q) { res.style.display = 'none'; return; }
      var hits = data.filter(function (x) { return x.f.indexOf(q) >= 0; });
      hits.sort(function (a, b) {
        var ra = a.f === q ? 0 : a.f.indexOf(q) === 0 ? 1 : 2;
        var rb = b.f === q ? 0 : b.f.indexOf(q) === 0 ? 1 : 2;
        return ra - rb || a.f.length - b.f.length || (a.f < b.f ? -1 : 1);
      });
      hits.slice(0, 60).forEach(function (x) {
        var a = document.createElement('a');
        a.href = x.d[3];
        a.textContent = x.d[0];
        var s = document.createElement('span');
        s.className = 'sk';
        s.textContent = x.d[1] + (x.d[2] ? ' · ' + x.d[2] : '');
        a.appendChild(s);
        res.appendChild(a);
      });
      if (!hits.length) {
        var n = document.createElement('div');
        n.className = 'none';
        n.textContent = 'No matches';
        res.appendChild(n);
      }
      res.style.display = 'block';
    }
    box.addEventListener('input', show);
    box.addEventListener('focus', show);
    box.addEventListener('keydown', function (e) {
      var links = res.querySelectorAll('a');
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        if (!links.length) return;
        if (sel >= 0) links[sel].classList.remove('sel');
        sel = (sel + (e.key === 'ArrowDown' ? 1 : -1) + links.length) % links.length;
        links[sel].classList.add('sel');
        links[sel].scrollIntoView({ block: 'nearest' });
      } else if (e.key === 'Enter') {
        var a = links[sel >= 0 ? sel : 0];
        if (a) location.href = a.href;
      } else if (e.key === 'Escape') {
        res.style.display = 'none';
        box.blur();
      }
    });
    document.addEventListener('click', function (e) {
      if (e.target !== box && !res.contains(e.target)) res.style.display = 'none';
    });
  }
})();
"""

# ---------------------------------------------------------------- the site

TABS = [
    ("Main Page", "index.html", "main"),
    ("Folders", "folders.html", "folders"),
    ("Types", "annotated.html", "types"),
    ("Files", "files.html", "files"),
]
SUBTABS = {
    "types": [("Type List", "annotated.html"), ("Type Index", "classes.html"), ("Type Members", "functions.html")],
    "files": [("File List", "files.html"), ("File Members", "globals.html")],
}
ICONS = {"struct": ("S", "d"), "class": ("C", ""), "enum": ("E", "e"), "protocol": ("P", "i"), "actor": ("A", "o"),
         "extension": ("X", "o"), "func": ("F", "f"), "init": ("F", "f"), "var": ("V", "p"), "let": ("V", "p"),
         "case": ("E", "e"), "typealias": ("T", ""), "subscript": ("F", "f")}


def icon(d):
    letter, cls = ICONS.get(d.kind, ("?", ""))
    return f'<span class="icon {cls}">{letter}</span>'


class Site:
    def __init__(self, project, out):
        self.p = project
        self.out = out
        self.search = []
        # Names to link, in code and in backticks: types first, then unique member names
        self.names = {name: t for name, t in project.types.items()}
        by_name = defaultdict(list)
        for d in project.all_decls():
            if d.kind not in TYPE_KINDS and d.page:
                by_name[d.name].append(d)
        self.member_names = {k: v[0] for k, v in by_name.items() if len(v) == 1}

    # -- page frame

    def write(self, name, title, body, tab=None, subtab=None, summary="", navpath=None):
        tabs = "".join(f'<li class="{"current" if key == tab else ""}"><a href="{href}">{esc(label)}</a></li>' for label, href, key in TABS)
        tabs += '<li class="search"><input id="searchbox" type="search" placeholder="Search" autocomplete="off" aria-label="Search"><div id="searchresults"></div></li>'
        sub = ""
        if tab in SUBTABS:
            sub = '<ul class="tabs2">' + "".join(
                f'<li class="{"current" if href == subtab else ""}"><a href="{href}">{esc(label)}</a></li>' for label, href in SUBTABS[tab]) + "</ul>"
        nav = ""
        if navpath:
            nav = '<div class="navpath">' + '<span class="sep">›</span>'.join(
                f'<a href="{href}">{esc(label)}</a>' if href else esc(label) for label, href in navpath) + "</div>"
        version = f'<span id="projectnumber">{esc(self.p.version)}</span>' if self.p.version else ""
        commit = f' from commit <a href="{REPO_URL}/commit/{esc(self.p.commit)}">{esc(self.p.commit)}</a>' if self.p.commit else ""
        page = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="generator" content="scripts/gen_docs.py">
<title>Kastoria City Buses for iOS: {esc(title)}</title>
<link rel="icon" href="../icon.png" type="image/png">
<link rel="stylesheet" href="doxygen.css">
<script src="navtreedata.js"></script>
<script src="searchdata.js"></script>
<script src="docs.js"></script>
</head>
<body>
<div id="top">
<div id="titlearea">
<button id="nav-toggle" type="button" aria-label="Show navigation">☰</button>
<div id="projectlogo"><img alt="" src="../icon.png"></div>
<div><div id="projectname">Kastoria City Buses for iOS{version}</div>
<div id="projectbrief">Αστικά Καστοριάς · iPhone app source documentation</div></div>
<button id="theme-toggle" type="button" onclick="toggleTheme()" title="Light or dark">◐</button>
</div>
<ul class="tabs">{tabs}</ul>
{sub}
</div>
<div id="layout">
<nav id="side-nav" aria-label="Contents"></nav>
<div id="doc-content">
<div class="header">
{f'<div class="summary">{summary}</div>' if summary else ""}
<div class="headertitle"><div class="title">{esc(title)}</div></div>
</div>
<div class="contents">
{body}
</div>
{nav}
<address class="footer">Generated {esc(self.p.commit_date)}{commit} by <code>scripts/gen_docs.py</code>, a Doxygen-style generator for Swift</address>
</div>
</div>
</body>
</html>
"""
        (self.out / name).write_text(page, encoding="utf-8", newline="\n")

    # -- text

    def link_name(self, name, context=None):
        """The page of a type or member called `name`, if there's exactly one"""
        if name in self.names:
            return self.names[name].url
        if context is not None:
            owner = context if context.is_type else context.parent
            if owner is not None:
                for m in self.p.members_of(owner) if owner.name in self.p.types else owner.members:
                    if m.name == name:
                        return m.url
        d = self.member_names.get(name)
        return d.url if d else None

    def inline(self, text, context=None):
        """Doc text to HTML: `code` linked where it names something, **bold**, *italic*, [links](url)"""
        out = []
        pos = 0
        for m in re.finditer(r"`([^`]+)`|\*\*([^*]+)\*\*|\[([^\]]+)\]\(([^)]+)\)", text):
            out.append(self.plain(text[pos:m.start()]))
            if m.group(1) is not None:
                code = m.group(1)
                target = self.link_name(re.sub(r"\(.*\)$", "", code.split(".")[-1]), context)
                out.append(f'<code><a class="el" href="{target}">{esc(code)}</a></code>' if target else f"<code>{esc(code)}</code>")
            elif m.group(2) is not None:
                out.append(f"<b>{esc(m.group(2))}</b>")
            else:
                out.append(f'<a href="{esc(m.group(4))}">{esc(m.group(3))}</a>')
            pos = m.end()
        out.append(self.plain(text[pos:]))
        return "".join(out)

    def plain(self, s):
        s = esc(s)
        return re.sub(r"(https?://[^\s<]+[^\s<.,)])", r'<a href="\1">\1</a>', s)

    def block(self, text, context=None):
        """Paragraphs, bullet lists and code blocks"""
        html_out = []
        for para in re.split(r"\n\s*\n", text):
            lines = [ln for ln in para.split("\n")]
            if all(ln.strip().startswith(("- ", "* ")) or not ln.strip() for ln in lines) and any(ln.strip() for ln in lines):
                items = [self.inline(ln.strip()[2:], context) for ln in lines if ln.strip()]
                html_out.append("<ul>" + "".join(f"<li>{i}</li>" for i in items) + "</ul>")
            elif all(ln.startswith("    ") or not ln.strip() for ln in lines):
                html_out.append(f'<div class="fragment"><pre>{esc(chr(10).join(ln[4:] for ln in lines))}</pre></div>')
            else:
                html_out.append(f"<p>{self.inline(' '.join(ln.strip() for ln in lines), context)}</p>")
        return "".join(html_out)

    # -- declarations

    def code_html(self, sig, context=None):
        """A signature coloured, with type names linked"""
        out = []
        for m in re.finditer(r"@\w+|[A-Za-z_][\w]*|\"[^\"]*\"|\d[\d.]*|\s+|.", sig):
            w = m.group(0)
            if w.startswith("@"):
                out.append(f'<span class="annotation">{esc(w)}</span>')
            elif w in KEYWORDS:
                out.append(f'<span class="keyword">{esc(w)}</span>')
            elif w[0].isupper() and w in self.names:
                out.append(f'<a class="el" href="{self.names[w].url}">{esc(w)}</a>')
            elif w[0].isupper():
                out.append(f'<span class="typename">{esc(w)}</span>')
            elif w.startswith('"'):
                out.append(f'<span class="stringliteral">{esc(w)}</span>')
            else:
                out.append(esc(w))
        return "".join(out)

    def labels(self, d):
        out = [m for m in d.modifiers if m in ("private", "fileprivate", "static", "mutating", "override", "lazy", "nonisolated", "final", "convenience")]
        if any(a.startswith("@MainActor") for a in d.attributes):
            out.append("@MainActor")
        if any(a.startswith("@Published") for a in d.attributes):
            out.append("@Published")
        if any(a.startswith(("@State", "@Binding", "@EnvironmentObject", "@Environment", "@StateObject")) for a in d.attributes):
            out.append(next(a for a in d.attributes if a.startswith(("@State", "@Binding", "@EnvironmentObject", "@Environment", "@StateObject"))).split("(")[0])
        if d.parent is not None and d.parent.kind == "extension":
            out.append("extension")
        if "async" in d.signature.split():
            out.append("async")
        if re.search(r"\bthrows\b", d.signature):
            out.append("throws")
        return out

    def member_row(self, d):
        brief = self.inline(d.doc.brief, d) if d.doc.brief else ""
        sig = d.signature
        sig = re.sub(r"^(?:@\S+\s+)*", "", sig)
        return (f'<tr class="memitem"><td class="memItemLeft">{icon(d)}</td>'
                f'<td class="memItemRight"><a class="el" href="{d.url}">{esc(d.title)}</a> '
                f'<span class="params">{self.code_html(sig[sig.find(d.name) + len(d.name):] if d.name in sig and d.kind not in ("case",) else "", d)}</span></td></tr>'
                + (f'<tr><td class="mdescLeft"></td><td class="mdescRight">{brief}</td></tr>' if brief else "")
                + '<tr class="separator"><td class="memSeparator" colspan="2"></td></tr>')

    def member_doc(self, d):
        labels = "".join(f'<span class="mlabel">{esc(l)}</span>' for l in self.labels(d))
        attrs = [a for a in d.attributes]
        ann = f'<div class="annotations">{esc(" ".join(attrs))}</div>' if attrs else ""
        sig = re.sub(r"^(?:@\S+(?:\([^)]*\))?\s+)*", "", d.signature)
        proto = (f'<div class="memproto">{ann}<table class="mlabels"><tr><td class="mlabels-left">'
                 f'<table class="memname"><tr><td class="memname">{self.code_html(sig, d)}</td></tr></table></td>'
                 f'<td class="mlabels-right">{labels}</td></tr></table></div>')
        return (f'<a id="{d.anchor}"></a>\n<h2 class="memtitle"><span class="permalink"><a href="#{d.anchor}">◆</a></span>{esc(d.title)}</h2>\n'
                f'<div class="memitem">{proto}<div class="memdoc">{self.doc_body(d)}</div></div>\n')

    def doc_body(self, d):
        out = []
        if d.doc.text:
            out.append(f'<div class="textblock">{self.block(d.doc.text, d)}</div>')
        else:
            out.append('<p class="undoc">Not documented.</p>')
        if d.doc.params:
            rows = "".join(f'<tr><td class="paramname">{esc(k)}</td><td>{self.inline(v, d)}</td></tr>' for k, v in d.doc.params.items())
            out.append(f'<dl class="params"><dt>Parameters</dt><dd><table class="params">{rows}</table></dd></dl>')
        if d.doc.returns:
            out.append(f'<dl class="section return"><dt>Returns</dt><dd>{self.inline(d.doc.returns, d)}</dd></dl>')
        if d.doc.throws:
            out.append(f'<dl class="section"><dt>Throws</dt><dd>{self.inline(d.doc.throws, d)}</dd></dl>')
        lines = f"line {d.line}" if d.end_line <= d.line else f"lines {d.line}–{d.end_line}"
        out.append(f'<p class="definition">Definition at {lines} of file <a class="el" href="{d.file.src_page}#l{d.line:05d}">{esc(d.file.name)}</a>.</p>')
        return "".join(out)

    def member_table(self, title, decls):
        if not decls:
            return ""
        rows = "".join(self.member_row(d) for d in decls)
        return f'<h2 class="groupheader">{esc(title)}</h2><table class="memberdecls">{rows}</table>'

    def grouped_tables(self, members):
        groups = [
            ("Enum cases", [m for m in members if m.kind == "case"]),
            ("Initializers", [m for m in members if m.kind == "init"]),
            ("Properties", [m for m in members if m.kind in ("var", "let") and "static" not in m.modifiers]),
            ("Methods", [m for m in members if m.kind in ("func", "subscript") and "static" not in m.modifiers]),
            ("Static members", [m for m in members if m.kind in ("var", "let", "func") and "static" in m.modifiers]),
            ("Nested types", [m for m in members if m.kind in TYPE_KINDS]),
            ("Type aliases", [m for m in members if m.kind == "typealias"]),
        ]
        return "".join(self.member_table(t, ds) for t, ds in groups)

    # -- pages

    def type_page(self, t, name):
        members = self.p.members_of(t) if name in self.p.types else list(t.members)
        doc = f'<div class="textblock">{self.block(t.doc.text, t)}</div>' if t.doc.text else '<p class="undoc">Not documented.</p>'
        sig = re.sub(r"^(?:@\S+(?:\([^)]*\))?\s+)*", "", t.signature)
        attrs = " ".join(t.attributes)
        decl = (f'<div class="fragment"><pre>{esc(attrs) + chr(10) if attrs else ""}{self.code_html(sig, t)}</pre></div>')
        ext = ""
        if t.extensions:
            items = "".join(
                f'<li><a class="el" href="{e.file.src_page}#l{e.line:05d}">{esc(e.file.name)}, line {e.line}</a>'
                + (f": {self.inline(e.doc.brief, e)}" if e.doc.brief else "")
                + (f' <code>{self.code_html(e.inherits)}</code>' if e.inherits else "") + "</li>"
                for e in t.extensions)
            ext = f'<h2 class="groupheader">Extensions</h2><ul>{items}</ul>'
        detail = "".join(self.member_doc(m) for m in members if m.kind not in TYPE_KINDS)
        nested = [m for m in members if m.kind in TYPE_KINDS]
        body = (f'{decl}{doc}<p class="definition">Defined in <a class="el" href="{t.file.src_page}#l{t.line:05d}">{esc(t.file.rel)}</a>, '
                f'lines {t.line}–{t.end_line}.</p>{ext}{self.grouped_tables(members)}'
                + (f'<h2 class="groupheader">Member Documentation</h2>{detail}' if detail else ""))
        self.write(t.page, f"{name} {t.kind} reference", body, tab="types", subtab="annotated.html",
                   navpath=[(t.file.folder, f"folder_{t.file.folder}.html"), (t.file.name, t.file.page), (name, None)])
        self.search.append([name, t.kind, t.file.folder, t.page])
        for m in members:
            if m.kind in TYPE_KINDS:
                continue
            self.search.append([m.name, m.kind, name, m.url])
        for nt in nested:
            self.type_page(nt, f"{name}.{nt.name}")

    def file_page(self, f):
        types = [d for d in f.decls if d.kind in TYPE_KINDS]
        others = [d for d in f.decls if d.kind not in TYPE_KINDS]
        type_rows = "".join(
            f'<tr><td class="memItemLeft">{icon(d)}</td><td class="memItemRight">{d.kind} <a class="el" href="{d.url}">{esc(d.name)}</a></td></tr>'
            + (f'<tr><td class="mdescLeft"></td><td class="mdescRight">{self.inline(d.doc.brief, d)}</td></tr>' if d.doc.brief else "")
            for d in types)
        imports = ", ".join(f"<code>{esc(i)}</code>" for i in f.imports)
        body = (f'<p>Folder <a class="el" href="folder_{f.folder}.html">{esc(f.folder)}</a>, {f.lines} lines. '
                f'<a class="el" href="{f.src_page}">Go to the source code of this file.</a></p>'
                + (f"<p>Imports {imports}.</p>" if imports else "")
                + (f'<h2 class="groupheader">Types and extensions</h2><table class="memberdecls">{type_rows}</table>' if types else "")
                + self.grouped_tables(others)
                + (f'<h2 class="groupheader">Documentation</h2>{"".join(self.member_doc(d) for d in others)}' if others else ""))
        self.write(f.page, f"{f.name} file reference", body, tab="files", subtab="files.html",
                   navpath=[(f.folder, f"folder_{f.folder}.html"), (f.name, None)])
        self.search.append([f.name, "file", f.folder, f.page])
        for d in others:
            self.search.append([d.name, d.kind, f.name, d.url])

    def source_page(self, f):
        decl_at = {}
        for d in f.all:
            if d.name_tok is not None:
                decl_at[d.name_tok] = d
        parts = []
        pos = 0
        for idx, t in enumerate(f.tokens):
            parts.append(esc(f.src[pos:t.start]))
            text = esc(f.src[t.start:t.end])
            if t.kind == "comment":
                text = f'<span class="comment">{text}</span>'
            elif t.kind == "str":
                text = f'<span class="stringliteral">{text}</span>'
            elif t.kind == "num":
                text = f'<span class="numberliteral">{text}</span>'
            elif t.kind == "attr":
                text = f'<span class="annotation">{text}</span>'
            elif t.kind == "id":
                if idx in decl_at:
                    text = f'<a class="code hl_decl" href="{decl_at[idx].url}">{text}</a>'
                elif t.text in KEYWORDS:
                    text = f'<span class="keyword">{text}</span>'
                elif t.text in self.names:
                    text = f'<a class="code" href="{self.names[t.text].url}">{text}</a>'
                elif t.text in self.member_names and idx > 0 and f.tokens[idx - 1].text == ".":
                    text = f'<a class="code" href="{self.member_names[t.text].url}">{text}</a>'
            parts.append(text)
            pos = t.end
        parts.append(esc(f.src[pos:]))
        code = "".join(parts).split("\n")
        lines = "".join(
            f'<div class="line" id="l{n:05d}"><span class="lineno"><a href="#l{n:05d}">{n}</a></span>{ln or " "}</div>'
            for n, ln in enumerate(code, start=1))
        body = (f'<p><a class="el" href="{f.page}">Go to the documentation of this file.</a> '
                f'<a href="{REPO_URL}/blob/main/{f.rel}">{esc(f.rel)} on GitHub</a></p>'
                f'<div class="fragment srccode">{lines}</div>')
        self.write(f.src_page, f.name, body, tab="files", subtab="files.html",
                   navpath=[(f.folder, f"folder_{f.folder}.html"), (f.name, f.page), ("source", None)])

    def lists(self):
        p = self.p
        all_types = []
        for name, t in sorted(p.types.items(), key=lambda kv: kv[0].lower()):
            all_types.append((name, t))
            for nt in t.members:
                if nt.kind in TYPE_KINDS:
                    all_types.append((f"{name}.{nt.name}", nt))
        rows = "".join(
            f'<tr><td class="entry">{icon(t)}<a class="el" href="{t.page}">{esc(name)}</a></td>'
            f'<td class="desc">{self.inline(t.doc.brief, t)}</td></tr>' for name, t in all_types)
        self.write("annotated.html", "Type List", f'<p>Every type, with a short description.</p><table class="directory">{rows}</table>',
                   tab="types", subtab="annotated.html")
        letters = defaultdict(list)
        for name, t in all_types:
            letters[name[0].upper()].append((name, t))
        index = "".join(
            f'<div class="letter">{esc(k)}</div><ul class="memberlist">'
            + "".join(f'<li><a class="el" href="{t.page}">{esc(n)}</a> <span class="scope">({esc(t.file.folder)})</span></li>' for n, t in v)
            + "</ul>" for k, v in sorted(letters.items()))
        self.write("classes.html", "Type Index", index, tab="types", subtab="classes.html")
        members = sorted((m for _, t in all_types for m in (p.members_of(t) if t.name in p.types else t.members) if m.kind not in TYPE_KINDS),
                         key=lambda m: (m.name.lower(), m.scope))
        items = "".join(f'<li><a class="el" href="{m.url}">{esc(m.title)}</a> : {esc(m.parent.name if m.parent else m.scope)}</li>' for m in members)
        self.write("functions.html", "Type Members", f'<p>Every member of every type.</p><ul class="memberlist">{items}</ul>',
                   tab="types", subtab="functions.html")
        frows = "".join(
            f'<tr><td class="entry"><a class="el" href="{f.page}">{esc(f.rel)}</a></td><td class="desc">{f.lines} lines</td></tr>'
            for f in p.files)
        self.write("files.html", "File List", f'<table class="directory">{frows}</table>', tab="files", subtab="files.html")
        globals_ = sorted((d for f in p.files for d in f.decls if d.kind not in TYPE_KINDS), key=lambda d: d.name.lower())
        gitems = "".join(f'<li><a class="el" href="{d.url}">{esc(d.title)}</a> : {esc(d.file.name)}</li>' for d in globals_)
        self.write("globals.html", "File Members", f'<p>Declarations outside any type.</p><ul class="memberlist">{gitems}</ul>',
                   tab="files", subtab="globals.html")
        folders = defaultdict(list)
        for f in p.files:
            folders[f.folder].append(f)
        frows = "".join(
            f'<tr><td class="entry"><a class="el" href="folder_{k}.html">{esc(k)}</a></td><td class="desc">{esc(FOLDERS.get(k, ""))}</td></tr>'
            for k in folders)
        self.write("folders.html", "Folders", f'<table class="directory">{frows}</table>', tab="folders")
        for k, fs in folders.items():
            rows = []
            for f in fs:
                ts = ", ".join(f'<a class="el" href="{d.url}">{esc(d.name)}</a>' for d in f.decls if d.kind in TYPE_KINDS - {"extension"})
                rows.append(f'<tr><td class="entry"><a class="el" href="{f.page}">{esc(f.name)}</a></td><td class="desc">{ts}</td></tr>')
            self.write(f"folder_{k}.html", f"{k} folder reference", f'<p>{esc(FOLDERS.get(k, ""))}.</p><table class="directory">{"".join(rows)}</table>',
                       tab="folders", navpath=[(k, None)])
        return all_types, folders

    def main_page(self, folders):
        p = self.p
        want, have = p.documented()
        types = len(p.types)
        decls = sum(1 for _ in p.all_decls())
        lines = sum(f.lines for f in p.files)
        stats = "".join(f"<div><b>{v}</b><span>{esc(k)}</span></div>" for k, v in [
            ("Swift files", len(p.files)), ("lines", lines), ("types", types), ("declarations", decls)])
        undoc = [d for d in want if not d.doc.text]
        coverage = (f'<p class="coverage">{len(have)} of {len(want)} declarations documented.'
                    + (" Not documented yet: " + ", ".join(f'<a class="el" href="{d.url}">{esc(d.scope)}.{esc(d.title)}</a>' for d in undoc[:60]) if undoc else "")
                    + "</p>")
        frows = "".join(
            f'<tr><td class="entry"><a class="el" href="folder_{k}.html">{esc(k)}</a></td><td class="desc">{esc(FOLDERS.get(k, ""))}</td></tr>'
            for k in folders)
        body = f"""<div class="textblock">
<p>The source code of the iPhone app for the city buses of Kastoria, in SwiftUI. It does what the
<a href="https://kastoria-dev-core.github.io/astiko-ktel-kastorias-app/">Android app</a> does, the same way: the
timetable logic, the bus estimates, the live trips and the journey planner are ports of its Kotlin code, and the
data, the live bus server and the text are the same.</p>
<p>Start with <a class="el" href="{p.types['AppContainer'].url if 'AppContainer' in p.types else 'annotated.html'}">AppContainer</a> (what the screens
share), <a class="el" href="{p.types['Schedule'].url if 'Schedule' in p.types else 'annotated.html'}">Schedule</a> (the timetable logic) and
<a class="el" href="{p.types['RootView'].url if 'RootView' in p.types else 'annotated.html'}">RootView</a> (the tabs and the screens they open).</p>
</div>
<div class="statgrid">{stats}</div>
{coverage}
<h2 class="groupheader">Folders</h2><table class="directory">{frows}</table>
<p>Source: <a href="{REPO_URL}">{REPO_URL}</a></p>"""
        self.write("index.html", "Kastoria City Buses for iOS", body, tab="main")
        return want, have

    def data_files(self, all_types, folders):
        tree = [["Main Page", "index.html", []],
                ["Folders", "folders.html", [[k, f"folder_{k}.html", [[f.name, f.page, []] for f in fs]] for k, fs in folders.items()]],
                ["Types", "annotated.html", [[name, t.page, []] for name, t in all_types]],
                ["Files", "files.html", [[f.rel, f.page, []] for f in self.p.files]]]
        (self.out / "navtreedata.js").write_text("window.NAVTREE = " + json.dumps(tree, ensure_ascii=False) + ";\n", encoding="utf-8", newline="\n")
        seen = set()
        data = []
        for row in self.search:
            key = tuple(row)
            if key not in seen:
                seen.add(key)
                data.append(row)
        (self.out / "searchdata.js").write_text("window.SEARCHDATA = " + json.dumps(data, ensure_ascii=False) + ";\n", encoding="utf-8", newline="\n")
        (self.out / "doxygen.css").write_text(CSS, encoding="utf-8", newline="\n")
        (self.out / "docs.js").write_text(JS, encoding="utf-8", newline="\n")


def main():
    project = Project()
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*"):
        if old.is_file():
            old.unlink()
    site = Site(project, OUT)
    for name, t in project.types.items():
        site.type_page(t, name)
    for e in project.orphan_extensions:
        body = (f'<p>Adds to <code>{esc(e.name)}</code>, which isn\'t defined in this app.</p>'
                + (f'<div class="textblock">{site.block(e.doc.text, e)}</div>' if e.doc.text else "")
                + site.grouped_tables(e.members)
                + f'<h2 class="groupheader">Member Documentation</h2>{"".join(site.member_doc(m) for m in e.members)}')
        site.write(e.page, f"{e.name} extension reference", body, tab="types", subtab="annotated.html",
                   navpath=[(e.file.folder, f"folder_{e.file.folder}.html"), (e.file.name, e.file.page), (e.name, None)])
        site.search.append([e.name, "extension", e.file.name, e.page])
        for m in e.members:
            site.search.append([m.name, m.kind, e.name, m.url])
    for f in project.files:
        site.file_page(f)
        site.source_page(f)
    all_types, folders = site.lists()
    want, have = site.main_page(folders)
    site.data_files(all_types, folders)
    print(f"{len(list(OUT.glob('*.html')))} pages in {OUT.relative_to(ROOT).as_posix()}: "
          f"{len(project.files)} files, {len(project.types)} types, {len(have)}/{len(want)} declarations documented")
    missing = [d for d in want if not d.doc.text]
    for d in missing:
        print(f"  not documented: {d.file.rel}:{d.line} {d.scope}.{d.title}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
