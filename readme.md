<h1 align="center">
  <br>
  <img src="glance/Assets.xcassets/appicon.imageset/appicon.png" alt="Glance" width="150">
  <br>
  Glance
  <br>
</h1>

<h3 align="center">Desbloqueio facial no Mac, com a carinha verde e cifragem reforçada</h3>

<p align="center">
  <a href="license"><img src="https://img.shields.io/badge/licença-MIT-black.svg" alt="Licença MIT"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-black.svg" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-black.svg" alt="Swift">
</p>

Fork pessoal do [Glance](https://github.com/jonnyoo/glance), de Jonathan Zhou (MIT). O app continua igual: a ilha no
entalhe, as animações, o cadastro em nove direções e o anti-fraude. Mudam duas coisas: o azul virou verde, e o
armazenamento da senha e dos rostos ficou mais fechado.

O app instalado se chama **Glance**, como o original. Para não se misturar com ele, usa identificador e pasta de
dados próprios (`com.nicholasbirochi.glanceverde` e `GlanceVerde`).

![Ícone e animações do Glance](docs/glance-verde-icones.png)

---

> [!WARNING]
> **Não é tão seguro quanto Face ID ou Touch ID.** A câmera do MacBook vê uma imagem 2D, sem sensor de profundidade.
> O anti-fraude recusa com boa confiança foto impressa e foto no celular, mas **não recusa de forma confiável um vídeo
> seu**. O macOS não tem API para um app autorizar o login, então o desbloqueio funciona digitando a sua senha na tela de
> bloqueio. É conveniência, não reforço de segurança. A cifragem mais forte protege a senha guardada. Ela não torna o
> reconhecimento facial mais difícil de enganar.

## O que mudou em relação ao Glance

### Cifragem e Chaves

| Glance original | Este fork |
|---|---|
| Chave AES-256 com `userPresence`: Touch ID **ou a senha do Mac** abria a chave. | Chave no **Chaves de proteção de dados**, com `.biometryCurrentSet` e `WhenUnlockedThisDeviceOnly`. Só uma digital cadastrada hoje abre a chave, sem recurso à senha do Mac. |
| Itens sem atributo explícito de sincronização. | Todo item tem `kSecAttrSynchronizable = false` e acessibilidade `…ThisDeviceOnly`. Nada vai para o iCloud nem abre num backup restaurado em outro Mac. |
| AES-GCM sem dados autenticados adicionais. | AES-GCM com **rótulo autenticado por finalidade** (`glanceverde.password.v1` e `glanceverde.faces.v1`). O arquivo de rostos não abre como senha nem o contrário. |
| A senha digitada no cadastro era guardada sem conferência. | A senha é **conferida no diretório local** (`/Local/Default`, o mesmo da tela de bloqueio) antes de ser cifrada. Senha errada não é guardada, então nunca vira tentativas falhas na tela de bloqueio. |
| Os bytes da chave ficavam na memória até serem liberados. | Os bytes lidos e a chave nova são **zerados** logo após o uso. A chave lida precisa ter exatamente 32 bytes. |
| Rostos em `Application Support/Glance`, com permissões padrão. | Pasta `Application Support/GlanceVerde` com permissão **0700** e arquivo com **0600**, fora do backup do Time Machine. Ao apagar, o arquivo é sobrescrito com bytes aleatórios antes de ser removido. |

### Leitura e digitação da senha

- A senha decifrada vai para um buffer UTF-16 de tamanho fixo, que é **zerado** ao terminar, mesmo em caso de erro. No
  original, ela passava por uma `String`, que não dá para apagar.
- UTF-8 inválido e senha vazia são recusados, em vez de digitar lixo.
- A senha só é digitada se a tela **estiver de fato bloqueada**. Isso é conferido **de novo** logo antes de ler e
  digitar, e **antes de cada lote de teclas**. Se a tela desbloquear no meio, o resto não é digitado e ⌘ é solto.

### Senha, Touch ID e rosto ao mesmo tempo

- Na tela de bloqueio, você pode digitar a senha ou usar o Touch ID enquanto o rosto é procurado. **Quem responder
  primeiro vence**:
  - uma tecla física depois do início da procura cede a vez à digitação: a câmera desliga, a ilha recolhe e a nova
    tentativa automática é cancelada;
  - a tela desbloqueada por outro meio encerra a procura;
  - o rosto só digita a senha depois de conferir, no mesmo instante, que ninguém respondeu antes.
- Sob entrada segura o app não lê as teclas: só o estado HID diz há quanto tempo houve a última tecla. Nenhuma tecla é
  lida, guardada ou injetada por causa da corrida, e nenhuma proteção muda: ela só faz o rosto desistir mais cedo.
- Depois de ceder a vez, a barra de espaço faz parte da senha e não religa a câmera; passe o mouse no entalhe para
  tentar o rosto de novo. A ilha nunca vira janela-chave fora do cadastro, para não tirar o foco do campo de senha.
- Limites: um lote de até 20 caracteres pode sair inteiro se o desbloqueio acontecer no meio dele; se o rosto vencer,
  a senha que estava pela metade no campo é apagada antes de digitar.

### Assinatura e atualizações

- **Sem Sparkle**: nenhum atualizador remoto troca o app. Atualizar exige recompilar.
- Build Release **sem `get-task-allow`**, para que um depurador não se anexe ao processo e leia a chave da memória.
- Hardened runtime ligado. O identificador é próprio (`com.nicholasbirochi.glanceverde`) e não se mistura com o Glance.

### Visual

Passaram de azul `#3499FF` para verde `#33D666`:

- o ícone do app (Icon Composer, `glance/glanceicon.icon`), que agora entra de fato no build: o original apontava
  para `GlanceIcon`, nome que não batia com o arquivo, e o app ficava sem ícone;
- as animações (`*.mp4`) e a imagem estática;
- os SVGs;
- o gradiente do ícone;
- a cor de destaque;
- o tema do cadastro.

O ícone, o logo (`glance-logo.svg` e `appicon.png`) e a animação de abertura (`logoanimation.mp4`, a carinha que
olha para um lado e para o outro) perderam o cartão branco: agora são **só a carinha verde sobre fundo preto**, como a
ilha na hora da facial. Nos demais pontos, o branco continua branco.

Na tela de bloqueio, o painel da facial (estilo original, com entalhe) tem **a mesma largura da ilha do
Alcove**: a largura do entalhe, −2 pt, mais uma aba de 35 pt de cada lado (268 pt num entalhe de
200 pt). Antes ele tinha 220 pt, e as abas do Alcove apareciam dos dois lados. Os valores ficam em
`NotchGeometry.swift`, na seção "Match the Alcove island".

Em telas **sem entalhe** (monitor externo), o Glance original mostrava uma pílula solta, um quadrado arredondado
afastado do topo. Agora ele desenha um **entalhe simulado**, colado na borda de cima, como o entalhe simulado do
Alcove (`forceSimulatedNotch`). Medido pela Acessibilidade num monitor externo: 72 × 31 pt, o que dá, com o −2 pt,
o corpo de 70 pt entre as abas de 35 × 29 pt do Alcove. Na facial, o painel abre a partir desse entalhe, com
220 pt de largura. A pílula continua disponível: desligue **Notch on displays without one** em Settings → General.
Os valores ficam em `NotchGeometry.swift`, na seção "Simulated notch".

## Antes de usar

- **Não arme este Glance junto com o MacFaceGuard ou com o Glance original.** Dois apps digitando senha na mesma tela
  de bloqueio podem se atropelar.
- **Cadastrar ou apagar uma digital invalida a chave.** Isso é de propósito (`.biometryCurrentSet`). Nada é apagado
  sozinho. O app avisa, e você remove a senha guardada na aba Senha para limpar tudo e recadastrar.
- **Os dados do Glance original não migram.** Cadastre o rosto e a senha de novo.
- O build é assinado com certificado de desenvolvimento. O Gatekeeper o recusa se ele vier baixado da internet, mas
  compilado localmente ele abre normalmente. O build sai como `Glance.app`; instale em `~/Applications`.

## Permissões

| Permissão | Para quê |
|---|---|
| **Câmera** | Ver seu rosto. Os quadros ficam só na memória e nunca são gravados. |
| **Acessibilidade** | Digitar a senha na tela de bloqueio. |
| **Touch ID** | Abrir a chave que cifra os rostos e a senha. |

## Como funciona

1. No primeiro uso, o cadastro captura seu rosto enquanto você gira a cabeça em nove direções. Cada quadro vira um vetor
   de 512 números (ArcFace), e a imagem é descartada.
2. Você digita a senha do Mac uma vez. Ela é conferida no diretório local e cifrada com a chave presa ao Touch ID.
3. Quando o Mac bloqueia ou acorda, a ilha aparece no entalhe e procura um rosto.
4. A senha só é digitada se **todas** estas condições valerem:
   - a sessão foi aberta com Touch ID;
   - a tela está realmente bloqueada (conferido duas vezes);
   - o rosto passa do limiar;
   - o anti-fraude aprova;
   - a Acessibilidade está concedida.

A sessão do Touch ID se fecha sozinha depois do tempo ocioso escolhido em Ajustes. O Face Lab, para testar o
reconhecimento e o anti-fraude, abre em **Ajustes → Sobre** com cinco cliques no ícone.

## Compilar

Requisitos: macOS 15 ou mais novo e Xcode 26 ou mais novo.

```bash
xcodebuild -project glance.xcodeproj -scheme glance -configuration Release -allowProvisioningUpdates DEVELOPMENT_TEAM=<seu time> build
```

Para testar as regras de cifragem e de digitação (sem câmera, sem Chaves e sem Touch ID):

```bash
swift tools/crypto_selftest.swift
```

Para testar a corrida entre senha, Touch ID e rosto:

```bash
swiftc -o /tmp/unlock_race_selftest glance/UnlockRace.swift tools/unlock_race_selftest.swift && /tmp/unlock_race_selftest
```

Para testar o entalhe simulado e a pílula em telas sem entalhe:

```bash
swiftc -o /tmp/notch_geometry_selftest glance/NotchOverlay/NotchGeometry.swift glance/NotchOverlay/NotchPanelStyle.swift glance/Onboarding/OnboardingMetrics.swift tools/notch_geometry_selftest.swift && /tmp/notch_geometry_selftest
```

O teste do anti-fraude está descrito no cabeçalho de `tools/liveness_selftest.swift`.

## Créditos e licença

- Projeto original: **[Glance](https://github.com/jonnyoo/glance)** © 2026 Jonathan Zhou, licença [MIT](license).
- Modelo ArcFace: [InsightFace](https://github.com/deepinsight/insightface). Os pesos são **somente para pesquisa não
  comercial**; veja [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- Física da janela do entalhe: [The Boring Notch](https://github.com/TheBoredTeam/boring.notch).

Este fork não é afiliado ao Glance nem ao seu autor.
