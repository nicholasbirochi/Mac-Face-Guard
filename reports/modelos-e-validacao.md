# MacFaceGuard — modelo facial e avaliação incremental

Consulta em 17/10/2026. Proposta para laboratório local, aprovada pelo usuário no mesmo dia (ver "Estado após a aprovação"). Não há reconhecimento 1:1, PAD validado ou desbloqueio do sistema na versão instalada 0.1.4.

## Diagnóstico confirmado no código

`CameraPipeline` já separa a câmera em fila serial, limita a análise a dois quadros por segundo, usa a câmera integrada e descarta imagens após a análise. `AppModel` controla consentimento, Touch ID, três posições, prazo e encerramento. `TemplateVault` e `EnrollmentCipher` mantêm AES-GCM, AAD, backend protegido do Chaves e escrita atômica fora do projeto. Esses componentes devem ser mantidos.

A parte a substituir é `VNGenerateImageFeaturePrintRequest`: gera características genéricas da imagem, sem um modelo de identidade. A comparação atual não possui limiar de identidade. `DecisionEngine` recebe explicitamente identidade e vivacidade falsas do adaptador real. O resultado continua recusado. Movimento e qualidade de captura não são evidência suficiente de PAD.

Não foi aberto, decifrado, exportado ou reenviado o cadastro do proprietário. O cadastro existente permanece no formato v1, provedor `apple-vision-image-feature-print`, revisão 2. Não será reinterpretado como embedding facial.

## Alternativas verificadas em fontes primárias

| Alternativa | Evidência publicada e custo aproximado dos pesos | Código versus pesos | Adequação e limites |
| --- | --- | --- | --- |
| **EdgeFace XS gamma 0.6** | Autores publicam 1,77 milhões de parâmetros e 154 MFLOPs; LFW 99,73% e CFP-FP 94,71%, com protocolos de benchmark próprios. Checkpoint oficial: 7.170.425 bytes. | Repositório oficial dos autores distribui código e checkpoints sob LICENSE BSD-3-Clause; não foi localizada licença individual adicional do checkpoint. Conferência da cadeia dos dados de treino e de redistribuição permanece necessária antes de publicar pesos. | Candidato preferido para protótipo local pequeno. Conversão Core ML e equivalência numérica ainda precisam ser demonstradas. Latência, RSS, ANE e bateria no M5 **não medidos**. |
| **SFace 2021dec / MobileFaceNet** | OpenCV Zoo relata acurácia 0,9940 e alinhamento com cinco pontos. Artefato ONNX de aproximadamente 38,7 MB. | README do diretório declara Apache-2.0 para todos os arquivos. A origem exata dos dados e o alcance sobre redistribuição dos pesos motivam a questão upstream #313, ainda sem confirmação autorizada visível nesta consulta. | Alternativa para comparar qualidade/pose após esclarecer proveniência. A rota ONNX exigiria conversão adicional ou runtime maior; não acrescentar OpenCV ao app apenas por conveniência. |
| **InsightFace / ArcFace w600k_r50 (buffalo_l)** | Pacote oficial buffalo_l: 326 MB, incluindo detector e outros modelos; esse tamanho não é somente o reconhecedor. | Código MIT; modelos pré-treinados públicos limitados a pesquisa não comercial, inclusive downloads manuais. A licença do código não libera os pesos. | Referência de pesquisa possível, sem redistribuir os pesos neste fork. Mais componentes que o necessário para a câmera/Vision existente. Sem vantagem medida neste Mac. |

Esses percentuais não são FMR/FNMR do MacFaceGuard e não são comparações diretas entre protocolos. Não predizem taxa de erro do proprietário, sob baixa luz, óculos ou mudança de pose. Todos permitem inferência offline depois de obter o artefato apropriado; nenhum comprova presença física.

## Recomendação concreta para aprovação

Avaliar **apenas EdgeFace XS gamma 0.6**, inicialmente dentro do app e sem conceder autorização. Fonte: `otroshi/edgeface`, revisão `ce86851cfc37979a9cd2558598d0e9bc592cbba3`; arquivo `checkpoints/edgeface_xs_gamma_06.pt`; Git blob `af5f8c5cf75e8b90d82d08f7a07ee10677327bfd`, 7.170.425 bytes. Metadados lidos pela API pública; SHA-256 dos pesos **ainda não calculado**, porque o arquivo não foi baixado. Antes da conversão, verificar tamanho, revisão e integridade e registrar SHA-256 próprio. Não usar `torch.hub` nem downloads automáticos.

A conversão exigiria ferramentas Python em ambiente virtual isolado: PyTorch, torchvision/timm e coremltools, mais suas dependências necessárias. Não estão disponíveis no Python consultado. Os downloads podem somar centenas de MB ou mais de 1 GB, conforme versões e wheels; resolver a lista/tamanhos antes de instalar. Esses pacotes seriam ferramentas de conversão, não dependências do app Swift distribuído. Não instalar automaticamente toda a lista upstream, que inclui MXNet/OpenCV. Revisar o código usado e carregar somente tensores com `weights_only=True` em versão compatível do PyTorch.

Aprovação solicitada para **download e ensaio local desse candidato e ferramentas isoladas**, sem enviar dados faciais, sem publicar pesos, sem modificar login do macOS. A autorização do usuário não substitui os termos dos artefatos. Se a checagem do checkpoint revelar restrições adicionais incompatíveis, interromper essa rota e reavaliar antes de uso.

A arquitetura proposta mantém AVFoundation e Vision para detecção/landmarks, separa alinhamento, extração de embedding normalizado, similaridade e decisão. O alinhamento RGB 112×112 e a normalização precisam reproduzir a referência dos autores; equivalência de landmarks e conversão não pode ser presumida. O fluxo Apple de conversão PyTorch → Core ML é documentado, mas não garante suporte a todos os operadores deste modelo.

## Estado após a aprovação (17/10/2026)

O usuário autorizou o protótipo local do EdgeFace XS e das ferramentas de conversão isoladas.

- Checkpoint baixado da revisão fixada para `~/Library/Caches/MacFaceGuard/edgeface-build/`, fora do repositório: 7.170.425 bytes, SHA-256 `5ae7504c…6ce16`, conferido por `scripts/convert-edgeface.py` antes de carregar (`weights_only=True`).
- Ferramentas em ambiente virtual próprio no mesmo cache (torch 2.7.1, coremltools 9.0); não são dependências do app.
- Conversão para `EdgeFaceXS.mlpackage` (FP32, CPU_ONLY, entrada RGB 112×112, saída de 512 dimensões) concluída. Em 8 entradas **sintéticas**, cosseno em relação ao PyTorch ≥ 0,99999 e erro absoluto máximo ≤ 2e-7; `predict` isolado levou cerca de 2,5 ms por imagem após a primeira chamada (29 ms). Isso prova equivalência numérica da conversão, não precisão biométrica nem latência do pipeline completo.
- Ainda não feito: alinhamento por cinco pontos em Swift, extração no app, novo formato de cadastro, migração e qualquer ensaio com pessoas. Amostra humana continua **0**.

## Cadastro e migração

Após converter e validar o modelo: formato novo com identificador do modelo, revisão/hash, dimensão e versão de pré-processamento; validação estrita de tamanho, finitude e normalização. Um cadastro incompatível exige novo cadastro com consentimento e Touch ID. Preservar o cadastro anterior até que o novo seja concluído e salvo atomicamente. Troca/cancelamento nunca pode deixar a chave do registro válido removida. Nenhum teste deve ler o arquivo do proprietário.

Antes de oferecer correspondência 1:1: testar modelo ausente/adulterado/incompatível, vetores inválidos, imagens diferentes, mais de uma face, captura ruim, expiração e exclusão com dados sintéticos isolados. Ausência de modelo ou PAD continua resultando em recusa, mesmo com similaridade alta.

## PAD e evidências

MiniFASNet/Silent-Face-Anti-Spoofing é candidato de pesquisa separado: repositório Apache-2.0; licença/proveniência de cada peso precisam de conferência. O próprio upstream destaca dependência da câmera/cena. A variante V2 tem 0,435 milhões de parâmetros; os tempos em telefones publicados não são medições no M5. Nenhum peso PAD foi baixado ou aprovado.

Uma integração futura deve registrar em memória identidade/versionamento do modelo, janela e contagem de quadros, qualidade, consistência temporal, scores por apresentação, desafio solicitado/cumprido e motivo de recusa. Scores não calibrados, artefato ausente e evidência inconclusiva não autorizam. Desafios de cabeça/olhos podem complementar o ensaio; não substituem um detector validado contra fotografia, tela e replay.

## Protocolo de avaliação antes de autenticação

1. Obter consentimento específico para ensaios; manter identificadores anônimos e resultados locais. Não gravar fotos/vídeos por padrão. Definir previamente coleta, exclusão e autorização para qualquer conjunto separado.
2. Separar desenvolvimento/calibração/teste por pessoas e sessões. Usar sessões genuínas distintas do cadastro, pares impostores e condições de luz/pose/óculos. Registrar falhas de aquisição separadamente.
3. Escolher ponto operacional a partir do risco e curvas reais na calibração; congelar modelo, pré-processamento e limiar antes do teste. Não importar o limiar de uma demo nem escolher um número arbitrário.
4. Reportar FMR = falsas correspondências / comparações impostoras, FNMR = falsas rejeições / comparações genuínas, numeradores, denominadores e intervalos de confiança. Pares correlacionados não equivalem a pessoas independentes. Zero erros numa amostra pequena não demonstra segurança.
5. Para PAD, reportar APCER por tipo de instrumento/ataque e BPCER em apresentações legítimas. Incluir fotos impressas, telas LCD/OLED, vídeos gravados, replay/desafios, câmeras virtuais e variações de luz. Selecionar/declarar protocolo de agregação e limiar antes do teste; não misturar FMR com APCER.
6. Medir pipeline completo no M5, com sessão fria/quente: tempo de carga, latência mediana/p95 por quadro, RSS de pico, carga de CPU/GPU e energia em sessões delimitadas. Comparar CPU e unidades disponíveis; não prometer ANE ou latência antecipadamente. Câmera desligada fora de sessão deve continuar obrigatória.

Amostra humana atual: **0**. FMR, FNMR, APCER e BPCER: **não medidos**. O primeiro aceite é verificação experimental 1:1 no próprio aplicativo; integração de desbloqueio do macOS fica fora deste trabalho.

## Fontes consultadas

- [EdgeFace: autores, variantes e benchmarks](https://github.com/otroshi/edgeface); [licença BSD](https://github.com/otroshi/edgeface/blob/main/LICENSE); [checkpoint oficial](https://github.com/otroshi/edgeface/blob/main/checkpoints/edgeface_xs_gamma_06.pt).
- [SFace: modelo e licença do diretório](https://github.com/opencv/opencv_zoo/tree/main/models/face_recognition_sface); [questão de proveniência #313](https://github.com/opencv/opencv_zoo/issues/313).
- [InsightFace: licença separada dos modelos](https://github.com/deepinsight/insightface/blob/master/python-package/docs/model_zoo.md).
- [Apple: conversão PyTorch/Core ML](https://apple.github.io/coremltools/docs-guides/source/convert-pytorch-workflow.html).
- [MiniVision: limites e métodos do PAD RGB](https://github.com/minivision-ai/Silent-Face-Anti-Spoofing/blob/master/README_EN.md).

O repositório completo de treinamento EdgeFace no GitLab/Idiap bloqueou a consulta automatizada; não foi contornado. Revisão do pipeline de treino e licença dos datasets continua pendente. A avaliação acima registra evidência técnica publicada, não certificação biométrica ou conclusão jurídica.
