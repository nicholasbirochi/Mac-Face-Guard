# Estado real — MacFaceGuard 0.1.1

Data: 14/10/2026. Protótipo experimental nativo para desenvolvimento local.

## Implementado e compilado

- UI SwiftUI em português: cadastro, comparação, privacidade e barra de menus. Interface aberta e verificada via acessibilidade e imagem, com câmera desligada.
- Captura AVFoundation da câmera integrada sob consentimento e permissão, quadros somente em memória, uma face, qualidade mínima e pose via Vision.
- Cadastro em três posições com Touch ID; guarda somente descritores genéricos de imagem, revisão e versão.
- Comparação de distância de feature prints, explicitamente experimental, sem limiar de identidade.
- AES-256-GCM com AAD, nonce aleatório e verificação de integridade. Chave no Chaves com biometria atual, sem sincronização e restrição ao dispositivo.
- Cofre fora do projeto/OneDrive/Git, diretório 0700, arquivo 0600 e exclusão de backup solicitada. Exclusão de chave e cadastro exige Touch ID.
- Cadastro limitado a 90 segundos e comparação a 45 segundos, descarte de referências ao parar, suspensão/saída/fechamento desligam a câmera.
- Registro de abertura no login via SMAppService confirmado por `LOGIN_ITEM_ENABLED`, câmera desligada na inicialização.
- `.app` release arm64 instalado em `~/Applications/MacFaceGuard.app`, assinatura ad hoc verificada no destino; sem notarização/Developer ID. Entrega em ZIP para evitar metadados de sincronização no pacote.

## Validação executada

- Starter: `swift test`, 10 testes aprovados; `swift run MacFaceGuardDemo` recusou evidência simulada sem vivacidade.
- Projeto: `swift test --disable-sandbox --scratch-path /private/tmp/macfaceguard-build`, 19 testes, zero falhas. Caches de módulos temporários definidos devido ao sandbox de desenvolvimento.
- `bash scripts/build-app.sh`: build release local e `codesign --verify --deep --strict` aprovados.
- `sw_vers`: macOS 26.7; `xcodebuild -version`: Xcode 27.0; `swift --version`: Swift 6.4.
- Interface inicial inspecionada com a câmera desligada, consentimento e botão de cadastro visíveis. Versão corrigida reaberta na pasta Applications.
- A pasta sincronizada acrescentou FinderInfo ao pacote `.app`; a distribuição final usa ZIP criado a partir de pacote assinado em diretório temporário. A instalação copia diretamente desse pacote e passou no `codesign --verify --deep --strict`.

## Correção de integração

O primeiro teste humano revelou uma condição de corrida: o retorno do Touch ID podia ocorrer antes de a janela recuperar foco. A versão corrigida mantém a sessão autorizada pendente e só inicia a câmera quando o aplicativo fica ativo. Dois testes de regressão cobrem a devolução tardia de foco, cancelamento e eventos de sessões antigas. A mensagem de erro prematura foi removida.

## Guia de captura v0.1.1

Instruções, setas, etapas e feedback de luz/posição aparecem sobre a câmera. A primeira virada aceita qualquer lado; a última exige sinal oposto, evitando ambiguidade da imagem espelhada. Qualidade mínima experimental diferencia frente de lateral, pois Vision penaliza rotação. Viradas pequenas são aceitas, há confirmação sonora e 90 segundos para o cadastro. Dois testes adicionais cobrem direções espelhadas e qualidade lateral, incluindo valores inválidos. Ajustes são de captura experimental, não validação biométrica.

## Não validado / não implementado

- Cadastro/decifra/exclusão com o Touch ID e rosto do proprietário dependem da interação dele; não foi automatizada nem observada a câmera. Testes unitários validam a cifra, não a integração real do Chaves/Touch ID.
- Modelo de reconhecimento facial e detector PAD: não implementados. Feature prints da Apple não verificam identidade.
- Prova de vida, FAR/FRR, FMR/FNMR, APCER/BPCER, desempenho/bateria e resistência a fotos, telas, vídeo/deepfake: não medidos.
- Autorização: sempre recusada pelo adaptador real (`identityMatched: false`, `livenessPassed: false`). O sucesso do teste unitário do núcleo é somente cenário sintético.
- Desbloqueio do sistema: não implementado. Nenhuma senha coletada, nenhum mecanismo de login modificado.
- API de modelo externo/conversão Core ML e autenticação via iPhone: não implementadas. Nenhum peso ou binário externo baixado.
- Reinício completo do Mac para testar relançamento no login: não realizado.

## Riscos e remoção

Descritores faciais continuam sensíveis mesmo sem fotos. Proteção depende do macOS/Chaves; um processo comprometido no mesmo usuário ou no SO fica fora da garantia. A marcação de exclusão de backup não controla ferramentas que a ignoram. Recompilações com assinatura ad hoc podem pedir novas permissões. Alterar as digitais pode invalidar a chave.

Remova cadastro/chave e desative a inicialização na tela Privacidade antes de excluir o aplicativo. Instruções de recuperação manual estão no README.

Próxima etapa técnica: modelo facial e PAD com proveniência e licença verificadas, seguido de avaliação consentida e métricas; até lá, não autorizar acesso.
