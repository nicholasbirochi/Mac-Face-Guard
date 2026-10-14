# Ambiente de desenvolvimento — 14/10/2026

- macOS 26.7, build 25G229, arm64.
- Xcode 27.0 (27A266a), Swift 6.4.
- Compilação e testes locais com frameworks do SDK Apple. Nenhuma dependência/modelo externo instalado.
- Inspeção do script original sem alterações de sistema.
- Starter: 10 testes aprovados; demo simulada recusou por falta de vivacidade.
- Projeto: 17 testes aprovados e build release realizado.
- O sandbox impediu o cache padrão do compilador; os testes usaram caches temporários e `--disable-sandbox` do SwiftPM. A compilação final usou as ferramentas locais fora desse sandbox.
