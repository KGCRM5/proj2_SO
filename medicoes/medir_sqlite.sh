#!/usr/bin/env bash
# medir_sqlite.sh — custo em disco por cliente quando todos ficam num banco SQLite (frente do Klaus)
#
# Uso:
#   sudo ./medir_sqlite.sh              # N = 1 e 1000, 3 repetições
#   sudo ./medir_sqlite.sh 1 1          # teste: N=1, uma repetição
#
# Mesmo método do medir_clientes.sh, mas com 1 registro de 1 KB por cliente em
# um único arquivo clientes.db, em vez de 1 arquivo por cliente.

set -euo pipefail

QTDS=${1:-"1 1000"}
REPS=${2:-3}
NOVOS=100
TAM_REG=1024

BASE=$(cd "$(dirname "$0")" && pwd)
DADOS="$BASE/dados"
IMG="$BASE/disco_sqlite.img"
MNT="/mnt/medicao_sqlite"
CSV="$DADOS/resumo_sqlite.csv"

[[ $EUID -eq 0 ]] || { echo "Rode com sudo."; exit 1; }
command -v python3 >/dev/null || { echo "Falta python3"; exit 1; }
python3 -c "import sqlite3" || { echo "python3 sem módulo sqlite3"; exit 1; }

mkdir -p "$DADOS" "$MNT"
limpar() { mountpoint -q "$MNT" && umount "$MNT" || true; rm -f "$IMG"; }
trap limpar EXIT

[[ -f "$CSV" ]] || echo "n_existentes,rep,df_antes_KB,df_depois_KB,custo_df_KB_por_cliente,db_bytes_antes,db_bytes_depois,custo_arquivo_KB_por_cliente,data_hora" > "$CSV"

insere() {   # $1 = banco, $2 = quantidade
  python3 - "$1" "$2" "$TAM_REG" <<'PY'
import sqlite3, sys
db, qtd, tam = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
con = sqlite3.connect(db)
con.execute("CREATE TABLE IF NOT EXISTS clientes (id INTEGER PRIMARY KEY, dados BLOB)")
con.executemany("INSERT INTO clientes (dados) VALUES (?)", ((b"x" * tam,) for _ in range(qtd)))
con.commit(); con.close()
PY
}

df_used() { df --output=used -k "$MNT" | tail -1 | tr -d ' '; }

for n in $QTDS; do
  for ((r=1; r<=REPS; r++)); do
    SAIDA="$DADOS/sqlite_N${n}_rep${r}.txt"
    echo ">> sqlite | N=$n | repetição $r"
    mountpoint -q "$MNT" && umount "$MNT"
    rm -f "$IMG"; truncate -s 1G "$IMG"
    mkfs.ext4 -q -F -E lazy_itable_init=0,lazy_journal_init=0 "$IMG"
    mount -o loop "$IMG" "$MNT"
    DB="$MNT/clientes.db"

    insere "$DB" "$n"; sync
    ANTES=$(df_used); BA=$(stat -c %s "$DB")
    insere "$DB" "$NOVOS"; sync
    DEPOIS=$(df_used); BD=$(stat -c %s "$DB")

    CUSTO=$(awk -v a="$ANTES" -v d="$DEPOIS" -v k=$NOVOS 'BEGIN{printf "%.2f",(d-a)/k}')
    CARQ=$(awk -v a="$BA" -v d="$BD" -v k=$NOVOS 'BEGIN{printf "%.2f",(d-a)/1024/k}')
    AGORA=$(date '+%Y-%m-%d %H:%M:%S')

    {
      echo "comando: sudo $0 $n $REPS"
      echo "N_existentes=$n  repeticao=$r  novos=$NOVOS  tam_registro=${TAM_REG}B"
      echo "df_antes_KB=$ANTES  df_depois_KB=$DEPOIS"
      echo "clientes.db antes=${BA} bytes  depois=${BD} bytes"
      echo "custo_df_KB_por_cliente=$CUSTO"
      echo "custo_arquivo_KB_por_cliente=$CARQ"
    } > "$SAIDA"
    echo "$n,$r,$ANTES,$DEPOIS,$CUSTO,$BA,$BD,$CARQ,$AGORA" >> "$CSV"
    echo "   custo_df=$CUSTO KB/cliente | crescimento do .db=$CARQ KB/cliente"
  done
done

echo; echo "Pronto. Resumo em $CSV"; column -s, -t "$CSV" 2>/dev/null || cat "$CSV"
