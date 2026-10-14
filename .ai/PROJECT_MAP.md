# Mapa do projeto — MacFaceGuard v0.1.1

Fonte: código local, 14/10/2026. Mapa manual; não é saída Graphify.

- `Package.swift`: Swift 6, macOS 15+, sem dependências externas.
- `Sources/MacFaceGuardCore/DecisionEngine.swift`: política pura de recusa por padrão; mantida do starter.
- `Sources/MacFaceGuardCore/Enrollment.swift`: registro versionado, validação, AES-GCM com AAD e três posições de captura.
- `Sources/MacFaceGuardApp/CameraPipeline.swift`: AVFoundation em fila serial, câmera integrada, Vision para uma face/qualidade/pose e feature prints de imagem; quadros em memória, 2 análises/s.
- `Sources/MacFaceGuardApp/TemplateVault.swift`: cifra local fora do projeto, chave no Chaves com biometria, permissões de arquivo e exclusão.
- `Sources/MacFaceGuardApp/AppModel.swift`: consentimento → Touch ID → câmera → três descritores → cofre. Comparação calcula distância, sem autorização. Expiração e limpeza ao sair.
- `Sources/MacFaceGuardApp/MacFaceGuardApp.swift`: SwiftUI, preview, cadastro/comparação/privacidade, barra de menus e login item pelo SMAppService.
- `scripts/build-app.sh` e `Info.plist`: pacote `.app`, mensagem de permissão de câmera, assinatura ad hoc.
- `Tests/`: decisões e cifra, registros inválidos, poses e recusa experimental.

Riscos e limites: feature print não verifica identidade; não há PAD, métricas humanas ou desbloqueio do sistema; biometria real depende de interação humana. Nenhum vetor, chave, foto ou vídeo pertence ao repositório.
