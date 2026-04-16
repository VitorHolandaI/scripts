#!/bin/bash

# ================= VARIÁVEIS =================
VM_ORIGINAL="100"          # ID da VM original no nó fonte
CLONE_ID="9100"            # ID que a VM terá no destino
TARGET_IP="192.168.X.X"   # IP do nó de destino
TARGET_NODE="pveX"         # Nome do nó de destino
TARGET_MAC="XX:XX:XX:XX:XX:XX"  # MAC para Wake-on-LAN
TARGET_STORAGE="local-btrfs"
SOURCE_NODE=$(hostname)

# --- Configuração de Logs ---
LOG_DIR="/var/log/migracao_vms"
LOG_FILE="$LOG_DIR/migracao_vm${VM_ORIGINAL}_$(date +%Y%m%d).log"
# =============================================

# Garante que a pasta de logs exista
mkdir -p "$LOG_DIR"

# A MÁGICA DO LOG: Tudo abaixo desta linha vai para a tela E para o arquivo de log
exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================="
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Iniciando rotina de migração diária BTRFS"
echo ">>> Arquivo de log: $LOG_FILE"

# PASSO 1: Ligar o nó de destino (Wake-on-LAN)
echo ">>> [Passo 1] Enviando pacote mágico para $TARGET_MAC..."
/usr/sbin/etherwake -i vmbr0 $TARGET_MAC


# PASSO 2: Ping loop (Aguarda a máquina ligar)
echo ">>> [Passo 2] Aguardando $TARGET_NODE ($TARGET_IP) responder ao ping..."
while ! ping -c 1 -W 1 $TARGET_IP &> /dev/null; do
    sleep 5
done
echo ">>> Nó online! Aguardando 30 segundos para os serviços do Proxmox iniciarem..."
sleep 30

# PASSO 3: Limpeza Completa (Remove a cópia antiga se existir)
echo ">>> [Passo 3] Removendo clone antigo ($CLONE_ID)..."

# Limpa no destino (pve2)
ssh root@$TARGET_IP "qm stop $CLONE_ID &>/dev/null; qm destroy $CLONE_ID --destroy-unreferenced-disks 1 --purge 1 &>/dev/null"
# Limpa no local (nó fonte)
qm stop $CLONE_ID &>/dev/null
qm destroy $CLONE_ID --destroy-unreferenced-disks 1 --purge 1 &>/dev/null
# Limpa fantasmas
rm -f /etc/pve/nodes/*/qemu-server/$CLONE_ID.conf
sleep 3

# PASSO 4: A Mágica (Backup ao vivo + Envio via SSH + Restore no BTRFS)
echo ">>> [Passo 4] Criando snapshot e transferindo a VM $VM_ORIGINAL direto para o nó $TARGET_NODE..."
echo ">>> O Proxmox exibirá o progresso abaixo. Aguarde..."

# O vzdump joga os dados no stdout e os logs no stderr (que nosso sistema de logs captura perfeitamente)
if vzdump $VM_ORIGINAL --mode snapshot --dumpdir /tmp --stdout | ssh root@$TARGET_IP "qmrestore - $CLONE_ID --storage $TARGET_STORAGE --force"; then
    echo ">>> SUCESSO ABSOLUTO! A VM foi transferida e recriada perfeitamente no $TARGET_NODE."
    echo ">>> [Passo 4.5] Desabilitando inicialização automática do clone..."
    ssh root@$TARGET_IP "qm set $CLONE_ID --onboot 0"
else
    echo ">>> ERRO CRÍTICO: Falha durante o processo de transferência/restore."
    exit 1
fi

# PASSO 5: Desligar o nó destino (Opcional)
echo ">>> [Passo 5] Desligando o nó de backup ($TARGET_NODE)..."
sleep 5
ssh root@$TARGET_IP "poweroff"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Fim do script."
echo "============================================="
