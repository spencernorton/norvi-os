#!/usr/bin/env python3
"""Fetch verified upstream inputs, or pack and restore them offline."""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import tarfile
import tempfile
from urllib.parse import urlparse
from urllib.request import urlopen

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
LIMIT = 32 * 1024 * 1024


def inputs():
    lock = json.loads((HERE / 'source-inputs.lock.json').read_text())
    if lock.get('version') != 1 or not lock.get('files'):
        raise ValueError('Unsupported or empty source lock')
    entries = {}
    for entry in lock['files']:
        name = entry['path']
        path = PurePosixPath(name)
        if (not path.is_relative_to('desktop/window-glass') or '..' in path.parts or
                str(path) != name or name in entries or urlparse(entry['url']).scheme != 'https' or
                not re.fullmatch(r'[0-9a-f]{64}', entry['sha256'])):
            raise ValueError(f'Invalid source lock entry: {name}')
        entries[name] = entry
    return entries


def digest(file):
    with file.open('rb') as stream:
        result = hashlib.sha256()
        for chunk in iter(lambda: stream.read(128 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def verified_copy(stream, destination, expected):
    checksum = hashlib.sha256()
    length = 0
    with destination.open('wb') as output:
        for block in iter(lambda: stream.read(128 * 1024), b''):
            length += len(block)
            if length > LIMIT:
                raise ValueError('Source input exceeds the supported size')
            checksum.update(block)
            output.write(block)
    if checksum.hexdigest() != expected:
        raise ValueError(f'Upstream digest mismatch: {destination.name}')


def target(name):
    destination = ROOT / name
    if not destination.resolve().is_relative_to(ROOT) or destination.is_symlink():
        raise ValueError(f'Invalid source destination: {name}')
    return destination


def fetch_or_verify(entries, fetch):
    for name, entry in entries.items():
        output = target(name)
        if output.is_file() and digest(output) == entry['sha256']:
            continue
        if not fetch:
            raise ValueError(f'Missing or modified source input: {name}')
        output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=output.parent) as scratch:
            temp = Path(scratch) / output.name
            with urlopen(entry['url'], timeout=90) as response:
                verified_copy(response, temp, entry['sha256'])
            temp.chmod(0o644)
            temp.replace(output)


def pack(entries, output):
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent) as scratch:
        temp = Path(scratch) / 'supplement'
        with temp.open('wb') as stream, gzip.GzipFile(
                filename='', mode='wb', compresslevel=0, mtime=0, fileobj=stream) as compressed:
            with tarfile.open(fileobj=compressed, mode='w', format=tarfile.USTAR_FORMAT) as archive:
                for name in sorted(entries):
                    source = target(name)
                    with source.open('rb') as stream:
                        data = stream.read(LIMIT + 1)
                    if len(data) > LIMIT or hashlib.sha256(data).hexdigest() != entries[name]['sha256']:
                        raise ValueError(f'Missing or modified source input: {name}')
                    member = tarfile.TarInfo(name)
                    member.mode = 0o644
                    member.size = len(data)
                    archive.addfile(member, io.BytesIO(data))
        temp.replace(output)


def unpack(entries, archive):
    with tempfile.TemporaryDirectory(dir=HERE) as scratch:
        pending = {}
        with tarfile.open(archive, mode='r|gz') as bundle:
            for member in bundle:
                if (member.name not in entries or member.name in pending or not member.isfile() or
                        member.size > LIMIT):
                    raise ValueError(f'Unexpected source archive member: {member.name}')
                temp = Path(scratch) / str(len(pending))
                with bundle.extractfile(member) as data:
                    verified_copy(data, temp, entries[member.name]['sha256'])
                pending[member.name] = temp
        if pending.keys() != entries.keys():
            raise ValueError('Incomplete source supplement')
        for name, temp in pending.items():
            output = target(name)
            output.parent.mkdir(parents=True, exist_ok=True)
            temp.chmod(0o644)
            temp.replace(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='operation', required=True)
    for action in ('fetch', 'verify'):
        commands.add_parser(action)
    for action in ('pack', 'unpack'):
        commands.add_parser(action).add_argument('archive', type=Path)
    args = parser.parse_args()
    entries = inputs()
    if args.operation in ('fetch', 'verify'):
        fetch_or_verify(entries, args.operation == 'fetch')
    elif args.operation == 'pack':
        pack(entries, args.archive)
    else:
        unpack(entries, args.archive)


if __name__ == '__main__':
    main()
