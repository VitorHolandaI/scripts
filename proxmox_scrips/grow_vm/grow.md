adicionado espaco de vm

No terminal do Proxmox (host):
qm resize 104 scsi0 +20G

Dentro da VM:

sudo growpart /dev/sda 3

sudo resize2fs /dev/sda3

df -h /
