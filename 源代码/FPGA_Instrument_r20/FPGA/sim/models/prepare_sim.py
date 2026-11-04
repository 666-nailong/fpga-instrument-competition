"""Extract the exact frozen LUT truth tables for functional simulation."""
import argparse
import hashlib
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('out', type=Path)
args = parser.parse_args()
source = args.out / 'src/bowed_conflict_decode.v'
text = source.read_text(encoding='utf-8')
truth = [None]*768
for line in text.splitlines():
    if not line.startswith('LUT6 '):
        continue
    init = re.search(r"INIT\(64'h([0-9a-fA-F]+)\)", line)[1]
    bit = int(re.search(r'patterns\[(\d+)\]', line)[1])
    addresses = [int(n) for n in re.findall(r'\.I\d\(codes\[(\d+)\]\)', line)]
    assert addresses == list(range(bit//24*6, bit//24*6+6))
    assert truth[bit] is None
    truth[bit] = int(init, 16)
assert all(t is not None for t in truth)
(args.out / 'conflict_lut_truth.mem').write_text(''.join(f'{t:016x}\n' for t in truth), encoding='ascii')
summary = dict(source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
               lut_count=768, addresses_per_lut=64, exact_bits=768*64,
               simulation='zero-delay LUT INIT table, not a timing model')
(args.out / 'LUT_TRUTH_AUDIT.json').write_text(json.dumps(summary, indent=2)+'\n', encoding='utf-8')
print('PASS: extracted 768 exact LUT6 tables / 49152 bits and checked all input address mappings')
