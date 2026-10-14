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

## Testabilidade

`starter/` já traz uma lógica pura de decisão em Swift Package Manager para validar política fail-closed; não contém webcam, reconhecimento nem autorização do sistema. Os adaptadores reais serão feitos no macOS e testados lá. Manter testes de mocks distintos de testes com câmera/modelos reais.

## Notas de performance

Reduzir resolução da inferência (não da câmera anunciada) conforme requisitos de modelo; medir latência real, bateria e uso da Neural Engine, aquecimento e falsos negativos. Não supor que 12 MP aumenta automaticamente segurança biométrica.
