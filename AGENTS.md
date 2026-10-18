# MacFaceGuard

- Leia `readme.md`, `.ai/PROJECT_MAP.md` e `reports/STATUS_FINAL.md` antes de alterar o projeto.
- Preserve a recusa por padrão. Feature prints não são reconhecimento de identidade; falta de modelo facial/PAD nunca autoriza acesso.
- Dados faciais, arquivos cifrados, chaves, capturas e logs privados nunca entram no Git ou em serviços remotos.
- Não altere loginwindow, PAM, FileVault, TCC ou AuthorizationDB.
- Senha do Mac (autorizada pelo proprietário em 18/10/2026): só cifrada no Chaves, com chave presa ao Touch ID, conferida no diretório local antes de guardar, e digitada por Acessibilidade apenas com o desbloqueio armado, a tela bloqueada, rosto acima do limiar e anti-fraude aprovado. Nunca em log, Git, chat ou serviço remoto.
- Câmera exige ação, consentimento e permissão. Encerre ao sair, suspender e expirar a sessão.
- Use APIs nativas e testes proporcionais. Não baixe pesos nem acrescente dependências sem necessidade e autorização.
