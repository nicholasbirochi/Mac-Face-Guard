# Estado real — MacFaceGuard 0.1.3

Data: 14/10/2026. Aplicativo experimental instalado. A interface confirmou **cadastro local encontrado**; o desenvolvedor não decifrou nem inspecionou o cadastro facial.

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
