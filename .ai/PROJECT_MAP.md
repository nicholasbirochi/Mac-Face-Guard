# Mapa do projeto — MacFaceGuard v0.1.8

Fonte: código local, atualizado em 18/10/2026. Mapa manual; não é saída Graphify.

- `Package.swift`: Swift 6, macOS 15+, sem dependências externas.
- `Sources/MacFaceGuardCore/DecisionEngine.swift`: política pura de recusa por padrão; mantida do starter.
- `Sources/MacFaceGuardCore/Enrollment.swift`: registro versionado, validação, AES-GCM com AAD e três posições de captura.
- `Sources/MacFaceGuardApp/CameraPipeline.swift`: AVFoundation em fila serial, câmera integrada, Vision para uma face/qualidade/pose e feature prints de imagem; quadros em memória, 2 análises/s.
- `Sources/MacFaceGuardApp/TemplateVault.swift`: cifra local fora do projeto, chave no Chaves com biometria, permissões de arquivo e exclusão.
- `Sources/MacFaceGuardApp/AppModel.swift`: consentimento → Touch ID → câmera → três descritores → cofre. Comparação calcula distância, sem autorização. Expiração e limpeza ao sair.
- `Sources/MacFaceGuardApp/MacFaceGuardApp.swift`: SwiftUI, preview, cadastro/comparação/privacidade, barra de menus e login item pelo SMAppService.
- `scripts/build-app.sh` e `Info.plist`: pacote `.app`, mensagem de permissão de câmera, assinatura Apple com perfil de provisionamento.
- `Tests/`: decisões e cifra, registros inválidos, poses e recusa experimental.

Riscos e limites: feature print não verifica identidade; não há PAD, métricas humanas ou desbloqueio do sistema; biometria real depende de interação humana. Nenhum vetor, chave, foto ou vídeo pertence ao repositório.

- `FaceGeometry.swift`: movimento nariz/olhos e deduplicação conservadora de caixas; sem persistência de pontos faciais.

- Correção 0.1.3: `MacFaceGuard.xcodeproj`, `project.yml`, `scripts/MacFaceGuard.entitlements`; assinatura Apple/profile e preflight do Chaves antes da câmera. Instalada; assinatura e autoverificação do Chaves aprovadas. Desbloqueio do sistema e modelo facial/PAD não implementados; consultar STATUS_FINAL.

- v0.1.4: `LSUIElement` mantém o app na barra de menus, sem Dock; abrir a janela pelo menu existente.

- v0.1.5: `CaptureFrameGate` em `Enrollment.swift` valida relógio monotônico, frescor e ordem dos quadros; `AppModel` reinicia o filtro por sessão. Não é PAD.
- `reports/modelos-e-validacao.md`: comparação de modelos, proposta EdgeFace XS, migração e protocolo FMR/FNMR/APCER/BPCER. Download aprovado e conversão Core ML validada só com entradas sintéticas (`scripts/convert-edgeface.py`); integrada no app na 0.1.6.

- v0.1.6: `FaceAlignment.swift` (cinco pontos → similaridade → 112×112 BGRA), `FaceEmbedding.swift` (normalização L2, cosseno, descritor do modelo e digest do pacote), `EdgeFaceExtractor.swift` (cópia privada, hash, compilação e interface Core ML; `--self-check-model`). `Enrollment.swift` ganhou `EnrollmentV2`/`EnrollmentCipherV2`; `TemplateVault` grava `enrollment-v2.aesgcm` e só remove o v1 após reler o v2. `CameraPipeline` usa landmarks em vez de feature prints. Similaridade informativa; decisão sempre recusada sem PAD. Pesos fora do Git.
- v0.1.7: `RotationRing.swift` (anel de 60 traços, cobertura e maior lacuna) e `FaceGeometry.noseLift`. `CameraPipeline` envia giro, altura do nariz e espelhamento a cada 0,2 s; `AppModel.traceRing` acende o anel e `ringPrompt` indica a direção; `MacFaceGuardApp` desenha prévia circular espelhada com traços verdes. Guia de UX, não PAD.
- v0.1.8: `NotchIsland.swift` (`NSPanel` não ativador no entalhe, `NotchShape`, `IslandView` com anel, prévia, amostras e cancelar). `AppModel.foregrounded` abre a ilha no cadastro; `stop` e o salvamento a recolhem. `RingTicks`, `CameraPreview` e `ringGreen` deixaram de ser privados para a ilha reutilizá-los.
