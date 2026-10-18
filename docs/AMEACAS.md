# Modelo de ameaças e medidas de segurança

## Ativos

Senha de usuário macOS (que o projeto **não deve tocar**), sessão autenticada, templates de face, chaves de criptografia, dados capturados da câmera, permissões e integridade do app/modelo.

## Adversários possíveis

Pessoa com acesso físico temporário, alguém com foto pública do proprietário, alguém com vídeo em celular/tablet, ator com deepfake reproduzido, aplicação maliciosa em sessão já comprometida, plugin/modelo adulterado, pessoa parecida com o dono.

## Matriz de risco qualitativa (não estatística)

| Ameaça | Impacto | Controles necessários | Risco residual |
|---|---|---|---|
| Foto impressa | acesso indevido à demo | PAD + testes variados | ainda presente até medir |
| Foto em celular | acesso indevido à demo | PAD refletância, movimento temporal | ainda presente |
| Vídeo gravado | replay de movimentos | desafios aleatórios + PAD temporal | elevado/não comprovado |
| Deepfake de vídeo | falso rosto responsivo | múltiplos controles + avaliação especializada | desconhecido/elevado |
| Câmera virtual / frame injection | falsa origem do stream | validação de origem e desenho de confiança do sensor | não resolvido por software simples |
| Rosto semelhante / gêmeos | falso match | limiar calibrado e avaliação específica | não mensurado; na 0.1.6 não há limiar e a similaridade não autoriza |
| Roubo de templates | exposição de dado biométrico | AES-GCM, Keychain, `ThisDeviceOnly`, privilégio mínimo | depende da segurança do endpoint |
| Roubo de chave por sessão comprometida | exposição | acesso biométrico/device owner com LAContext, expiração | não elimina malware em sessão |
| Falha de dependência/modelo | execução maliciosa | pin/assinatura/hash, auditoria e SBOM | exige manutenção; na 0.1.6 revisão upstream, checkpoint e pacote Core ML têm SHA-256 fixado e conferido antes do uso |
| Alteração de configuração | PAD desativado | configurações protegidas, defaults restritivos | deve ser testado |
| Falha de câmera / ausência de rede | erro interpretado como sucesso | negar por padrão, sem fallback inseguro | baixo se implementado |
| Login via senha injetada | divulgação de credencial/uso em foco errado | **não implementar** | eliminado do escopo |

## Métricas e experimentos

- Identidade: FMR (taxa de falsa correspondência), FNMR (taxa de falso não reconhecimento), amostragem documentada, intervalo de confiança e diferenças por iluminação/pose/representatividade.
- PAD: APCER (aceitação de apresentação de ataque) e BPCER (rejeição de apresentação legítima), separados por modalidade (foto, tela, vídeo, câmera virtual, máscara). Se amostra insuficiente, dizer **sem inferência confiável**.
- Controles: taxa de bloqueio em ausência de permissão, tempo de espera, número máximo de tentativas, expiracão de sessão, integridade dos modelos.
- Nunca alegar “99,9% seguro” por resultados em meia dúzia de vídeos.

## Referência

NIST SP 800-63B (edição 800-63-4): requisitos para autenticadores e PAD. Metas do NIST descrevem sistemas avaliados sob condições definidas; não se autodeclara conformidade com base apenas em regras caseiras.
