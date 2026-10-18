# Arquitetura proposta

## Desenho de alto nível

```text
MacFaceGuardApp (SwiftUI, onboarding, privacidade, estados)
    |
    v
Application Orchestrator ───────────────> Audit Events locais (sem PII)
    |          |             |
    v          v             v
Capture      Face Analysis    Presentation Attack Detection
(AVFoundation)  (Vision/CoreML)  (CoreML/temporal)
    \          |              /
     \         v             /
      ------> DecisionEngine <------ SecurityPolicy
                |
                v
        Resultado de DEMO (nunca loginwindow)

EnrollmentUseCase -> EncryptedTemplateRepository -> CryptoKit/Keychain
                                  |
                    Touch ID / LocalAuthentication (controle de acesso)
```

## Domínio

- `DecisionEngine`: entrada de evidências validadas; saída `demoAuthorized` ou recusa. Sem APIs do SO, sem gatilho de desbloqueio; dependências unidirecionais.
- `EnrollmentService`: captura consentida, controle de uma face, múltiplas poses, qualidade, versão de modelo, política de retenção e exclusão.
- `FaceEmbeddingProvider`: abstração de modelo e checksum; nunca aceitar retorno sem origem e integridade.
- `PresentationAttackDetector`: resultado `pass / fail / inconclusive` com versão de detector e janela temporal; `inconclusive` sempre bloqueia.
- `TemplateVault`: blobs AES-GCM + chave de dispositivo; exclusão reversível? Não: excluir metadados e chave conforme desenho documentado, com atenção a backups.
- `AuthorizationBoundary`: inicialmente **DEMO ONLY**; nenhuma API de desbloqueio do macOS.

## Privacidade

- Frames somente em memória; sem screenshots, sem persistência de vídeo/fotos por padrão.
- Proteção dos embeddings, metadados mínimos e chave no Keychain; nenhuma foto como "senha".
- Permissões AVFoundation explícitas; interface exibe câmera ativa e permite encerrá-la.
- Cadastro, redefinição, exportação e exclusão exigem presença/autorização legítima do proprietário.
- Logs sem frames, IDs biométricos, vetor de embedding, senha ou nome da conta macOS.

## Implementado em 0.1.6 (18/10/2026)

- `FaceAlignment` (núcleo, puro): cinco pontos dos landmarks do Vision → similaridade ArcFace para 112×112, com recusa para pontos inválidos, reflexão, escala fora de (0,07; 1,5), inclinação ≥ 45° e ajuste ruim (RMS ≥ 8 px); warp bilinear BGRA com preenchimento zero.
- `FaceEmbeddingProvider` concreto: `EdgeFaceExtractor` (app) carrega o EdgeFace XS convertido localmente, confere o SHA-256 do pacote numa cópia privada, confere a interface (112×112 → 512) e roda só na CPU. Sem modelo ou com hash divergente, nada é comparado.
- `TemplateVault`: cadastro v2 (`enrollment-v2.aesgcm`, AAD própria) com três embeddings normalizados, id do modelo e versão do pré-processamento; o v1 só é apagado depois de o v2 ser gravado e relido.
- `DecisionEngine` continua recusando sempre: sem PAD, a similaridade é apenas informativa.

## Implementado em 0.1.7 (18/10/2026)

- `RotationRing` (núcleo, puro): 60 traços; cada deslocamento do nariz em relação à posição frontal (horizontal por `noseOffset`, vertical por `FaceGeometry.noseLift`) acende o traço daquela direção e dois vizinhos. O anel conclui com 95% aceso e aponta o maior trecho apagado para orientar o próximo movimento.
- Cadastro no estilo do iPhone: prévia circular espelhada, traços cinza que ficam verdes, direção seguinte em texto. A frente é a primeira amostra; as duas laterais exigem cabeça nivelada. Só grava com anel completo e três vetores.
- Análise a cada 0,2 s no cadastro. Os limiares (0,07 para o anel, 0,2 para "nivelado") ainda não foram calibrados com pessoas.
- O anel é guia de UX, não prova de vida: um vídeo gravado também o preenche. `DecisionEngine` continua recusando sempre.

## Testabilidade

`starter/` já traz uma lógica pura de decisão em Swift Package Manager para validar política fail-closed; não contém webcam, reconhecimento nem autorização do sistema. Os adaptadores reais serão feitos no macOS e testados lá. Manter testes de mocks distintos de testes com câmera/modelos reais.

## Notas de performance

Reduzir resolução da inferência (não da câmera anunciada) conforme requisitos de modelo; medir latência real, bateria e uso da Neural Engine, aquecimento e falsos negativos. Não supor que 12 MP aumenta automaticamente segurança biométrica.
