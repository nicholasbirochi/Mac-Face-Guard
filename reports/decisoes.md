# Decisões — 14/10/2026

## Aplicativo próprio com APIs Apple

Implementação nativa SwiftUI, AVFoundation, Vision, CryptoKit, Security, LocalAuthentication e ServiceManagement. Sem frameworks/pesos externos ou APIs pagas. Os forks de desbloqueio consultados armazenam ou inserem a senha; esse mecanismo não faz parte do escopo.

## Cadastro experimental disponível; autorização recusada

O kit não fornece modelo facial nem detector de ataques licenciado e avaliado. Feature prints do Vision permitem cadastrar descritores e medir semelhança visual, mas não verificam identidade. A UI os identifica corretamente e o adaptador envia `identityMatched: false` e `livenessPassed: false` ao DecisionEngine. Não se atribuiu um limiar arbitrário de segurança.

## Dados locais separados do código público

O usuário autorizou explicitamente repositório público e excluiu os dados faciais. Todo cadastro e chave ficam fora do projeto e do OneDrive. Código da criptografia é público; vetor, arquivo cifrado e chave são privados. Touch ID controla cadastro, leitura e exclusão. A política da chave usa biometria atual do dispositivo.

## Inicialização

O usuário solicitou explicitamente inicialização do aplicativo no Mac. Usa-se SMAppService para o app do usuário, sem helper privilegiado, LaunchDaemon ou acesso automático à câmera.

## Alternativas futuras

Modelo facial/PAD com licença verificável e medições locais consentidas; iPhone com autenticação nativa e desafio assinado seria estudo independente. Nenhuma dessas alternativas foi implementada.
