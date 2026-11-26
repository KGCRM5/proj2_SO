#!/usr/bin/env bash
# medir_quantidade.sh — quantidade de clientes existentes (coluna da Maike)
# Uso: sudo ./medir_quantidade.sh          (1 e 1000 clientes, 3 repetições)
# Em cada repetição: ext4 novo de 1 GB em loop device, cria N clientes (arquivos de 1 KB),
# sync, e conta os clientes de dois jeitos: ls | wc -l  e  inodes usados no df -i.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Rode com sudo."; exit 1; }

BASE=$(cd "$(dirname "$0")" && pwd)
DADOS="$BASE/dados"; IMG="$BASE/disco_qtd.img"; MNT="/mnt/medicao_qtd"
CSV="$DADOS/resumo_quantidade.csv"
mkdir -p "$DADOS" "$MNT"
limpar() { mountpoint -q "$MNT" && umount "$MNT" || true; rm -f "$IMG"; }
trap limpar EXIT

echo "n_criados,rep,qtd_ls,inodes_vazio,inodes_com_clientes,qtd_por_inodes,data_hora_utc" > "$CSV"
PAYLOAD=$(printf 'x%.0s' $(seq 1 1024))

for n in 1 1000; do
  for r in 1 2 3; do
    mountpoint -q "$MNT" && umount "$MNT"
    rm -f "$IMG"; truncate -s 1G "$IMG"
    mkfs.ext4 -q -F "$IMG"; mount -o loop "$IMG" "$MNT"
    mkdir "$MNT/clientes"; sync
    IVAZIO=$(df --output=iused "$MNT" | tail -1 | tr -d ' ')
    for ((i=1; i<=n; i++)); do printf '%s' "$PAYLOAD" > "$MNT/clientes/cliente_$i.dat"; done
    sync
    QLS=$(ls "$MNT/clientes" | wc -l)
    ICOM=$(df --output=iused "$MNT" | tail -1 | tr -d ' ')
    QINO=$((ICOM - IVAZIO))
    AGORA=$(date -u '+%Y-%m-%d %H:%M:%S')
    {
      echo "comando: sudo $0   (N=$n, repeticao=$r)"
      echo "\$ ls clientes | wc -l"; echo "$QLS"
      echo "\$ df -i  (disco vazio, so com a pasta clientes/)"; echo "IUsed=$IVAZIO"
      echo "\$ df -i  (com os clientes)"; df -i "$MNT"
      echo "quantidade pelos inodes = $ICOM - $IVAZIO = $QINO"
    } > "$DADOS/quantidade_N${n}_rep${r}.txt"
    echo "$n,$r,$QLS,$IVAZIO,$ICOM,$QINO,$AGORA" >> "$CSV"
    echo "N=$n rep=$r -> ls: $QLS | inodes: $QINO"
  done
done
echo; column -s, -t "$CSV" 2>/dev/null || cat "$CSV"
