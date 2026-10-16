# Mapa do projeto — MacFaceGuard v0.1.4

Fonte: código local, atualizado em 16/10/2026. Mapa manual; não é saída Graphify.

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
