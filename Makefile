%.obj : %.asm
	nasm -g -f win64 -o $@ $<

%.exe : %.obj
	ld -L C:\Windows\System32 -e Start $< -lkernel32 -luser32 -o $@

%.exe : %.c
	gcc -g -o $@ $<

.PHONY: clean
clean:
	del *.obj
	del *.exe
