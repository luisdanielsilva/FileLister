# Registo Histórico: Projeto FileLister Pro & Dev Hub

Este documento serve como a "caixa negra" do desenvolvimento deste projeto. Contém toda a lógica, decisões e estado final para preservação offline.

## 📁 Estrutura do Ecossistema
O projeto é composto por três pilares principais:
1.  **FileLister (macOS)**: App nativa em Swift/SwiftUI com verificador binário e sistema de trial de 15 ficheiros.
2.  **LS Developer Hub (Web)**: Portal premium em HTML/CSS/JS para showcase das suas 4 aplicações (FileLister, KnockApp, BrightnessApp, System Pulse).
3.  **Engine de Licenciamento**: Algoritmo SHA-256 com Sal Secreto ("FileLister-Secret-Salt-2026-Porto") que une a App macOS e o Portal Web.

---

## 🔑 Algoritmo de Licenciamento (O Coração)
Para recriar ou validar chaves, a lógica é:
- **Input**: Semente aleatória de 20 caracteres (A-Z, 0-9).
- **Processo**: `Hash_SHA256(Semente + Palavra_Secreta)`.
- **Resultado**: Os primeiros 4 caracteres do Hash em Hex (Maiúsculas) tornam-se a assinatura da chave.
- **Formato Final**: `XXXX-XXXX-XXXX-XXXX-XXXX-SIG4`.

---

## 🗺️ Roadmap Final (Estado do Projeto)
- [x] **V1.0**: Scan recursivo, Deep Scan (SHA-256), Trash seguro.
- [x] **V1.1**: Limpeza em lote (Clean All), Verificação binária bit-a-bit, Monitorização de progresso.
- [x] **Licenciamento Pro**: Gerador automatizado com e-mail, registo por nome na barra de título, botão "Unregister".
- [x] **Infraestrutura Web**: Landing page de portfólio com simulação de compra e desbloqueio do gerador.

---

## 🛠️ Notas de Continuidade
Para retomar o projeto ou fazer novos builds:
1.  **Xcode**: Carregar o ficheiro `FileLister.xcodeproj` na pasta `FileLister`.
2.  **Build de Produção**: Executar `./build_release.sh` no terminal.
3.  **Gerador de Chaves**: Executar `swift generate_pro_license.swift "Nome" "email"`.
4.  **Servidor Web**: Executar `python3 -m http.server 8000` na pasta `webapp`.

---

## 📜 Memória da Conversa
Todo o processo de pair-programming, desde a implementação do primeiro botão até ao design da Landing Page, está documentado nos logs locais do sistema Antigravity. Este ficheiro MD resume as 12 horas de desenvolvimento intensivo focadas em segurança e estética premium.

*Preservado em 12 de Abril de 2026.* 🥂📁🌟
