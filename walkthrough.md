# Walkthrough: FileLister macOS (v1.1 — April 2026)

**FileLister** is a native macOS tool for auditing storage and eliminating duplicate files safely and efficiently.

---

## Funcionalidades Implementadas 🚀

### 1. Varrimento Flexível

- **Recursividade Total**: Percorre todas as subpastas da origem selecionada (disco USB, pasta local, etc.).
- **Deep Scan (SHA-256)**: Comparação byte-a-byte do conteúdo dos ficheiros para deteção 100% precisa. Mais lento mas infalível.
- **Quick Scan**: Comparação por nome e tamanho — rápido para ficheiros óbvios como cópias com " copy" no nome.
- **Filtro por Média**: Ativa o modo "Media" para focar apenas em fotos, vídeos e áudio.
- **Ficheiros Ocultos**: O toggle "No Hidden" exclui `.DS_Store` e outros ficheiros de sistema.
- **Filtro por Extensão**: Campo de texto "Ext" permite filtrar por tipo de ficheiro (ex: `xls`, `pdf`, `jpg`).

### 2. Gestão Inteligente de Duplicados

- **Safety Lock**: Impede a eliminação da última cópia de qualquer ficheiro. O ícone de lixo transforma-se num cadeado.
- **Flag "Ignore"**: Cada ficheiro tem uma checkbox "Ignore". Se ativada, o ficheiro é excluído da limpeza automática e a sua linha fica destacada a cinzento escuro.
- **Regras de Auto-Seleção**: Menu dropdown a aplicar a todos os grupos:
  - **Manual Selection**: O utilizador decide manualmente qual o ficheiro a manter.
  - **Keep Oldest**: Mantém o ficheiro criado há mais tempo.
  - **Keep Newest**: Mantém o ficheiro criado mais recentemente.
  - **Keep Largest**: Mantém o ficheiro maior (útil para media de alta resolução).
- **Integração com o Lixo**: Ficheiros não são apagados permanentemente — movidos para o **Trash** do macOS.

### 3. Confirmação de Eliminação

- **Eliminação Individual**: Clicar no ícone do lixo de um ficheiro abre uma caixa de confirmação com o caminho completo do ficheiro.
- **Eliminação em Lote**: O botão "Clean All Duplicates (N)" mostra o número de ficheiros a eliminar entre parênteses. A caixa de confirmação apresenta:
  - Número exato de ficheiros a eliminar.
  - Espaço total a recuperar (ex: "1.45 GB").
  - Avisos de irreversibilidade e garantia de preservação dos originais.

### 4. Registo de Ações (Log)

- **Ativação**: Clicar na palavra "Log" abre um seletor de pasta. Selecionar uma pasta ativa automaticamente o log.
- **Criação Lazy**: O ficheiro de log só é criado no momento da **primeira eliminação**. Navegar e filtrar não gera nenhum ficheiro.
- **Formato do Nome**: `FileLister_Log_yyyy_MM_dd_HH_mm_ss.txt`
- **Conteúdo**: Cada linha regista a data/hora e o caminho completo do ficheiro eliminado.
- **Reset por Sessão**: Cada nova pesquisa reinicia o contexto do log. A próxima eliminação gera um novo ficheiro com novo timestamp.

### 5. Ordenação e Interface

- **Ordenação por Cópias**: Ordena os grupos pelo número de duplicados (crescente/decrescente).
- **Ordenação por Tamanho**: Ordena os grupos pelo tamanho de cada ficheiro.
- **Quick Look**: Pré-visualização do ficheiro selecionado com a **Barra de Espaço**, igual ao Finder.
- **Feedback Visual**: Ficheiros eliminados ficam a vermelho e riscados; ficheiros ignorados ficam a cinzento.
- **Tooltips**: Pairar o rato sobre qualquer filtro ou botão mostra uma descrição contextual.
- **Barra de Estado**: Progresso em tempo real e contadores de ficheiros/espaço na barra inferior.

---

## Notas Técnicas e Segurança ⚠️

> [!IMPORTANT]
> **Sandbox e Permissões:**
> Se a app falhar ao analisar pastas protegidas, verifica que as permissões **User Selected File** estão em **Read/Write** no Xcode (aba *Signing & Capabilities*).

> [!NOTE]
> **Build Script (`build_release.sh`)**:
> O script faz clean + build + zip + upload automático para o GitHub Releases (tag `v1.0.0`).
> Para forçar um rebuild limpo: `rm -rf build Dist && xcodebuild ... && cp -R ...`

> [!TIP]
> **Backup do Projeto**:
> Existe uma cópia de segurança em: `/Users/luissilva/.gemini/antigravity/scratch/backups/FileLister_Backup`

---

## Como Usar

1. Prime **"Select..."** para escolher a pasta ou disco a auditar.
2. Configura os filtros: **Deep Scan**, **Media**, **No Hidden**, **Log**, **Ext**.
3. Prime **"Search for Duplicates"** para iniciar o varrimento.
4. Revê os grupos de duplicados. Aplica uma **Regra de Auto-Seleção** se quiseres.
5. Usa o ícone do lixo em ficheiros individuais ou prime **"Clean All Duplicates (N)"** para limpeza em lote.
6. Confirma a caixa de diálogo (mostra contagem de ficheiros e espaço a recuperar).
7. Se o **Log** estiver ativo, encontras o registo na pasta selecionada.

---

*Última atualização: Abril 2026*
