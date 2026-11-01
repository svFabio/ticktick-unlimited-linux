.PHONY: patch revert status

patch:
	./patch.sh

revert:
	./revert.sh

status:
	@which ticktick && echo "TickTick instalado" || echo "TickTick NO instalado"
	@ls /tmp/ticktick-asar-backup-*.asar 2>/dev/null | tail -1 || echo "Sin backup"