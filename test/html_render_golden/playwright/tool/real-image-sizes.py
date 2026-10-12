#!/usr/bin/env python3
"""Rewrite the placeholder image sizes of the scrubbed fixture emails to the real ones.

Reads the original .eml files, pairs each <img src> / CSS url() with the same slot in
the matching fixture (eml_N.html.gz) and replaces the placeholder size by the size of
the original image. Fixtures stay scrubbed: only the WxH of fixture.invalid URLs changes.

Fetching original images contacts the senders' servers (tracking pixels included),
so it only runs with --fetch.
"""
import argparse
import base64
import concurrent.futures
import email
import email.policy
import gzip
import ipaddress
import re
import struct
import sys
import urllib.parse
import urllib.request
from pathlib import Path

IMG = re.compile(r'<img\b[^>]*?(?<![\w-])src\s*=\s*(["\']?)([^"\'\s>]+)\1', re.I)
URL = re.compile(r'url\(\s*(["\']?)([^"\')]+)\1\s*\)', re.I)
PLACEHOLDER = re.compile(r'^https://fixture\.invalid/(img|est|cid)/(\d+)x(\d+)(.*)$', re.S)
HEAD_BYTES = 512 * 1024
JPEG_NO_LENGTH = {0x00, 0x01, 0xD8, *range(0xD0, 0xD8)}
JPEG_FRAME = set(range(0xC0, 0xD0)) - {0xC4, 0xC8, 0xCC}


def png_size(d):
    return struct.unpack('>II', d[16:24]) if d[:8] == b'\x89PNG\r\n\x1a\n' else None


def gif_size(d):
    return struct.unpack('<HH', d[6:10]) if d[:6] in (b'GIF87a', b'GIF89a') else None


def jpeg_segment(d, i):
    """(marker, bytes to skip) of the segment at i; filler bytes are skipped one by one."""
    if d[i] != 0xFF or d[i + 1] == 0xFF:
        return None, 1
    marker = d[i + 1]
    if marker in JPEG_NO_LENGTH:
        return marker, 2
    return marker, 2 + struct.unpack('>H', d[i + 2:i + 4])[0]


def jpeg_size(d):
    if d[:2] != b'\xff\xd8':
        return None
    i = 2
    while i + 9 < len(d):
        marker, skip = jpeg_segment(d, i)
        if marker in JPEG_FRAME:
            height, width = struct.unpack('>HH', d[i + 5:i + 9])
            return width, height
        i += skip
    return None


def webp_size(d):
    if d[:4] != b'RIFF' or d[8:12] != b'WEBP':
        return None
    kind = d[12:16]
    if kind == b'VP8 ':
        width, height = struct.unpack('<HH', d[26:30])
        return width & 0x3FFF, height & 0x3FFF
    if kind == b'VP8L':
        bits = struct.unpack('<I', d[21:25])[0]
        return (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1
    if kind == b'VP8X':
        return 1 + int.from_bytes(d[24:27], 'little'), 1 + int.from_bytes(d[27:30], 'little')
    return None


def read_size(reader, data):
    try:
        size = reader(data)
    except (struct.error, IndexError):
        return None
    return size if size and min(size) > 0 else None


def image_size(data):
    """(w, h) from the image header, or None."""
    sizes = (read_size(reader, data) for reader in (png_size, gif_size, jpeg_size, webp_size))
    return next((s for s in sizes if s), None)


def is_public_http(url):
    parts = urllib.parse.urlparse(url)
    if parts.scheme not in ('http', 'https') or not parts.hostname:
        return False
    try:
        return ipaddress.ip_address(parts.hostname).is_global
    except ValueError:
        return parts.hostname != 'localhost'


def data_uri_size(url):
    try:
        return image_size(base64.b64decode(url.split(',', 1)[1] + '==')) or 'unknown format'
    except Exception as e:  # malformed data URI
        return f'bad data uri: {e}'


def remote_size(url):
    if not is_public_http(url):
        return 'not a public http(s) url'
    try:
        request = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(request, timeout=15) as response:
            return image_size(response.read(HEAD_BYTES)) or 'unknown format'
    except Exception as e:  # network errors are expected for old emails
        return f'{type(e).__name__}: {e}'


def fetch_size(url):
    """(w, h), or a failure reason string."""
    return data_uri_size(url) if url.startswith('data:') else remote_size(url)


def slots(text):
    """Image URLs in document order: (span, url, from_img_tag)."""
    found = [(m.span(2), m.group(2), True) for m in IMG.finditer(text)]
    found += [(m.span(2), m.group(2), False) for m in URL.finditer(text)]
    return sorted(found, key=lambda s: s[0][0])


def original_html(path):
    message = email.message_from_bytes(path.read_bytes(), policy=email.policy.default)
    body = message.get_body(preferencelist=('html',))
    return body.get_content() if body else None


def needs_size(fixture_url, from_img):
    """Placeholders are resized (CID ones already carry real sizes); other img srcs get a placeholder."""
    hit = PLACEHOLDER.match(fixture_url)
    return hit.group(1) != 'cid' if hit else from_img


def fetch_all(urls):
    with concurrent.futures.ThreadPoolExecutor(8) as pool:
        return dict(zip(urls, pool.map(fetch_size, urls)))


def placeholder_url(size, fixture_url):
    hit = PLACEHOLDER.match(fixture_url)
    return f'https://fixture.invalid/img/{size[0]}x{size[1]}{hit.group(4) if hit else ""}'


def plan_edits(before, after, sizes):
    """(edits, kept, failed) for slots paired by position."""
    edits, kept, failed = [], 0, []
    for (_, url, _), (span, fixture_url, _) in zip(before, after):
        size = sizes.get(url)
        if size is None:
            kept += 1
        elif isinstance(size, str):
            failed.append(f'{urllib.parse.urlparse(url).hostname}: {size}')
        else:
            edits.append((span, placeholder_url(size, fixture_url)))
    return edits, kept, failed


def apply_edits(text, edits):
    for (start, end), value in sorted(edits, reverse=True):
        text = text[:start] + value + text[end:]
    return text


def convert(eml, fixture):
    """One report line; rewrites the fixture when the slots line up."""
    name = fixture.name[:-8]
    original = original_html(eml)
    text = gzip.decompress(fixture.read_bytes()).decode('utf-8')
    if original is None:
        return f'{name:<8} skipped: no text/html part'
    before, after = slots(original), slots(text)
    if len(before) != len(after):
        return f'{name:<8} skipped: count mismatch {len(before)}/{len(after)}'
    wanted = [url for (_, url, _), (_, fx, from_img) in zip(before, after) if needs_size(fx, from_img)]
    edits, kept, failed = plan_edits(before, after, fetch_all(list(dict.fromkeys(wanted))))
    if edits:
        fixture.write_bytes(gzip.compress(apply_edits(text, edits).encode('utf-8'), compresslevel=9, mtime=0))
    notes = '; '.join(sorted(set(failed))[:3])
    return f'{name:<8}{len(after):>6}{len(edits):>9}{kept:>6}{len(failed):>8}  {notes}'


def fixture_for(eml, fixtures):
    """The eml_N.html.gz fixture of an original named `...-N.eml`, if both are usable."""
    number = re.search(r'-(\d+)\.eml$', eml.name)
    if not number or eml.stat().st_size < 100:
        return None
    fixture = fixtures / f'eml_{number.group(1)}.html.gz'
    return fixture if fixture.exists() else None


def matching_pairs(originals, fixtures):
    for eml in sorted(originals.glob('*.eml')):
        fixture = fixture_for(eml, fixtures)
        if fixture:
            yield eml, fixture


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--originals', required=True, type=Path, help='folder of original .eml files')
    parser.add_argument('--fixtures', required=True, type=Path, help='folder of eml_N.html.gz fixtures')
    parser.add_argument('--fetch', action='store_true', help='allow contacting the original image servers')
    args = parser.parse_args()
    if not args.fetch:
        sys.exit('refusing to run without --fetch: images are fetched from the original senders')
    print(f'{"email":<8}{"slots":>6}{"updated":>9}{"kept":>6}{"failed":>8}  note')
    for eml, fixture in matching_pairs(args.originals, args.fixtures):
        print(convert(eml, fixture))


if __name__ == '__main__':
    main()
