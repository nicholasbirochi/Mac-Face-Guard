# Estado real — MacFaceGuard 0.1.4

Data: atualizado em 16/10/2026. Aplicativo experimental instalado. A interface confirmou **cadastro local encontrado**; o desenvolvedor não decifrou nem inspecionou o cadastro facial.

## Implementado

- SwiftUI em português: cadastro, comparação visual, privacidade e barra de menus.
- Câmera integrada sob consentimento, quadros em memória, uma face, captura frontal e dois lados.
- Guia sobre a câmera, feedback de luz/posição, etapas, som e barra de movimento nariz/olhos relativa à posição frontal. Deduplicação conservadora de caixas quase idênticas preserva rostos distintos.
- Cadastro exige Touch ID; o Chaves é verificado antes da câmera.
- AES-256-GCM com AAD e nonce aleatório. Chave em data protection keychain, sem sincronização, WhenUnlockedThisDeviceOnly e biometryCurrentSet.
- Arquivo privado fora do projeto/OneDrive/Git, permissões 0700/0600, escrita atômica e exclusão de backup solicitada.
- Cadastro até 90 segundos, comparação até 45; câmera para ao sair, fechar ou suspender.
- Projeto Xcode com assinatura Apple Development, perfil e grupo próprio do Chaves; hardened runtime e autorização de câmera. Os certificados e perfis não entram no Git.
- Abertura após login via SMAppService; câmera desligada. Não altera autenticação do sistema.

## Evidências

- macOS 26.7, Xcode 27.0, Swift 6.4, arm64.
- Starter: 10 testes aprovados; demo simulada recusou vivacidade ausente. Projeto: 22 testes, zero falhas.
- Projeto Xcode compilou com assinatura desativada para verificar código durante a preparação.
- Usuário executou o instalador local depois de a revisão automática ficar indisponível por limite. A verificação posterior encontrou v0.1.3 e perfil de provisionamento no app instalado.
- `codesign --verify --deep --strict ~/Applications/MacFaceGuard.app`: aprovado fora do sandbox do agente. A checagem dentro desse sandbox retornou CSSMERR_TP_NOT_TRUSTED; o resultado completo fora dele resolveu a dúvida.
- `MacFaceGuard --self-check-keychain`: retornou KEYCHAIN_PROTECTION_VERIFIED. Criação de item sintético protegido, recusa de leitura sem biometria e remoção verificadas. Nenhuma chave real foi lida.
- Estado textual da UI: v0.1.3, cadastro protegido/local encontrado, câmera desligada. Nenhuma imagem da câmera foi capturada pelo desenvolvedor.

## Correções relevantes

O retorno do Touch ID antes da recuperação de foco foi tratado com sessão pendente até ativar a janela. A leitura lateral passou a aceitar qualquer lado, depois exigir o oposto; nariz/olhos e barra de progresso melhoraram o guia.

O erro -34018 ocorreu ao salvar a chave sem autorização na assinatura. A v0.1.3 usa explicitamente o backend de proteção de dados, projeto Xcode com provisionamento e preflight antes da câmera. Um diagnóstico sintético mostrou que o backend legado podia permitir leitura sem autenticação; ele não foi usado como fallback.

Pastas sincronizadas acrescentaram FinderInfo ao pacote. O build assina em diretório temporário e entrega ZIP; instalação fora da sincronização.

## Não implementado / não validado

- Reconhecimento de identidade facial e detector PAD: não implementados. Feature prints são descritores genéricos de imagem.
- Autorização: sempre recusada pelo adaptador real, com identityMatched e livenessPassed falsos. O caso de sucesso dos testes do núcleo é sintético.
- Desbloqueio do macOS, tela de bloqueio e FileVault: não implementados. Abrir no login significa depois de entrar no sistema.
- Decifra/comparação/exclusão do cadastro real com o proprietário: não verificadas nesta inspeção; a presença do arquivo foi confirmada pela UI.
- Métricas FMR/FNMR/APCER/BPCER, resistência a foto/tela/vídeo, desempenho e bateria: não medidos.
- Reinício do Mac para validar relançamento: não realizado.
- Modelo externo, conversão Core ML, iPhone e notarização: não implementados.

## Riscos e remoção

Descritores faciais continuam sensíveis. Um processo comprometido no usuário/SO fica fora da garantia; a exclusão de backup não controla ferramentas que a ignoram. Alterar as digitais pode invalidar a chave. Exclua cadastro e chave e desative a inicialização em Privacidade antes de remover o app.

Próxima etapa técnica: modelo facial e PAD com licença/proveniência e avaliação consentida, antes de qualquer autorização.

## Ajuste 0.1.4 — 16/10/2026

Solicitado pelo usuário: operar pela barra superior sem ícone no Dock. `scripts/Info.plist` define `LSUIElement=true`; o menu existente abre a janela e permite sair. Versão 0.1.4, build 5. Compilação Xcode Release com assinatura Apple aprovada e instalada. O Info.plist do pacote confirmou LSUIElement, versão e build; codesign --verify --deep --strict e a autoverificação sintética do Chaves passaram. A UI confirmou v0.1.4, cadastro local encontrado e câmera desligada; NSRunningApplication confirmou activationPolicy=accessory, sem Dock. As evidências históricas acima descrevem a versão 0.1.3. Cadastro, criptografia e autenticação não foram alterados.

## Ajuste 0.1.5 — 17/10/2026

`CaptureFrameGate` recusa quadros futuros, atrasados, repetidos ou fora de ordem; não é PAD. Versão 0.1.5, build 6, instalada com perfil de provisionamento renovado (o perfil gratuito vale 7 dias e precisa ser renovado no Xcode).

## Ajuste 0.1.6 — 18/10/2026

Integração do EdgeFace XS (ver `reports/modelos-e-validacao.md`): alinhamento por cinco pontos, extração Core ML com digest SHA-256 do pacote conferido antes de carregar, cadastro v2 preso a modelo/hash/dimensão/pré-processamento e similaridade apenas informativa. O v1 não é decifrado; a comparação pede novo cadastro. Versão 0.1.6, build 7.

Evidências: `swift test --scratch-path "$HOME/Library/Caches/MacFaceGuard/swift-build"` com 48 testes sintéticos e zero falhas; build Release assinado; `codesign --verify --deep --strict` aprovado no app instalado; `--self-check-keychain` retornou KEYCHAIN_PROTECTION_VERIFIED e `--self-check-model` retornou MODEL_VERIFIED com dimensão 512, usando imagem sintética. O cadastro do proprietário não foi lido nem decifrado.

## Ajuste 0.1.7 — 18/10/2026

Cadastro com anel de giro (`RotationRing`): prévia circular espelhada, 60 traços que passam de cinza a verde conforme a direção do nariz e indicação da próxima direção. Grava só com anel em 95% e três vetores (frente e dois lados nivelados). O anel não é PAD: um vídeo reproduzido também o completa. Limiares não calibrados com pessoas. Versão 0.1.7, build 8.

Evidências: 54 testes sintéticos com zero falhas (6 do anel); build Release assinado e `codesign --verify --deep --strict` aprovado no app instalado. O cadastro real pela câmera depende do usuário; o cadastro não foi lido nem decifrado.

## Ajuste 0.1.8 — 18/10/2026

Cadastro na ilha (`NotchIsland`): o anel de giro, a prévia circular e as amostras aparecem num painel preto que se abre a partir do entalhe da câmera, no estilo da Dynamic Island, e recolhe com confirmação ao salvar. A janela principal só aponta para a ilha. Sem mudança em decisão, PAD ou desbloqueio. Versão 0.1.8, build 9.

Evidências: 54 testes sintéticos com zero falhas; build Release assinado, `--self-check-keychain` aprovado e `codesign --verify --deep --strict` aprovado no app instalado. A aparência da ilha com a câmera real depende do cadastro feito pelo usuário e não foi conferida pelo desenvolvedor.

## Ajuste 0.1.9 — 18/10/2026

Anti-fraude passivo na comparação: MiniFASNetV2 + MiniFASNetV1SE (Silent-Face-Anti-Spoofing, Apache-2.0, revisão `b6d5f04a`), baixados com autorização do usuário, conferidos por SHA-256 e convertidos localmente em `MiniFASNetPAD.mlpackage` (fora do Git e do app). `PresentationAttackDetector` confere o digest, compila numa pasta privada e roda só em CPU. Cada quadro da comparação é avaliado; suspeita aparece como "Possível fraude detectada", e o resultado continua recusado em qualquer caso. Sem desbloqueio do Mac, sem senha armazenada ou injetada. O cadastro não usa PAD. Versão 0.1.9, build 10.

Evidências: conversão com erro máximo de 5,96e-07 contra o PyTorch em 8 entradas sintéticas; 64 testes sintéticos com zero falhas (10 novos de recorte, reamostragem, leitura fail-closed e sequência); build Release assinado e instalado, `--self-check-model` com `MODEL_VERIFIED` e `PAD_VERIFIED` (só imagem sintética), `--self-check-keychain` e `codesign --verify --deep --strict` aprovados. Desempenho contra fotos, telas, vídeos e máscaras reais não foi medido; a comparação com a câmera depende do usuário.

Continua não implementado/validado: calibração e ensaio do PAD com ataques reais, limiar de identidade calibrado, FMR/FNMR/APCER/BPCER, paridade do alinhamento com a referência em OpenCV, cadastro e comparação reais pela câmera (dependem do usuário) e desbloqueio do macOS. A decisão continua sempre recusada.
