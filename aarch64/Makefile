CC := $(CROSS_COMPILE)gcc
AR := $(CROSS_COMPILE)ar

OBJS := start.o cache.o vectors.o platform.o

LIBNAME = libarch.a

%.o: %.c
	$(CC) $(CFLAGS) -o $@ -c $<

%.o: %.S
	$(CC) $(CFLAGS) -o $@ -c $<

$(LIBNAME): $(OBJS)
	$(AR) rcsTP $(LIBNAME) $(OBJS)

clean:
	rm -f $(OBJS) $(LIBNAME)
