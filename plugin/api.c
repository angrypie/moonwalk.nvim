#include<stdlib.h>
#include<stdbool.h>

//kvec.h start

#define KV_INITIAL_VALUE { .size = 0, .capacity = 0, .items = NULL }

#define kvec_t(type) \
  struct { \
    size_t size; \
    size_t capacity; \
    type *items; \
  }

#define kv_init(v) ((v).size = (v).capacity = 0, (v).items = 0)
#define kv_destroy(v) \
  do { \
    xfree((v).items); \
    kv_init(v); \
  } while (0)
#define kv_A(v, i) ((v).items[(i)])
#define kv_pop(v) ((v).items[--(v).size])
#define kv_size(v) ((v).size)
#define kv_max(v) ((v).capacity)
#define kv_Z(v, i) kv_A(v, kv_size(v) - (i) - 1)
#define kv_last(v) kv_Z(v, 0)
//kvec.h end

typedef bool Boolean;
typedef int64_t Integer;
typedef double Float;
typedef int LuaRef;
typedef void* lua_State;
typedef const char* String;
typedef int Window;
typedef int Buffer;

typedef enum {
  kErrorTypeNone = -1,
  kErrorTypeException,
  kErrorTypeValidation,
} ErrorType;

typedef struct {
  ErrorType type;
  char *msg;
} Error;
#define ERROR_INIT ((Error) { .type = kErrorTypeNone  })

typedef struct key_value_pair KeyValuePair;
typedef kvec_t(KeyValuePair) Dictionary;
typedef kvec_t(KeyValuePair) Dict;
#define Dict(name) KeyDict_##name

typedef struct {
  Boolean err;
  Boolean verbose;
} Dict(echo_opts);


typedef uint64_t OptionalKeys;

typedef struct {
  OptionalKeys is_set__get_extmark_;
  Boolean details;
  Boolean hl_name;
} Dict(get_extmark);



typedef enum {
  kObjectTypeNil = 0,
  kObjectTypeBoolean,
  kObjectTypeInteger,
  kObjectTypeFloat,
  kObjectTypeString,
  kObjectTypeArray,
  kObjectTypeDictionary,
  kObjectTypeLuaRef,
  // EXT types, cannot be split or reordered, see #EXT_OBJECT_TYPE_SHIFT
  kObjectTypeBuffer,
  kObjectTypeWindow,
  kObjectTypeTabpage,
} ObjectType;

typedef struct object Object;
typedef kvec_t(Object) Array;
#define ArrayOf(...) Array

union Data {
	Boolean boolean;
	Integer integer;
	Float floating;
	String string;
	Array array;
	Dictionary dictionary;
	LuaRef luaref;
};


struct object {
  ObjectType type;
	union Data data;
};

typedef struct {
  char *cur_blk;
  size_t pos, size;
} Arena;

/// Mask for all internal calls
#define INTERNAL_CALL_MASK (((uint64_t)1) << (sizeof(uint64_t) * 8 - 1))

/// Internal call from VimL code
#define VIML_INTERNAL_CALL INTERNAL_CALL_MASK

/// Internal call from lua code
#define LUA_INTERNAL_CALL (VIML_INTERNAL_CALL + 1)


//Working with Zig
extern int name_to_color(const unsigned char *name, int *idx);
extern Integer nvim_win_get_height(Window window, Error *err);
extern ArrayOf(Integer, 2) nvim_win_get_cursor(Window window, Arena *arena,  Error *err);
extern void nvim_win_set_cursor(Window window, ArrayOf(Integer, 2) pos, Error *err);
extern String nvim_buf_get_name(Buffer buffer, Error *err);
extern ArrayOf(Integer) nvim_buf_get_extmark_by_id(Buffer buffer, Integer ns_id, Integer id, Dict(get_extmark) *opts, Arena *arena, Error *err);
extern void nvim_err_writeln(String str);

//working on now







//in process but still not working still

extern void nvim_echo(Array chunks, Boolean history, Dict(echo_opts) *opts, Error *err);
extern Object nvim_notify(String msg, Integer log_level, Dict opts, Arena *arena, Error *err);





// testing
extern ArrayOf(String) nvim_buf_get_lines( uint64_t channel_id, Buffer buffer, Integer start, Integer end, Boolean strict_indexing, Arena *arena, lua_State *lstate, Error *err);

extern void **get_global_lstate(void);
extern void arena_alloc_block(Arena *arena);
// extern Object nvim_exec_lua(String code, Array args, Arena *arena, Error *err);



