all: demo plug.so

DEMO_SRC += source/main.c3
DEMO_SRC += source/event.c3
DEMO_SRC += source/instrument.c3
DEMO_SRC += source/queue.c3
DEMO_SRC += source/router.c3
DEMO_SRC += source/types.c3

PLUG_SRC += plugin/plug.c

C3C = c3c
C3FLAGS +=
CFLAGS +=

demo: $(DEMO_SRC) | plug.so
	$(C3C) compile -o $@ $(C3FLAGS) $^

plug.so: $(PLUG_SRC)
	$(CC) -o $@ $(CFLAGS) -fPIC -shared $^
