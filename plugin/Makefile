all: translate-c build-lib

translate-c:
	zig translate-c api.c > nvim_c_api.zig
build-lib:
	zig build-lib ./main.zig -dynamic -fallow-shlib-undefined -fPIC -Denable-llvm=false
