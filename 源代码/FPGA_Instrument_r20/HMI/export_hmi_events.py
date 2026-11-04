"""Export editable event code from a native HMI; preserve the HMI unchanged."""
import argparse
import re
import struct
from pathlib import Path

U32 = struct.Struct('<I')


def crc(data, word=False, seed=0xffffffff):
    result = seed
    step = 4 if word else 1
    assert len(data) % step == 0
    for position in range(0, len(data), step):
        result ^= int.from_bytes(data[position:position+step], 'little')
        for _ in range(32):
            result = ((result << 1) ^ (0x04c11db7 if result & 0x80000000 else 0)) & 0xffffffff
    return result


def strings(blob):
    result, position = [], 0
    while position < len(blob):
        size = U32.unpack_from(blob, position)[0]
        position += 4
        assert position+size <= len(blob)
        result.append(blob[position:position+size])
        position += size
    return result


def export(source, output):
    data = source.read_bytes()
    count = U32.unpack_from(data)[0]
    end = 4+28*count
    assert data[:end+4] == data[524288:524288+end+4]
    assert U32.unpack_from(data, end)[0] == crc(data[:end]+b'ADEC', True)
    output.mkdir(parents=True, exist_ok=False)
    pages, events, lines = 0, 0, 0
    for index in range(count):
        name, offset, size, _ = struct.unpack_from('<16sIII', data, 4+28*index)
        name = name.split(b'\0')[0].decode('ascii')
        assert offset+size <= len(data)
        payload = data[offset:offset+size]
        if name == 'Program.s':
            (output/'Program.s').write_text(payload.decode('gb2312'), encoding='utf-8')
        if not re.fullmatch(r'[0-3]\.pa', name):
            continue
        check = crc(payload[4:])
        for begin, finish in ((4, 8), (12, 16), (20, 21), (21, 22)):
            check = crc(payload[begin:finish], seed=check)
        assert U32.unpack_from(payload)[0] == check
        page = output/('page'+name[:-3])
        page.mkdir()
        pages += 1
        for obj in range(U32.unpack_from(payload, 12)[0]):
            start, length, _ = struct.unpack_from('<III', payload, 56+12*obj)
            values = strings(payload[56+start:56+start+length])
            objname = next(v[16:].decode('ascii') for v in values if v[:16].split(b'\0')[0] == b'objname')
            assert re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', objname)
            for i, value in enumerate(values):
                match = re.fullmatch(rb'(codes[A-Za-z0-9_]*)-([0-9]+)', value)
                if not match or int(match[2]) == 0:
                    continue
                length = int(match[2])
                assert i+1+length <= len(values)
                code = '\n'.join(v.decode('gb2312') for v in values[i+1:i+1+length])+'\n'
                (page/(objname+'_'+match[1].decode('ascii')+'.txt')).write_text(code, encoding='utf-8')
                events += 1
                lines += length
    assert pages == 4 and events > 100 and (output/'Program.s').is_file()
    return dict(pages=pages, nonempty_events=events, event_lines=lines)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    print(export(args.source, args.output))
