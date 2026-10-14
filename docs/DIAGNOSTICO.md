# Diagnóstico técnico — outubro de 2026

## Problema

O usuário quer experiência de desbloqueio facial no MacBook Air M5 com máxima segurança prática. A máquina tem potência de sobra para inferência local com Core ML e Neural Engine, mas capacidade computacional NÃO substitui sensor de profundidade, infravermelho, cadeia de confiança de boot e autenticação de hardware do sistema.

## Fatos verificados

- Apple especifica câmera 12 MP Center Stage, gravação 1080p e Touch ID no MacBook Air M5; NÃO descreve sensor TrueDepth para Face ID.
- `LocalAuthentication` utiliza mecanismos biométricos disponibilizados pelo sistema; não oferece registro de uma webcam RGB como Face ID nativo do macOS.
- Apple documenta Authorization Plug-ins para mecanismos/políticas de autorização. A existência dessa API NÃO demonstra suporte simples para substituir o unlock nativo seguro do macOS, nem o FileVault pré-boot.
- Glance e Peek informam expressamente que não atingem Face ID/Touch ID e que desbloqueiam digitando senha armazenada; Glance admite ataques por vídeo.
- HasBrain/FaceUnlock documenta mecanismo semelhante de senha criptografada, proteção de chave pelo Touch ID e entrada via eventos de teclado. Apesar da proteção, a senha precisa tornar-se disponível à aplicação para ser digitada.

## Diagnóstico por objetivo

| Objetivo | Viabilidade | Restrição principal | Posição inicial |
|---|---|---|---|
| Reconhecer rosto em aplicativo | Alta | calibração e consentimento | Implementar |
| Proteger templates biométricos localmente | Alta | desenho correto de chaves, armazenamento, lifecycle | Implementar |
| Resistir a foto estática | Parcial/testável | depende de dados, PAD e equipamento | Implementar e medir |
| Resistir a replay em vídeo/deepfake | Indeterminada | câmera RGB sem depth/IR, limitações de PAD | Não prometer |
| Igualar confiança de Face ID/Touch ID | Não demonstrável com webcam integrada | ausência de sensores e integração de confiança | Não alegar |
| Desbloquear sessão macOS sem senha armazenada | Sem caminho simples oficialmente documentado | API/autorização do SO | Apenas estudo |
| Usar iPhone com Face ID como prova de identidade | Viável para app pareado | integração do login macOS permanece separada | Pesquisa futura |

## Avaliação de abordagens

**A. App próprio SwiftUI + Core ML e Keychain:** auditável, modular, segurança local, menor risco de degradação da proteção do macOS. Mais trabalho inicial. Recomendado para MVP.

**B. Fork Glance/Peek:** desenvolvimento de UI/inferência mais rápido; principal custo é a arquitetura baseada em credencial de login armazenada e injetada. Referência de implementação, NÃO instalação automática.

**C. iPhone companheiro via Face ID:** aproveita sensor/biometria do iPhone para assinar autorização de aplicativo; requer emparelhamento e protocolo criptográfico bem definido; não é login nativo do macOS.

**D. Authorization Plug-in:** API pública de mecanismo de autorização, mas integração com login pode ser arriscada e específica da versão; não tentar no Mac principal sem plano de recuperação. FileVault pré-boot é problema distinto.

## Segurança residual e conclusão

O principal gargalo não é RAM nem processador. É **confiança do sensor, resistência a apresentação fraudulenta e forma de integração com autenticação do sistema**. Um bom MVP pode ser útil para experiência e pesquisa de segurança, mas a webcam RGB não deve tornar-se o único fator para proteger sessão macOS. A senha/Touch ID/FileVault devem continuar autoridades finais.
