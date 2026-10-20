# Glance (fork verde)

- Fork do Glance (MIT, © 2026 Jonathan Zhou). Mantenha `LICENSE`, `THIRD_PARTY_NOTICES.md` e o crédito no README.
- Leia o README antes de alterar. A seção "O que mudou" lista as proteções; nenhuma pode ser removida ou afrouxada.
- Recusa por padrão: sem sessão aberta, tela bloqueada (conferida antes de ler e de digitar), rosto acima do limiar e
  anti-fraude aprovado, nada é digitado. Falta de modelo nunca autoriza acesso.
- Chave só no Chaves de proteção de dados, `.biometryCurrentSet`, `ThisDeviceOnly`, nunca sincronizada. Cada uso de
  AES-GCM leva o rótulo da sua finalidade (`SecureCredentialManager.Purpose`).
- Senha do Mac: conferida no diretório local antes de guardar, zerada após o uso, nunca em log, Git, chat ou serviço remoto.
- Dados faciais, arquivos cifrados, chaves, capturas e logs privados nunca entram no Git ou em serviços remotos.
- Não altere loginwindow, PAM, FileVault, TCC ou AuthorizationDB. Sem atualizador remoto (Sparkle saiu de propósito).
- Câmera só com ação, consentimento e permissão; encerre ao sair, suspender e expirar a sessão.
- Não baixe pesos nem acrescente dependências sem autorização. O ArcFace é só para pesquisa não comercial.
- Valide com o build Release e `swift tools/crypto_selftest.swift`. Mudou cifragem ou digitação, acrescente casos ali.
