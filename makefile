
ifndef VERBOSE
.SILENT:
endif

a.bin: dino.asm
	nasm -f bin -l dino.lst -o $@ $<

.PHONY: run count monitor floppy clean diff count_confirm

diff: a.bin
	cut -b17- dino.lst > dino.lst.new
	-[ -f dino.lst.old ] && diff -U1 dino.lst.old dino.lst.new
	cp dino.lst.new dino.lst.old

run: a.bin
	qemu-system-x86_64 -drive file=a.bin,format=raw,index=0,media=disk || \
	qemu-system-i386 -drive file=a.bin,format=raw,index=0,media=disk

count: a.bin
	echo -n "SIZE: "; stat -c%s ./a.bin

count_confirm: a.bin
	make -s count | grep -q 512

monitor: a.bin
	qemu-system-x86_64 -monitor stdio \
		-drive file=a.bin,format=raw,index=0,media=disk
	echo

floppy: a.bin
	dd if=/dev/zero of=floppy.img count=1440 bs=1KiB
	dd if=./a.bin of=floppy.img conv=notrunc

clean:
	rm -f a.bin dino.lst
