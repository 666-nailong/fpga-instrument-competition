"""Generate the measured S3005 report mapping and a guarded alternate USB ROM page."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
layout = json.loads((root/'S3005_NKRO_MAP.json').read_text())
keymap = json.loads((root/'KEYMAP.json').read_text())
mapping = layout['mapping']
assert [{k: row[k] for k in ('index', 'key', 'hid_usage', 'midi')} for row in mapping] == keymap
assert {row['report_id'] for row in mapping} == {4, 5}
assert len({(row['report_id'], row['byte'], row['bit']) for row in mapping}) == 32
base = [int(line, 16) for line in (root/'src/usb_hid_host_rom.mem').read_text().split()]
assert hashlib.sha256((root/'src/usb_hid_host_rom.mem').read_text().encode()).hexdigest().upper() == '5BB70D56CBB19AD6789EA7B308952E78DCAD971BEC463B3978650ACF36FE9126'
assert len(base) == 1024


def crc16(data):
    value = 0xFFFF
    for byte in data:
        value ^= byte
        for _ in range(8):
            value = (value >> 1) ^ (0xA001 if value & 1 else 0)
    return value ^ 0xFFFF


def setup_packet(payload):
    checksum = crc16(payload)
    return [n for byte in [0x80, 0xC3, *payload, checksum & 255, checksum >> 8]
            for n in (6, byte & 15, byte >> 4)]


alternate = base.copy()
patches = []
for name, old, new in (
    ('SET_IDLE interface1', [0x21, 0x0A, 0, 0, 0, 0, 0, 0], [0x21, 0x0A, 0, 0, 1, 0, 0, 0]),
    ('GET_REPORT_DESCRIPTOR interface1', [0x81, 6, 0, 0x22, 0, 0, 9, 0], [0x81, 6, 0, 0x22, 1, 0, 9, 0]),
    ('SET_PROTOCOL report interface1', [0x21, 0x0B, 0, 0, 0, 0, 0, 0], [0x21, 0x0B, 1, 0, 1, 0, 0, 0]),
):
    before, after = setup_packet(old), setup_packet(new)
    hits = [i for i in range(len(base)-len(before)+1) if base[i:i+len(before)] == before]
    assert len(hits) == 1, (name, hits)
    offset = hits[0]
    alternate[offset:offset+len(after)] = after
    patches.append(dict(request=name, nibble_offset=offset, payload=new, crc16=crc16(new)))
(root/'src/usb_hid_host_s3005.mem').write_text(''.join(f'{n:x}\n' for n in base+alternate), encoding='ascii')
lines = ['// Generated from Windows HID single-bit probes; run generate_s3005_nkro.py.']
for report in (4, 5):
    rows = [row for row in mapping if row['report_id'] == report]
    mask = sum(1 << row['index'] for row in rows)
    lines += [f"localparam [31:0] S3005_BANK{report}=32'h{mask:08x};",
              f'function [31:0] s3005_bank{report};', 'input [63:0] report;', 'begin', f's3005_bank{report}=0;']
    lines += [f"s3005_bank{report}[{row['index']}]=report[{row['byte']*8+row['bit']}]; // {row['key']}" for row in rows]
    lines += ['end', 'endfunction']
(root/'src/s3005_note_map.vh').write_text('\n'.join(lines)+'\n', encoding='ascii')
print(json.dumps(dict(default_rom_sha256=hashlib.sha256(bytes(base)).hexdigest(), patches=patches), indent=2))
