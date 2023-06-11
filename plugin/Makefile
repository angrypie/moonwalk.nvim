all: translate-c build-lib

translate-c:
	zig translate-c api.c > api.zig
build-lib:
	zig build-lib ./main.zig -dynamic -fallow-shlib-undefined -fPIC
