# Fontes e referências verificadas (13/10/2026)

## Fabricante/API

- MacBook Air M5 2026, ficha técnica: https://support.apple.com/pt-br/126320
- Especificações da linha MacBook Air, câmera/Touch ID: https://www.apple.com/br/macbook-air/specs/
- Apple `LocalAuthentication`: https://developer.apple.com/documentation/localauthentication/lacontext
- Apple controle de câmera/permissão: https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media
- Apple Authorization Plug-ins: https://developer.apple.com/documentation/security/extending-authorization-services-with-plug-ins
- Apple Secure Enclave/assinatura P256: https://developer.apple.com/documentation/cryptokit/secureenclave/p256/signing/privatekey
- Apple Keychain com CryptoKit: https://developer.apple.com/documentation/cryptokit/storing-cryptokit-keys-in-the-keychain
- NIST SP 800-63B autenticadores e PAD: https://pages.nist.gov/800-63-4/sp800-63b/authenticators/

## Open source (referências técnicas, não dependências já aprovadas)

- Glance: https://github.com/jonnyoo/glance — MIT conforme repositório, mas revisar dependências/pesos.
- Peek: https://github.com/XIVASSS/peek — fork do Glance, declara reforços anti-spoof; não resolve vídeos com confiança.
- HasBrain FaceUnlock: https://github.com/HasBrain/FaceUnlock — projeto de referência em ArcFace/Core ML, senha armazenada protegida por Keychain/Touch ID; **não importar esse padrão de login**.
- Silent Face Anti Spoofing: https://github.com/minivision-ai/Silent-Face-Anti-Spoofing — Apache-2.0 para repositório (confirmar license e pesos individualmente); verificar manutenção e vulnerabilidades nas dependências legadas.
- InsightFace: https://github.com/deepinsight/insightface — código MIT, modelos pré-treinados oficialmente limitados a pesquisa não comercial, verificar licenciamento antes de distribuir.

## Modelo em uso na 0.1.6 (18/10/2026)

- EdgeFace XS gamma 0.6: https://github.com/otroshi/edgeface — BSD-3-Clause conforme o repositório; revisão `ce86851cfc37979a9cd2558598d0e9bc592cbba3`, arquivo `checkpoints/edgeface_xs_gamma_06.pt` (7.170.425 bytes, SHA-256 `5ae7504cd9aee0a5d52c2115fd2eb66b0985dd1730f40134b5854e0cb658ce16`).
- Conversão local por `scripts/convert-edgeface.py`; pacote `EdgeFaceXS.mlpackage` com digest SHA-256 `036326e60212ab3773a6b3bb2d312655cc4a2707e738c0807bc2341d82f0edee`, conferido pelo app antes de carregar.
- Pesos e pacote convertido ficam em `~/Library/Caches/MacFaceGuard/edgeface-build/`, fora do Git e do `.app`; o MacFaceGuard não os redistribui.

## Avisos de responsabilidade

- A licença do código de uma biblioteca NÃO implica a mesma licença dos pesos de rede neural, datasets e binários distribuídos por terceiros.
- Para qualquer modelo, registrar URL de origem, commit/tag, licença exata, hash SHA256, estrutura de dependências e confirmação de uso pretendido.
- GitHub stars, screenshots, README e autodeclaração de segurança não substituem auditoria nem testes.
- Um fork que diz "mais seguro" não confirma resistência contra vídeo ou deepfakes.
