#!/bin/zsh
# Recolore para verde as animações de desbloqueio do Glance (MIT, © 2026 Jonathan Zhou).
# Uso: scripts/tint-glance-assets.sh <pasta Resources do Glance>
# Os originais são azul sobre preto; o mixer leva a luminância para o verde do anel (0.20, 0.84, 0.40).
set -euo pipefail
src="${1:?informe a pasta Resources do Glance}"
out="${0:A:h}/../Resources/Unlock"
mkdir -p "$out"
mix="colorchannelmixer=rr=0:rg=0:rb=0.20:gr=0:gg=0:gb=0.84:br=0:bg=0:bb=0.40"
for name in unlockanimation unsuccessfulunlockanimation; do
  ffmpeg -nostdin -loglevel error -y -i "$src/$name.mp4" -vf "$mix" \
    -c:v libx264 -pix_fmt yuv420p -crf 18 -movflags +faststart -an "$out/$name.mp4"
done
ffmpeg -nostdin -loglevel error -y -i "$src/unlockstatic.png" -vf "$mix" "$out/unlockstatic.png"
echo "Assets verdes em $out"
