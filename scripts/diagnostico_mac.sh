#!/usr/bin/env bash
set -u

echo "MacFaceGuard - diagnóstico somente leitura"
echo "========================================"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Ambiente atual não é macOS. Execute este script no MacBook alvo."
  exit 0
fi
printf 'SO: '; sw_vers -productName 2>/dev/null || true
printf 'Versão: '; sw_vers -productVersion 2>/dev/null || true
printf 'Arquitetura: '; uname -m
printf 'Hardware: '; system_profiler SPHardwareDataType 2>/dev/null | grep -E 'Chip:|Memory:' | sed 's/^ *//' || true
printf '\nXcode: '; command -v xcodebuild || true
xcodebuild -version 2>&1 || true
printf '\nDeveloper dir: '; xcode-select -p 2>&1 || true
printf '\nSwift: '; swift --version 2>&1 || true
printf '\nGit: '; git --version 2>&1 || true
printf '\nHomebrew: '; if command -v brew >/dev/null 2>&1; then brew --version | head -n 1; else echo 'não encontrado (não é obrigatório no MVP)'; fi
printf '\nCâmeras detectadas (modelo, sem imagens):\n'
system_profiler SPCameraDataType 2>/dev/null | grep -E 'Camera|FaceTime|Model ID:' | head -n 15 || true
printf '\nNenhuma instalação, elevação de privilégio ou alteração de configuração foi realizada.\n'
