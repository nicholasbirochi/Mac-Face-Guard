# Plano de execução e critérios verificáveis

## Etapa 0 — Ferramentas e ambiente

**Entregas:** inventário de Xcode/Swift/macOS, `swift test`, fontes verificadas, relatório de licenças, riscos.

**Aceite:** comando e resultado documentados; nada instalado sem autorização; sem segredo coletado.

## Etapa 1 — App UI + câmera

**Entregas:** `.app` SwiftUI, preview AVFoundation com indicador ativo, solicitação/negação de permissão, modo demo sem registro de vídeo, finalização de sessão de câmera.

**Aceite:** build e execução reais no M5; sem câmera quando inativo; status de autorização honesto; app não escreve credenciais nem desbloqueia macOS.

## Etapa 2 — Cadastro + autenticação 1:1

**Entregas:** modelo licenciado de face, interface de provider, enrollment multi-pose, embeddings locais protegidos, gestão/exclusão de identidade.

**Aceite:** identificação sob diferentes poses/iluminação medida; Keychain e CryptoKit auditáveis; redefinição protegida; falha em ausência de modelos; ausência de armazenamento de imagens por padrão.

**Situação em 0.1.6 (18/10/2026): parcial.** Entregues: EdgeFace XS (BSD-3-Clause) convertido localmente com hash fixado, alinhamento por cinco pontos, cadastro v2 com três poses e embeddings cifrados, recusa sem modelo ou com hash divergente, exclusão protegida por Touch ID. Pendentes: amostra humana (hoje 0), limiar calibrado, FMR/FNMR por pose e iluminação, paridade do alinhamento com a referência em Python. Nenhuma autorização é concedida antes do PAD (Etapa 3).

**0.1.7 (18/10/2026):** o cadastro ganhou um anel de giro (guia de movimento, não PAD). Limiares do anel ainda não calibrados com pessoas.

**0.1.8 (18/10/2026):** o anel de cadastro passou para uma ilha no entalhe da câmera. Só interface; nada muda na decisão.

## Etapa 3 — Detecção de ataques

**Entregas:** PAD com critérios e proveniência, qualidade/captura temporal, testes com fotos e telas, desafios ativos opcionais, relatório de erro.

**Aceite:** conjunto de testes estruturado incluindo vídeo e câmera virtual; métricas publicadas com metodologia e tamanho da amostra; nenhum "sucesso" se PAD for inconclusivo.

## Etapa 4 — Revisão de segurança

**Entregas:** ameaça atualizada, checagem de dependências/artefatos/licenças, fluxo de remoção, relatório de build e testes.

**Aceite:** requisitos críticos de segurança atendidos e pendências explícitas. Preparar distribuição local sem contornar Gatekeeper.

## Etapa 5 — Estudo de desbloqueio nativo, sem implementação

**Entregas:** matriz de APIs do macOS, riscos FileVault/loginwindow, alternativas, plano de teste e reversão para laboratório.

**Aceite:** nenhuma alteração no mecanismo de login real sem autorização separada.

## Casos obrigatórios no Test Suite

- Cadastro inexistente: recusa.
- Câmera negada/desconectada: recusa.
- Zero ou mais de uma face: recusa.
- Identidade não correspondente: recusa.
- Falha ou resultado inconclusivo de PAD: recusa.
- Evidência de spoof: recusa.
- Qualidade insuficiente, frames inconsistentes, sessão expirada: recusa.
- Todas as evidências satisfatórias: **autorização de demonstração**, jamais desbloqueio do sistema.
- Dados cifrados adulterados: não decifrar/recusar.
- Reinstalar, revogar câmera e apagar templates: fluxo testado.
- Mostrar termos de segurança, não chamar experiência de Face ID certificado.

## Relatório final mínimo

O agente deve entregar `reports/STATUS_FINAL.md` com versão, ambiente, comandos de build, testes aprovados/falhos, funcionalidades reais, funcionalidades simuladas, vulnerabilidades conhecidas, permissões instaladas, limpeza/reversão e próximos passos.
