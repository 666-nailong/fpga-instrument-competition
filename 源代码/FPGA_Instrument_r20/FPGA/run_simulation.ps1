# Icarus Verilog 14.x; run in a fresh output directory. -CompileOnly compiles all18 benches.
param([Parameter(Mandatory)][string]$OutDir,[string]$PackageDir=$PSScriptRoot,[switch]$CompileOnly,
      [string]$IcarusBin='')
$iverilog=if($IcarusBin){Join-Path $IcarusBin 'iverilog.exe'}else{'iverilog'}
$vvp=if($IcarusBin){Join-Path $IcarusBin 'vvp.exe'}else{'vvp'}
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutDir){throw 'Choose a fresh output directory'}
New-Item -ItemType Directory -Path $OutDir | Out-Null
Copy-Item -LiteralPath (Join-Path $PackageDir src) -Destination $OutDir -Recurse
Copy-Item -Path "$PackageDir/sim/tests/*.v","$PackageDir/sim/models/*.v" -Destination $OutDir
Copy-Item -Path "$OutDir/src/*.mem","$OutDir/src/*.vh" -Destination $OutDir
& python "$PackageDir/sim/models/prepare_sim.py" $OutDir
if($LASTEXITCODE -ne 0){throw 'LUT extraction failed'}
Push-Location $OutDir
try {
 foreach($name in @('inputs32','ads1115','pressure_scale32','pressure_scan32','natural_suite','resampler_wait','fx32','system32','s3005_nkro','s3005_host','s3005_rom','status32','selftest32','polyphony32','quality32','modal_piano32','folded_sine','pedal_status32')){
  $sources=switch($name){
   inputs32 {@('src/usb_note_decoder32.v','src/pressure_sustain32.v')}
   ads1115 {@('src/ads1115_reader.v')}
   pressure_scale32 {@('src/pressure_sustain32.v')}
   pressure_scan32 {@('src/pressure_sustain32.v')}
   natural_suite {@('src/pipe_organ.v','src/plucked_guitar.v','src/organ_room.v','src/sine_rom.v')}
   resampler_wait {@('src/natural_native_to_48k.v','src/resample_coefficient_decoder.v','src/pcm5102_i2s.v','native_to_48k.v')}
   fx32 {@('src/audio_fx32.v')}
   s3005_nkro {@('src/usb_note_decoder32.v')}
   s3005_host {@('src/usb_hid_host.v','src/usb_hid_host_rom.v','src/usb_note_decoder32.v')}
   s3005_rom {@('src/usb_hid_host.v','src/usb_hid_host_rom.v')}
   status32 {@('src/keyboard_status_uart.v')}
   selftest32 {@('src/polyphony_selftest32.v')}
   quality32 {@('src/voice_engine_32.v','src/sine_rom.v','voice_engine_32_r16.v')}
   modal_piano32 {@('src/modal_piano32.v')}
   folded_sine {@('src/bowed_wave.v')}
   pedal_status32 {@('src/keyboard_status_uart.v')}
   polyphony32 {@(Get-ChildItem src -Filter '*.v' | Where-Object Name -notin @('usb_pll_50_to_60.v','usb_hid_host.v','bowed_conflict_decode.v') | ForEach-Object FullName);'usb_pll_model.v';'usb_host_model.v';'conflict_decode_model.v'}
   system32 {@(Get-ChildItem src -Filter '*.v' | Where-Object Name -notin @('usb_pll_50_to_60.v','usb_hid_host.v','bowed_conflict_decode.v') | ForEach-Object FullName);'usb_pll_model.v';'usb_host_model.v';'conflict_decode_model.v'}
  }
  & $iverilog -g2012 -I src -s "tb_$name" -o "$name.vvp" "tb_$name.v" $sources
  if($LASTEXITCODE -ne 0){throw "Compile failed: $name"}
  if(!$CompileOnly){
   & $vvp -i "$name.vvp" | Tee-Object "$name.txt"
   if($LASTEXITCODE -ne 0){throw "Test failed: $name"}
  }
 }
}finally{Pop-Location}
