#!/usr/bin/env python

from __future__ import absolute_import, division, print_function, unicode_literals

import re

try:
    unicode
except NameError:
    unicode = str
try:
    bytes
except NameError:
    bytes = str

try:
    from collections.abc import Mapping, Sequence
except ImportError:
    from collections import Mapping, Sequence

ident_re = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')


def flatten(d, key_re=None):
    """Flatten the given JSON/YAML deserialized data."""
    return _flatten(None, d, key_re)


def _flatten(p, d, key_re):
    if p is None:
        p1 = ''
    else:
        p1 = p + '.'
    if isinstance(d, Mapping):
        for k, v in d.items():
            if key_re is not None:
                m = key_re.search(k)
                if m is None:
                    raise ValueError(
                        "invalid (sub-)key %r under parent key %r" % (p, k))
            for r in _flatten(p1 + k, v, key_re):
                yield r
    elif isinstance(d, Sequence) and not isinstance(d, (unicode, bytes)):
        for i, v in enumerate(d):
            for r in _flatten(p1 + str(i), v, key_re):
                yield r
    else:
        yield p, d


if __name__ == '__main__':
    import argparse
    import sys
    parser = argparse.ArgumentParser(description="""
        Flattens a JSON/YAML configuration into a list of tab-separated
        key-value pairs.""")
    parser.add_argument('--yaml', '-y', dest='input_type',
                        action='store_const', const='yaml',
                        help="""treat input(s) as YAML""")
    parser.add_argument('--json', '-j', dest='input_type',
                        action='store_const', const='json',
                        help="""treat input(s) as JSON (default)""")
    parser.add_argument('--ident', '-I', dest='key_re',
                        action='store_const', const=ident_re,
                        help="""validate keys as identifiers""")
    parser.add_argument('--key-re', '-R', dest='key_re', type=re.compile,
                        metavar='REGEX',
                        help="""validate keys using the given regex""")
    parser.add_argument('--sep', '-S',
                        help="""key-value separator (default: tab)""")
    parser.add_argument('filenames', nargs='*', metavar='FILE',
                        help="""input filename(s); - is stdin (default)""")
    parser.set_defaults(input_type='json', sep='\t')
    args = parser.parse_args()
    if args.input_type == 'json':
        import json
        load = json.load
    elif args.input_type == 'yaml':
        import yaml
        load = yaml.load
    else:
        parser.error("invalid input type %r" % (args.input_type,))
    for filename in args.filenames or ['-']:
        if filename == '-':
            d = load(sys.stdin)
        else:
            with open(filename) as f:
                d = load(f)
        for k, v in flatten(d, args.key_re):
            if isinstance(v, bool):
                v = v and 'true' or 'false'
            print(k or '', args.sep, v, sep='')
