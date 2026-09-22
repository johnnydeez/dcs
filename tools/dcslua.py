"""Reader for DCS's Lua table serialization (the `mission` file inside a .miz,
`options`, `warehouses`, and our own data/*.lua files).

Handles the subset DCS and we emit:
    name = { ["key"] = value, [1] = value, key = value, ... }
    strings ("..." with backslash escapes), numbers, true/false/nil,
    nested tables, trailing commas, -- line comments.
Returns plain Python dicts (tables), str, float/int, bool, None.

Not a general Lua interpreter: no expressions, no function calls.
"""

import re
import zipfile


class LuaParseError(ValueError):
    pass


_TOKEN = re.compile(r'''
    (?P<ws>\s+|--[^\n]*)                       # whitespace / line comment
  | (?P<str>"(?:\\.|[^"\\])*")
  | (?P<num>-?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<punct>[{}\[\]=,])
''', re.X)

_ESCAPES = {'n': '\n', 't': '\t', 'r': '\r', '\\': '\\', '"': '"', "'": "'", '\n': '\n'}


def _unescape(s):
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            nxt = s[i + 1]
            if nxt in _ESCAPES:
                out.append(_ESCAPES[nxt])
                i += 2
                continue
            if nxt.isdigit():
                m = re.match(r'\d{1,3}', s[i + 1:])
                out.append(chr(int(m.group(0))))
                i += 1 + len(m.group(0))
                continue
        out.append(c)
        i += 1
    return ''.join(out)


def _tokenize(text):
    pos = 0
    n = len(text)
    while pos < n:
        m = _TOKEN.match(text, pos)
        if not m:
            raise LuaParseError("unexpected character %r at offset %d" % (text[pos], pos))
        pos = m.end()
        kind = m.lastgroup
        if kind == 'ws':
            continue
        yield kind, m.group(kind)
    yield 'eof', ''


class _Parser:
    def __init__(self, text):
        self._toks = list(_tokenize(text))
        self._i = 0

    def peek(self):
        return self._toks[self._i]

    def take(self, kind=None, value=None):
        k, v = self._toks[self._i]
        if (kind and k != kind) or (value is not None and v != value):
            raise LuaParseError("expected %s %r, got %s %r (token %d)" % (kind, value, k, v, self._i))
        self._i += 1
        return v

    def value(self):
        k, v = self.peek()
        if k == 'str':
            self.take()
            return _unescape(v[1:-1])
        if k == 'num':
            self.take()
            return int(v) if re.fullmatch(r'-?\d+', v) else float(v)
        if k == 'name':
            self.take()
            if v == 'true':
                return True
            if v == 'false':
                return False
            if v == 'nil':
                return None
            raise LuaParseError("unexpected identifier %r" % v)
        if k == 'punct' and v == '{':
            return self.table()
        raise LuaParseError("unexpected token %s %r" % (k, v))

    def table(self):
        self.take('punct', '{')
        result = {}
        auto_index = 1
        while True:
            k, v = self.peek()
            if k == 'punct' and v == '}':
                self.take()
                return result
            if k == 'punct' and v == '[':
                self.take()
                key = self.value()
                self.take('punct', ']')
                self.take('punct', '=')
                result[key] = self.value()
            elif k == 'name' and self._toks[self._i + 1] == ('punct', '='):
                key = self.take('name')
                self.take('punct', '=')
                result[key] = self.value()
            else:
                result[auto_index] = self.value()
                auto_index += 1
            k, v = self.peek()
            if k == 'punct' and v == ',':
                self.take()


def loads(text):
    """Parse `name = { ... }` (or a bare `{ ... }`) and return the table as a dict."""
    p = _Parser(text)
    k, v = p.peek()
    if k == 'name':
        p.take('name')
        p.take('punct', '=')
    result = p.value()
    p.take('eof')
    return result


def load_miz(path, member='mission'):
    """Read one Lua-table member out of a .miz archive."""
    with zipfile.ZipFile(path) as z:
        text = z.read(member).decode('utf-8')
    return loads(text)


def as_list(tbl):
    """Convert a 1-based integer-keyed table into a Python list, in index order."""
    if isinstance(tbl, list):
        return tbl
    return [tbl[i] for i in sorted(k for k in tbl if isinstance(k, int))]


# ── Emit ─────────────────────────────────────────────────────────────

def _lua_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'


def dumps(value, indent=0, key_order=None):
    """Serialize a Python value to a Lua literal. Dicts become tables; lists become
    1-based arrays. `key_order` lists dict keys to emit first, in that order."""
    pad = '    ' * indent
    if value is None:
        return 'nil'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, str):
        return _lua_str(value)
    if isinstance(value, (list, tuple)):
        if not value:
            return '{}'
        if all(isinstance(v, (int, float)) for v in value):
            return '{ ' + ', '.join(dumps(v) for v in value) + ' }'
        inner = ',\n'.join(pad + '    ' + dumps(v, indent + 1, key_order) for v in value)
        return '{\n' + inner + ',\n' + pad + '}'
    if isinstance(value, dict):
        if not value:
            return '{}'
        keys = list(value.keys())
        if key_order:
            keys.sort(key=lambda k: (key_order.index(k) if k in key_order else len(key_order), str(k)))
        lines = []
        for k in keys:
            lk = k if (isinstance(k, str) and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', k)) else '[' + dumps(k) + ']'
            lines.append(pad + '    ' + lk + ' = ' + dumps(value[k], indent + 1, key_order))
        return '{\n' + ',\n'.join(lines) + ',\n' + pad + '}'
    raise TypeError("cannot serialize %r" % type(value))
