# Walkthrough: FileLister macOS (v1.0)

O **FileLister** é agora uma ferramenta completa e segura para auditar o teu armazenamento e eliminar ficheiros duplicados sem riscos.

## Funcionalidades Implementadas 🚀

### 1. Varrimento Profundo e Flexível
- **Recursividade Total**: A aplicação percorre todas as subpastas da origem selecionada (Disco USB ou pasta local).
- **Ficheiros Ocultos**: Inclui ficheiros de sistema e ocultos (ex: `.DS_Store`).
- **Unidades Automáticas**: Converte o tamanho dos ficheiros para **KB** ou **MB** de forma inteligente e compacta.

### 2. Exportação para Excel
- **Formato CSV Compacto**: Gera um ficheiro `filelist.txt` com o formato `Caminho;Nome;Tamanho;Tipo`.
- **Sem Cabeçalhos**: O ficheiro contém apenas dados puros para facilitar a importação direta.
- **Tradução**: Todo o conteúdo é exportado em Inglês (`Folder`, `File`).

### 3. Deteção e Gestão de Duplicados 🛡️
- **Contador Dinâmico**: Mostra quantas cópias restam de cada ficheiro em tempo real.
- **Integração com o Lixo**: Os ficheiros não são apagados permanentemente; são movidos para o **Trash** do macOS.
- **Safety Lock (Bloqueio de Segurança)**: A app **impede a eliminação da última cópia**, transformando o ícone do lixo num cadeado quando resta apenas um ficheiro.
- **Feedback Visual**: Ficheiros eliminados ficam riscados e a vermelho na interface.

### 4. Interface Minimalista
- **Barra de Estado**: Mensagens de sistema no fundo da janela para não poluir o ecrã.
- **Layout Horizontal**: Controlos compactos no topo para maximizar o espaço para a lista de duplicados.

## Notas Técnicas e Segurança ⚠️

> [!IMPORTANT]
> **Sandbox e Permissões:** 
> Se a app crashar ao "Gerar Lista", certifica-te de que as permissões **User Selected File** estão em **Read/Write** no Xcode (aba *Signing & Capabilities*).

> [!TIP]
> **Backup**: Foi criada uma cópia de segurança de todo o projeto na pasta: 
> `/Users/luissilva/.gemini/antigravity/scratch/FileLister_Backup`

## Como Usar
1. Prime **"Select..."** para escolher a pasta ou disco.
2. Prime **"Generate"** e escolhe onde guardar o `filelist.txt`.
3. Observa a barra de progresso verde.
4. Se houver duplicados, usa o botão do lixo para limpar o disco, descansado de que a última cópia está sempre bloqueada e segura.

---
**Projeto Concluído!** Se precisares de mais alguma funcionalidade no futuro, estou aqui para ajudar.
