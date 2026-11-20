#!/usr/bin/env bash
# medir_clientes.sh — custo em disco por cliente (1 arquivo de 1 KB por cliente) no ext4
#
# Uso:
#   sudo ./medir_clientes.sh                     # tudo: journal/nojournal x 1/1000 x 3 repetições
#   sudo ./medir_clientes.sh journal 1 1         # só um modo, uma quantidade, uma repetição (teste)
#   sudo ./medir_clientes.sh journal 100000 1    # ponto extra (aumenta inodes automaticamente)
#
# Método (M2): disco de 1 GB em loop device, ext4 recriado a cada repetição;
# cria N clientes, sync, df; cria +100 clientes, sync, df; custo = (depois - antes) / 100.

set -euo pipefail

MODOS=${1:-"journal nojournal"}
QTDS=${2:-"1 1000"}
REPS=${3:-3}
NOVOS=100
TAM_ARQ=1024
TAM_DISCO=1G

BASE=$(cd "$(dirname "$0")" && pwd)
DADOS="$BASE/dados"
IMG="$BASE/disco_teste.img"
MNT="/mnt/medicao_clientes"
CSV="$DADOS/resumo.csv"

[[ $EUID -eq 0 ]] || { echo "Rode com sudo."; exit 1; }
for cmd in mkfs.ext4 mount umount df du awk sync; do
  command -v "$cmd" >/dev/null || { echo "Falta o comando: $cmd (instale e2fsprogs/coreutils)"; exit 1; }
done

mkdir -p "$DADOS" "$MNT"

limpar() { mountpoint -q "$MNT" && umount "$MNT" || true; rm -f "$IMG"; }
trap limpar EXIT

# ---------- ambiente da máquina ----------
{
  echo "data: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "host: $(hostname)"
  echo "kernel: $(uname -r)"
  grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' | sed 's/^/SO: /'
  echo "CPU: $(lscpu 2>/dev/null | awk -F: '/Model name/{gsub(/^ +/,"",$2);print $2;exit}')"
  echo "vCPUs: $(nproc)"
  echo "RAM: $(free -h | awk '/Mem:/{print $2}')"
  echo "e2fsprogs: $(mkfs.ext4 -V 2>&1 | head -1)"
  echo "disco de teste: $TAM_DISCO (loop device, arquivo $IMG)"
} > "$DADOS/ambiente.txt"

[[ -f "$CSV" ]] || echo "modo,n_existentes,rep,df_total_KB_fs_vazio,df_used_KB_fs_vazio,df_antes_KB,df_depois_KB,custo_df_KB_por_cliente,du_alocado_KB_por_cliente,du_aparente_KB_por_cliente,inodes_por_cliente,dir_KB_antes,dir_KB_depois,data_hora" > "$CSV"

PAYLOAD=$(printf 'x%.0s' $(seq 1 $TAM_ARQ))   # 1024 bytes

cria_clientes() {   # $1 = primeiro id, $2 = último id
  local i
  for ((i=$1; i<=$2; i++)); do
    printf '%s' "$PAYLOAD" > "$MNT/clientes/cliente_$i.dat"
  done
}

df_total()  { df --output=size  -k "$MNT" | tail -1 | tr -d ' '; }
df_used()   { df --output=used  -k "$MNT" | tail -1 | tr -d ' '; }
df_iused()  { df --output=iused    "$MNT" | tail -1 | tr -d ' '; }
dir_kb()    { echo $(( $(stat -c %b "$MNT/clientes") * $(stat -c %B "$MNT/clientes") / 1024 )); }

for modo in $MODOS; do
  for n in $QTDS; do
    for ((r=1; r<=REPS; r++)); do
      SAIDA="$DADOS/${modo}_N${n}_rep${r}.txt"
      echo ">> $modo | N=$n | repetição $r"

      # 1) disco novo + ext4 novo
      mountpoint -q "$MNT" && umount "$MNT"
      rm -f "$IMG"; truncate -s "$TAM_DISCO" "$IMG"
      OPTS=(-q -F -E lazy_itable_init=0,lazy_journal_init=0)
      [[ $modo == nojournal ]] && OPTS+=(-O ^has_journal)
      (( n + NOVOS > 60000 )) && OPTS+=(-N $(( n + NOVOS + 10000 )))
      mkfs.ext4 "${OPTS[@]}" "$IMG"
      mount -o loop "$IMG" "$MNT"
      mkdir "$MNT/clientes"; sync
      VAZIO=$(df_used); TOTAL=$(df_total)

      # 2) N clientes existentes
      cria_clientes 1 "$n"; sync
      ANTES=$(df_used); IANTES=$(df_iused); DIRA=$(dir_kb)
      DUA_ANTES=$(du -sk "$MNT/clientes" | cut -f1); DFTXT_ANTES=$(df -k "$MNT"; df -i "$MNT")
      DUP_ANTES=$(du -sk --apparent-size "$MNT/clientes" | cut -f1)

      # 3) +100 clientes novos
      cria_clientes $((n+1)) $((n+NOVOS)); sync
      DEPOIS=$(df_used); IDEPOIS=$(df_iused); DIRD=$(dir_kb)
      DUA_DEP=$(du -sk "$MNT/clientes" | cut -f1); DFTXT_DEP=$(df -k "$MNT"; df -i "$MNT")
      DUP_DEP=$(du -sk --apparent-size "$MNT/clientes" | cut -f1)

      CUSTO=$(awk -v a="$ANTES" -v d="$DEPOIS" -v k=$NOVOS 'BEGIN{printf "%.2f",(d-a)/k}')
      DUA=$(awk -v a="$DUA_ANTES" -v d="$DUA_DEP" -v k=$NOVOS 'BEGIN{printf "%.2f",(d-a)/k}')
      DUP=$(awk -v a="$DUP_ANTES" -v d="$DUP_DEP" -v k=$NOVOS 'BEGIN{printf "%.2f",(d-a)/k}')
      INOD=$(awk -v a="$IANTES" -v d="$IDEPOIS" -v k=$NOVOS 'BEGIN{printf "%.2f",(d-a)/k}')
      AGORA=$(date '+%Y-%m-%d %H:%M:%S')

      {
        echo "comando: sudo $0 $modo $n $REPS"
        echo "modo=$modo  N_existentes=$n  repeticao=$r  novos=$NOVOS  tam_arquivo=${TAM_ARQ}B"
        echo "--- df do disco vazio (já com o diretório clientes/) ---"
        echo "df_total_KB_fs_vazio=$TOTAL  (o journal sai daqui: reduz o tamanho útil)"
        echo "df_used_KB_fs_vazio=$VAZIO"
        echo "--- antes dos 100 novos ---"
        echo "$DFTXT_ANTES"
        echo "du_alocado_KB=$DUA_ANTES  du_aparente_KB=$DUP_ANTES  diretorio_KB=$DIRA"
        echo "--- depois dos 100 novos ---"
        echo "$DFTXT_DEP"
        echo "du_alocado_KB=$DUA_DEP  du_aparente_KB=$DUP_DEP  diretorio_KB=$DIRD"
        echo "--- resultado ---"
        echo "custo_df_KB_por_cliente=$CUSTO"
        echo "du_alocado_KB_por_cliente=$DUA"
        echo "du_aparente_KB_por_cliente=$DUP"
        echo "inodes_por_cliente=$INOD"
      } > "$SAIDA"

      echo "$modo,$n,$r,$TOTAL,$VAZIO,$ANTES,$DEPOIS,$CUSTO,$DUA,$DUP,$INOD,$DIRA,$DIRD,$AGORA" >> "$CSV"
      echo "   custo_df=$CUSTO KB/cliente | du_alocado=$DUA | du_aparente=$DUP | inodes=$INOD | fs_vazio: total=${TOTAL} KB usado=${VAZIO} KB"
    done
  done
done

echo; echo "Pronto. Resumo em $CSV"; column -s, -t "$CSV" 2>/dev/null || cat "$CSV"
