#include<stdlib.h>
#include<stdbool.h>

//kvec.h start

#define KV_INITIAL_VALUE  ({ .size = 0, .capacity = 0 })

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
typedef const char* String;

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

struct object {
  ObjectType type;
  union {
    Boolean boolean;
    Integer integer;
    Float floating;
    String string;
    Array array;
    Dictionary dictionary;
    LuaRef luaref;
  } data;
};



typedef int Window;

extern int name_to_color(const unsigned char *name, int *idx);

extern Integer nvim_win_get_height(Window window, Error *err);

extern ArrayOf(Integer, 2) nvim_win_get_cursor(Window window, Error *err);
extern void nvim_win_set_cursor(Window window, ArrayOf(Integer, 2) pos, Error *err);


// typedef void* lua_State;

extern void **get_global_lstate(void);

