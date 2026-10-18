# MacFaceGuard

Experimento nativo de captura facial local para macOS. O foco atual é cadastrar vetores de um modelo facial com consentimento e protegê-los no aparelho; a 0.2.0 acrescenta um desbloqueio facial experimental da tela bloqueada, no estilo do [Glance](https://github.com/jonnyoo/glance), com limiar não calibrado.

![Ilustração da interface do MacFaceGuard, com câmera desligada e cadastro inicial](docs/images/interface.svg)

*Ilustração representativa da interface implementada, sem imagens ou dados pessoais; não é captura de tela.*

## Estado real: v0.2.0 experimental

O app alinha o rosto por cinco pontos dos landmarks do Vision e extrai um vetor de 512 dimensões com o **EdgeFace XS** convertido localmente para Core ML. O cadastro guarda três vetores criptografados, presos ao hash do modelo e ao pré-processamento; a comparação mostra a similaridade do cosseno apenas como informação. Na comparação, o anti-fraude passivo **MiniFASNet** (Apache-2.0), também convertido localmente, estima se o quadro parece foto, tela ou máscara; o resultado é informativo, com limiar não calibrado e sem teste com ataques reais. Não há limiar de identidade calibrado nem taxa de erro medida. A comparação continua apenas informativa; só a aba **Desbloqueio**, armada pelo proprietário, pode agir.

O desbloqueio facial digita a senha guardada na tela de bloqueio; não altera loginwindow, PAM, FileVault, TCC nem AuthorizationDB e não substitui a senha depois de reiniciar (FileVault). Uma webcam RGB não oferece as garantias do Face ID. Veja [o estado e a validação](reports/STATUS_FINAL.md) e a [proposta de modelo facial e avaliação](reports/modelos-e-validacao.md).

> **Situação atual:** a 0.2.0 instalada acrescenta o desbloqueio facial experimental (abaixo); compilação, assinatura e testes sintéticos passaram, mas o desbloqueio real ainda não foi ensaiado pelo proprietário. A 0.1.9 acrescentou o anti-fraude MiniFASNet à comparação: suspeita de foto/tela/máscara aparece como "Possível fraude detectada" e a autenticação continua bloqueada em qualquer caso. O cadastro não usa o anti-fraude. A 0.1.8 levou o anel de giro do cadastro para uma ilha no entalhe da câmera. A 0.1.6 confirmou assinatura, proteção do Chaves e integridade do modelo (`--self-check-model`, com imagem sintética). Cadastros anteriores (v1, feature prints do Vision) não são reaproveitados: a comparação pede um novo cadastro. Calibração e ensaio do PAD (APCER/BPCER), limiar de identidade, ensaio com pessoas e desbloqueio do macOS continuam pendentes. O cadastro do proprietário não foi decifrado pelo desenvolvedor.

## O que ocorre ao bloquear ou reiniciar o Mac

Sem armar, nada muda: o app não toca a tela de bloqueio e a câmera fica desligada. A abertura automática inicia o app depois de entrar no macOS.

**Desbloqueio facial (0.2.0, experimental, opcional).** Inspirado no Glance (MIT; `KeystrokeInjector` e `LockMonitor` adaptados, aviso em [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)). Na aba **Desbloqueio**:

1. Guarde a senha do Mac. Ela é conferida no diretório local (senha errada não é guardada), cifrada com AES-GCM e posta no Chaves; a chave exige Touch ID (`biometryCurrentSet`).
2. Permita o MacFaceGuard em **Ajustes do Sistema → Privacidade e Segurança → Acessibilidade**, necessário para digitar.
3. Clique em **Armar com Touch ID**. A chave fica só na memória até desarmar ou encerrar o app.

Com o desbloqueio armado, bloquear não liga a câmera. Ao despertar a tela ou parar o descanso de tela com o Mac bloqueado, a câmera liga por até 15 s. A senha só é digitada (por eventos de teclado, seguida de Return) quando há exatamente um rosto, semelhança acima do limiar (padrão 0,50, ajustável de 0,35 a 0,80) em 2 quadros seguidos e o MiniFASNet indica rosto real em 3 seguidos; o bloqueio é relido logo antes de digitar. Suspeita de fraude, rosto errado por 2 s, mais de um rosto ou tempo esgotado desligam a câmera, com até 3 tentativas por bloqueio.

**Risco:** uma webcam 2D é bem mais fraca que o Face ID. Foto, tela ou vídeo do seu rosto podem enganar o reconhecimento e o anti-fraude, cujos limiares não foram calibrados. Não use onde alguém possa ter interesse em entrar no seu Mac. Depois de reiniciar, o FileVault continua pedindo a senha.

## Barra de menus

O MacFaceGuard fica no ícone de rosto na barra superior do macOS, sem ícone no Dock. Clique nele e escolha **Abrir MacFaceGuard** para cadastrar ou comparar. Fechar a janela mantém o ícone disponível; **Sair** encerra o app. O desbloqueio facial só funciona enquanto o app está aberto e armado; depois de reiniciar, é preciso armá-lo de novo.

## Primeiro cadastro

1. Abra `MacFaceGuard.app` no Mac.
2. Em **Cadastro**, marque o consentimento e clique **Cadastrar meu rosto**.
3. Confirme com Touch ID e autorize a câmera no diálogo do macOS.
4. Olhe de frente para o círculo e depois mova a cabeça devagar, desenhando um círculo com o nariz, até todos os traços ficarem verdes; o texto abaixo indica a próxima direção. Termine virando para cada lado com a cabeça nivelada. O cadastro expira em 90 segundos, com confirmação sonora por amostra. O anel só orienta o movimento: não detecta foto ou vídeo.
5. O app confirma quando os três vetores faciais forem criptografados. A câmera desliga. Sem o modelo local íntegro, o cadastro não começa.

Em **Comparação**, confirme o consentimento e o Touch ID para observar a similaridade (de −1 a 1; maior indica vetores mais próximos). O número não valida identidade nem autoriza acesso. Em **Privacidade**, é possível excluir cadastro e chave, abrir a configuração da câmera e controlar a abertura no login.

## Privacidade

- Fotos e vídeos não são gravados. Os quadros são processados em memória.
- O único cadastro persistente fica em `~/Library/Application Support/MacFaceGuard/private/enrollment-v2.aesgcm`, fora do projeto, do OneDrive e do Git. Um cadastro antigo (`enrollment.aesgcm`) só é removido depois que o novo foi gravado e conferido, ou ao excluir o cadastro.
- Diretório `0700`, arquivo `0600`, escrita atômica e marcação de exclusão de backup. Outros programas que ignoram essa marcação podem copiar o arquivo.
- Chave AES de 256 bits no Chaves, sem sincronização, com `WhenUnlockedThisDeviceOnly` e controle `biometryCurrentSet`. Alterar o conjunto de digitais pode invalidar o acesso: exclua o cadastro e cadastre novamente.
- O repositório contém apenas código, testes, documentação e recursos ilustrativos. Não há telemetria, contas, servidor, SDK de terceiros ou código de envio de dados.
- A inicialização automática abre o app com a câmera **desligada**. Câmera somente após uma ação sua; encerra ao sair do app, fechar a janela, suspender o Mac ou atingir 90 segundos no cadastro / 45 na comparação.

## Compilar

Requer macOS 15+, Xcode/Swift 6+, conta Apple de desenvolvimento configurada no Xcode, certificado/perfil válido e Touch ID. Os controles biométricos do Chaves precisam de autorização na assinatura; uma assinatura ad hoc não serve para esse fluxo. Não há pacotes Swift externos.

O modelo não é distribuído. O app procura `~/Library/Caches/MacFaceGuard/edgeface-build/EdgeFaceXS.mlpackage`, gerado localmente por `scripts/convert-edgeface.py` a partir do checkpoint oficial fixado em [reports/modelos-e-validacao.md](reports/modelos-e-validacao.md), e recusa um pacote com hash diferente. Sem ele, cadastro e comparação ficam bloqueados. A comparação também exige `~/Library/Caches/MacFaceGuard/minifasnet-build/MiniFASNetPAD.mlpackage`, gerado por `scripts/convert-minifasnet.py` a partir da revisão fixada do Silent-Face-Anti-Spoofing; ausente ou com hash diferente, a comparação não começa.

```bash
swift test --scratch-path "$HOME/Library/Caches/MacFaceGuard/swift-build"
bash scripts/build-app.sh
unzip -q dist/MacFaceGuard.zip -d /tmp/MacFaceGuard-run
open /tmp/MacFaceGuard-run/MacFaceGuard.app
```

O script compila pelo projeto Xcode com assinatura Apple Development e perfil de provisionamento, verifica a proteção do Chaves com um item sintético e só então gera `dist/MacFaceGuard.zip`. O ZIP evita que metadados de pastas sincronizadas invalidem o pacote. Extraia fora do OneDrive/iCloud. Não inclui Developer ID nem notarização. A compilação usa a arquitetura do Mac atual. A política de confiança do macOS continua ativa.

Para instalar para o usuário atual, copie o `.app` para `~/Applications`. Ative **Abrir MacFaceGuard ao entrar no macOS** em **Privacidade** se desejar. A versão é de desenvolvimento, sem notarização. O perfil e os certificados locais não pertencem ao Git; o script reutiliza a identidade Apple já instalada.

## Testes e limites

Os testes cobrem política de recusa (inclusive com similaridade alta e sem PAD), cifra/decifra, nonce aleatório, chave incorreta, adulteração, truncamento, cadastro v2 com modelo, hash, dimensão ou pré-processamento incompatíveis, alinhamento por cinco pontos, normalização de vetores, digest do pacote do modelo e limites de pose. Usam somente dados sintéticos. Fora do OneDrive, `swift test` simples também funciona; dentro dele, `--scratch-path` evita a falha de assinatura do pacote de testes por metadados da pasta sincronizada. Não substituem ensaios humanos, teste de câmera/Touch ID, avaliação de ataques ou auditoria independente. O `UnlockGate` tem testes próprios (tela desbloqueada, fraude, rosto errado, vários rostos, sequências interrompidas, tempo e limiar). Não há métricas FMR/FNMR/APCER/BPCER publicadas porque não foram medidas.

As especificações originais do kit em `docs/` descrevem etapas futuras. O escopo implementado e os bloqueios estão em `reports/STATUS_FINAL.md`, e o mapa do código em [.ai/PROJECT_MAP.md](.ai/PROJECT_MAP.md).

## Remover

Em **Desbloqueio**, desarme e clique em **Apagar senha**; retire o app de Acessibilidade em Ajustes do Sistema. Em **Privacidade**, exclua o cadastro com Touch ID e desative a abertura no login. Encerre o app e remova sua cópia de `~/Applications`. Apagar apenas o aplicativo ou o repositório não exclui o cadastro nem a chave. Se a biometria do sistema foi redefinida e impede a exclusão pelo app, apague os itens `com.macfaceguard.local.template-key.v1` e `com.macfaceguard.local.unlock` (contas `password` e `session-key`) no aplicativo Chaves e o arquivo privado acima, sem remover outros itens.

## Fontes

- [AVFoundation: autorização da câmera](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media)
- [Vision: landmarks faciais](https://developer.apple.com/documentation/vision/vndetectfacelandmarksrequest)
- [Core ML: MLModel](https://developer.apple.com/documentation/coreml/mlmodel)
- [EdgeFace: código e checkpoints dos autores (BSD-3-Clause)](https://github.com/otroshi/edgeface)
- [Silent-Face-Anti-Spoofing / MiniFASNet (Apache-2.0)](https://github.com/minivision-ai/Silent-Face-Anti-Spoofing)
- [CryptoKit: AES-GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm)
- [LocalAuthentication: LAContext](https://developer.apple.com/documentation/localauthentication/lacontext)
- [ServiceManagement: SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Glance: desbloqueio facial para macOS (MIT)](https://github.com/jonnyoo/glance) — aviso em [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
- [Avaliação das referências open source](reports/avaliacao-open-source.md)

Licença MIT para o código deste projeto. Frameworks Apple seguem seus próprios termos. Nenhum peso de terceiros é incluído: os modelos EdgeFace e MiniFASNet são convertidos localmente e ficam fora do Git e do app.

## Licença

Código e documentação autorais sob [MIT](license).
