
ifndef VERBOSE
.SILENT:
endif

main: dino.asm
	nasm -f bin -o a.bin dino.asm

run: dino.asm
	make
	qemu-system-x86_64 -drive file=a.bin,format=raw,index=0,media=disk
	rm ./a.bin

count: dino.asm
	make
	echo -n "SIZE: "; stat -c%s ./a.bin
	rm ./a.bin

monitor: dino.asm
	make
	qemu-system-x86_64 -monitor stdio \
		-drive file=a.bin,format=raw,index=0,media=disk
	echo
	rm ./a.bin
