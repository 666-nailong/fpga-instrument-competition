"""Analytical stiff-string modal parameters; never recorded notes or excitations."""
import argparse,json,math
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out',type=Path,required=True)
args=parser.parse_args();args.out.mkdir(parents=True,exist_ok=True)
fs=50000000/1024
tables=[[] for _ in range(4)]
for note in range(64):
 f0=440*2**((60+note-69)/12)
 for mode in range(16):
  harmonic=mode+1 if mode<12 else mode-11
  stiffness=.00012*2**(note/24)
  frequency=f0*harmonic*math.sqrt((1+stiffness*harmonic**2)/(1+stiffness))
  if mode>=12:frequency*=1.0009
  weight=abs(math.sin(math.pi*harmonic*.135))/harmonic**.85
  gain=round(20500*weight*math.exp(-harmonic/17)*(1 if mode<12 else .30))
  decay=max(11,16-(harmonic-1)//3-note//20)
  increment=round(frequency*2**32/fs) if frequency<fs*.45 else 0
  gain=min(16383,gain) if increment else 0
  tables[mode%4].append((increment<<19)|(gain<<5)|decay)
for lane,table in enumerate(tables):
 (args.out/f'piano_modes_{lane}.mem').write_text(''.join(f'{v:013x}\n' for v in table),encoding='ascii')
(args.out/'piano_sine.mem').write_text(''.join(f'{round(math.sin(2*math.pi*i/1024)*32767)&65535:04x}\n' for i in range(1024)),encoding='ascii')
(args.out/'bowed_sine_quarter.mem').write_text(''.join(f'{round(math.sin(2*math.pi*i/4096)*32767):04x}\n' for i in range(1024)),encoding='ascii')
print('PASS generated64 note parameter rows x16 independent modes and mathematical sine tables')
