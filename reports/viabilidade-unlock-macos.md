# Desbloqueio do macOS — estudo, sem implementação

O aplicativo implementa cadastro e comparação experimental em espaço de usuário. SMAppService abre o app após login; não é autenticação do sistema. LocalAuthentication pede ao sistema confirmação biométrica para operações do próprio app.

- [Authorization Plug-ins](https://developer.apple.com/documentation/security/authorization_plug-ins): mecanismos específicos de autorização; não constituem suporte genérico para substituir Touch ID ou autenticar FileVault com webcam. Não foram instalados.
- Glance, FaceUnlock e Peek descrevem armazenamento/injeção de senha usando Accessibility. Esse caminho não foi incorporado.
- O login do macOS, loginwindow, PAM, AuthorizationDB, FileVault, SIP e Gatekeeper não são alterados.
- Um possível companheiro iPhone com Face ID e desafio assinado verificaria uma identidade no protocolo do app; não concede desbloqueio nativo do Mac por si. Não implementado.

Qualquer laboratório futuro de autenticação do sistema exige escopo independente, autorização específica, máquina de teste, recuperação e reversão. O app atual nunca concede acesso, nem mesmo de demonstração, sem backend facial/PAD validado.
