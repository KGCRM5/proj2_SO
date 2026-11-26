# Quanto espaço consome no disco do servidor para cada cliente novo que é criado?
**OS Inoperantes** 

— Klaus Gustavo Castelein Ricieri Moura: Formato de armazenamento dos dados

— José Maike Ferreira Ferro: Quantidade de dados já existentes em disco

— Bruno Matheus Garutti Pinto: Journal ligado/desligado

— Gabrieli Souza Santos: Tamanho dos dados


## Contexto
Um servidor de cadastro grava cada cliente novo em disco. Queremos saber se o custo é só o tamanho do dado ou se o sistema de arquivos cobra a mais (inodes, blocos de 4 KB, diretório, journal).


## Dispositivo
GitHub Codespaces deste repositório. Medição em um disco de teste de 1 GB (loop device) em ext4, recriado a cada repetição. SO, kernel, CPU e RAM em `medicoes/dados/ambiente.txt`.


## Método
`sync`, lê `df`, cria 100 clientes novos, `sync`, lê o `df` de novo. Custo = (depois − antes) ÷ 100, em KB por cliente, com 3 repetições para 1 e 1.000 clientes existentes.


## Como reproduzir
1. `cd medicoes`
2. `sudo bash medir_clientes.sh` (um arquivo por cliente, com e sem journal)
3. `sudo bash medir_sqlite.sh` (SQLite)
4. `column -s, -t dados/resumo.csv` e `column -s, -t dados/resumo_sqlite.csv`


## Estrutura
- `relatorio/`: relatório final
- `fichas/`: entregas semanais
- `medicoes/`: dados brutos e tabelas
- `medicoes/dados/`: saídas brutas e CSVs de resumo


## Relatório
[Projeto 2 - SO.pdf](https://github.com/user-attachments/files/35486927/Projeto.2.-.SO.pdf)
