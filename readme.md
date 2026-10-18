# MacFaceGuard

Experimento nativo de captura facial local para macOS. O foco atual é cadastrar vetores de um modelo facial com consentimento e protegê-los no aparelho; o projeto ainda não autentica identidade nem desbloqueia o Mac.

![Ilustração da interface do MacFaceGuard, com câmera desligada e cadastro inicial](docs/images/interface.svg)

*Ilustração representativa da interface implementada, sem imagens ou dados pessoais; não é captura de tela.*

## Estado real: v0.1.9 experimental

O app alinha o rosto por cinco pontos dos landmarks do Vision e extrai um vetor de 512 dimensões com o **EdgeFace XS** convertido localmente para Core ML. O cadastro guarda três vetores criptografados, presos ao hash do modelo e ao pré-processamento; a comparação mostra a similaridade do cosseno apenas como informação. Na comparação, o anti-fraude passivo **MiniFASNet** (Apache-2.0), também convertido localmente, estima se o quadro parece foto, tela ou máscara; o resultado é informativo, com limiar não calibrado e sem teste com ataques reais. Não há limiar de identidade calibrado nem taxa de erro medida. A decisão de autenticação permanece bloqueada, mesmo com similaridade alta.

Não desbloqueia o macOS, não substitui Touch ID, senha ou FileVault e não solicita nem guarda a senha do Mac. Uma webcam RGB não oferece as garantias do Face ID. Veja [o estado e a validação](reports/STATUS_FINAL.md) e a [proposta de modelo facial e avaliação](reports/modelos-e-validacao.md).

> **Situação atual:** a 0.1.9 instalada acrescenta o anti-fraude MiniFASNet à comparação: suspeita de foto/tela/máscara aparece como "Possível fraude detectada" e a autenticação continua bloqueada em qualquer caso. O cadastro não usa o anti-fraude. A 0.1.8 levou o anel de giro do cadastro para uma ilha no entalhe da câmera. A 0.1.6 confirmou assinatura, proteção do Chaves e integridade do modelo (`--self-check-model`, com imagem sintética). Cadastros anteriores (v1, feature prints do Vision) não são reaproveitados: a comparação pede um novo cadastro. Calibração e ensaio do PAD (APCER/BPCER), limiar de identidade, ensaio com pessoas e desbloqueio do macOS continuam pendentes. O cadastro do proprietário não foi decifrado pelo desenvolvedor.

## O que ocorre ao bloquear ou reiniciar o Mac

O aplicativo não autentica a tela de bloqueio nem substitui a senha/Touch ID. A abertura automática inicia o app depois de entrar no macOS; a câmera permanece desligada. Cadastro criptografado e comparação informativa são operações do próprio app. O adaptador real continua recusando autenticação porque não há modelo facial ou PAD validado; o MiniFASNet só informa.

## Barra de menus

O MacFaceGuard fica no ícone de rosto na barra superior do macOS, sem ícone no Dock. Clique nele e escolha **Abrir MacFaceGuard** para cadastrar ou comparar. Fechar a janela mantém o ícone disponível; **Sair** encerra o app. Reiniciar não habilita desbloqueio facial.

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

Os testes cobrem política de recusa (inclusive com similaridade alta e sem PAD), cifra/decifra, nonce aleatório, chave incorreta, adulteração, truncamento, cadastro v2 com modelo, hash, dimensão ou pré-processamento incompatíveis, alinhamento por cinco pontos, normalização de vetores, digest do pacote do modelo e limites de pose. Usam somente dados sintéticos. Fora do OneDrive, `swift test` simples também funciona; dentro dele, `--scratch-path` evita a falha de assinatura do pacote de testes por metadados da pasta sincronizada. Não substituem ensaios humanos, teste de câmera/Touch ID, avaliação de ataques ou auditoria independente. Não há métricas FMR/FNMR/APCER/BPCER publicadas porque não foram medidas.

As especificações originais do kit em `docs/` descrevem etapas futuras. O escopo implementado e os bloqueios estão em `reports/STATUS_FINAL.md`, e o mapa do código em [.ai/PROJECT_MAP.md](.ai/PROJECT_MAP.md).

## Remover

Em **Privacidade**, exclua o cadastro com Touch ID e desative a abertura no login. Encerre o app e remova sua cópia de `~/Applications`. Apagar apenas o aplicativo ou o repositório não exclui o cadastro nem a chave. Se a biometria do sistema foi redefinida e impede a exclusão pelo app, apague o item `com.macfaceguard.local.template-key.v1` no aplicativo Chaves e o arquivo privado acima, sem remover outros itens.

## Fontes

- [AVFoundation: autorização da câmera](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media)
- [Vision: landmarks faciais](https://developer.apple.com/documentation/vision/vndetectfacelandmarksrequest)
- [Core ML: MLModel](https://developer.apple.com/documentation/coreml/mlmodel)
- [EdgeFace: código e checkpoints dos autores (BSD-3-Clause)](https://github.com/otroshi/edgeface)
- [Silent-Face-Anti-Spoofing / MiniFASNet (Apache-2.0)](https://github.com/minivision-ai/Silent-Face-Anti-Spoofing)
- [CryptoKit: AES-GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm)
- [LocalAuthentication: LAContext](https://developer.apple.com/documentation/localauthentication/lacontext)
- [ServiceManagement: SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Avaliação das referências open source](reports/avaliacao-open-source.md)

Licença MIT para o código deste projeto. Frameworks Apple seguem seus próprios termos. Nenhum peso de terceiros é incluído: os modelos EdgeFace e MiniFASNet são convertidos localmente e ficam fora do Git e do app.

## Licença

Código e documentação autorais sob [MIT](license).
