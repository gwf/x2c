/*  yyjson.x -- yyjson-backed JSON values for ordinary x2c programs.

    There are two paths on purpose. JsonDocument owns the native document and
    hands out borrowed JsonValue, JsonArray, JsonObject, and JsonMember views,
    which keep object order, duplicate names, and signed, unsigned, or real
    numeric intent. Json.parse and to_x2c convert to ordinary Map and Array
    for callers who accept those semantics, and that conversion is the only
    place the distinctions above are lost.

    This unit is the `yyjson` package entry: `import "yyjson"` reaches every
    name above `#pragma private` as `yyjson__*`. The vendored
    `yyjson-0.12.h` stays public because the options methods take yyjson's
    own flag types.
 */

#include "yyjson-0.12.h"

typedef enum Json {
  JSON_NAMESPACE
} Json;

typedef enum JsonLisp {
  JSONLISP_NAMESPACE
} JsonLisp;

typedef struct JsonDocument *JsonDocument;
typedef struct JsonValue *JsonValue;
typedef struct JsonArray *JsonArray;
typedef struct JsonObject *JsonObject;
typedef List JsonMember;
typedef struct JsonArrayIndex *JsonArrayIndex;
typedef struct JsonObjectIndex *JsonObjectIndex;

typedef struct Boolean {
  unsigned long value;
} *Boolean;

typedef struct JsonNull {
  unsigned long value;
} *NullValue;

protocol Var(Boolean);
protocol Var(NullValue);
protocol Var(JsonValue);

protocol JsonArrayIndex(T) {
  associated Key = int;
  associated Value = JsonValue;

  Value T.getindex(T, Key);
}

protocol JsonObjectIndex(T) {
  associated Key = String;
  associated Value = JsonValue;

  Value T.getindex(T, Key);
}

protocol JsonArrayIndex(JsonArray);
protocol JsonObjectIndex(JsonObject);
protocol Iter(JsonArray);
protocol Iter(JsonObject);

#pragma private

#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define JSON_MAX_DEPTH 512

struct JsonDocument {
  yyjson_doc *native;
};

struct JsonValue {
  JsonDocument document;
  yyjson_val *native;
};

struct JsonArray {
  JsonDocument document;
  yyjson_val *native;
};

struct JsonObject {
  JsonDocument document;
  yyjson_val *native;
};

typedef struct JsonObjectCursor {
  JsonObject object;
  yyjson_obj_iter iterator;
} *JsonObjectCursor;

static struct Boolean _json_false = { 0 };
static struct Boolean _json_true = { 1 };
static struct JsonNull _json_null = { 0 };

/* A package type's Var tag is derived from its prefixed spelling, so the
   package names its own tags with the prefix it compiles under. A compact
   Symbol holds ten characters and `yyjson__` spends eight, so two boxed
   types must differ in the two that remain: this one is `Boolean`, not
   `JsonBool`, which would tie with `JsonValue` at `yyjson__js`. */
Var Boolean.var(Boolean value) {
  return Var.new(<yyjson--bo>, value);
}

Boolean Var.boolean(Var value) {
  return (Boolean) value.pointer();
}

String Boolean.str(Boolean value) {
  return value && value.value ? %"true" : %"false";
}

String Boolean.repr(Boolean value) {
  return value;
}

int Boolean.truth(Boolean value) {
  return value && value.value;
}

unsigned Boolean.hash(Boolean value) {
  return value && value.value ? 0x93f4a65du : 0x3d45c27bu;
}

int Boolean.equal(Boolean left, Boolean right) {
  return left.truth() == right.truth();
}

int Boolean.compare(Boolean left, Boolean right) {
  return left.truth() - right.truth();
}

Var NullValue.var(NullValue value) {
  return Var.new(<yyjson--nu>, value);
}

NullValue Var.nullvalue(Var value) {
  return value is <yyjson--nu> ? (NullValue) value.pointer() : NULL;
}

String NullValue.str(NullValue value) { return %"null"; }
String NullValue.repr(NullValue value) { return %"null"; }
int NullValue.truth(NullValue value) { return value != NULL; }
unsigned NullValue.hash(NullValue value) { return 0x16bc8c2du; }
int NullValue.equal(NullValue left, NullValue right) { return left == right; }
int NullValue.compare(NullValue left, NullValue right) { return 0; }

Var Json.bool(int value) {
  Boolean boolean = value ? &_json_true : &_json_false;
  return boolean;
}

int Json.is_bool(Var value) {
  return value is <yyjson--bo>;
}

int Json.boolean(Var value) {
  if (value is not <yyjson--bo>) {
    Symbol tag = value.tag();
    raise %(bad-types (library "yyjson") (operation "boolean")
            (want "JSON boolean") (tag $tag));
  }
  return value.boolean().truth();
}

static String _json_message(const char *message) {
  return message ? String.new((char *) message) : %"unknown yyjson error";
}

static void _json_read_error(yyjson_read_err *error) {
  unsigned code = error ? error->code : 0;
  ulong offset = error ? (ulong) error->pos : 0;
  String message = _json_message(error ? error->msg : NULL);
  raise %(malformed (library "yyjson") (operation "parse")
          (code $code) (message $message) (offset $offset));
}

static void _json_write_error(yyjson_write_err *error, String operation) {
  unsigned code = error ? error->code : 0;
  String message = _json_message(error ? error->msg : NULL);
  raise %(format (library "yyjson") (operation $operation)
          (code $code) (message $message));
}

static void _json_string_error(String operation) {
  raise %(bad-enc (library "yyjson") (operation $operation)
          (reason "JSON string contains NUL"));
}

static String _json_string(
  const char *bytes, size_t length, String operation) {
  if (length > INT_MAX) {
    ulong size = (ulong) length;
    raise %(size-limit (library "yyjson") (operation $operation)
            (bytes $size));
  }
  if (length && memchr(bytes, '\0', length)) {
    _json_string_error(operation);
  }
  return String.new_len((char *) bytes, (int) length);
}

static Var _json_from_value(yyjson_val *value, unsigned depth) {
  if (!value) return void;
  if (depth > JSON_MAX_DEPTH) {
    raise %(size-limit (library "yyjson") (operation "parse")
            (reason "JSON nesting exceeds client limit")
            (depth $depth));
  }

  if (yyjson_is_null(value)) return (Var) { .u64 = 0 };
  if (yyjson_is_bool(value)) return Json.bool(yyjson_get_bool(value));
  if (yyjson_is_sint(value))
    return Var.box_long_long((long long) yyjson_get_sint(value));
  if (yyjson_is_uint(value))
    return Var.box_ulong_long((unsigned long long) yyjson_get_uint(value));
  if (yyjson_is_real(value)) return Var.new(<f64>, yyjson_get_real(value));
  if (yyjson_is_str(value)) {
    return _json_string(
      yyjson_get_str(value), yyjson_get_len(value), %"parse"
    );
  }
  if (yyjson_is_arr(value)) {
    Array array = Array.new();
    yyjson_arr_iter iter = yyjson_arr_iter_with(value);
    yyjson_val *child = NULL;
    while ((child = yyjson_arr_iter_next(&iter))) {
      Var converted = _json_from_value(child, depth + 1);
      if (converted is void) return void;
      array.push(converted);
    }
    return array;
  }
  if (yyjson_is_obj(value)) {
    Map map = Map.new();
    yyjson_obj_iter iter = yyjson_obj_iter_with(value);
    yyjson_val *key = NULL;
    while ((key = yyjson_obj_iter_next(&iter))) {
      String name = _json_string(
        yyjson_get_str(key), yyjson_get_len(key), %"parse"
      );
      if (!name && yyjson_get_len(key)) return void;
      Var converted = _json_from_value(
        yyjson_obj_iter_get_val(key), depth + 1
      );
      if (converted is void) return void;
      map[name] = converted;
    }
    return map;
  }

  String kind = _json_message(yyjson_get_type_desc(value));
  raise %(bad-types (library "yyjson") (operation "parse") (type $kind));
}

static Var _json_from_mut_value(yyjson_mut_val *value, unsigned depth) {
  if (!value) return void;
  if (depth > JSON_MAX_DEPTH) {
    raise %(size-limit (library "yyjson") (operation "convert")
            (reason "JSON nesting exceeds client limit")
            (depth $depth));
  }

  if (yyjson_mut_is_null(value)) return (Var) { .u64 = 0 };
  if (yyjson_mut_is_bool(value)) return Json.bool(yyjson_mut_get_bool(value));
  if (yyjson_mut_is_sint(value))
    return Var.box_long_long((long long) yyjson_mut_get_sint(value));
  if (yyjson_mut_is_uint(value))
    return Var.box_ulong_long((unsigned long long) yyjson_mut_get_uint(value));
  if (yyjson_mut_is_real(value))
    return Var.new(<f64>, yyjson_mut_get_real(value));
  if (yyjson_mut_is_str(value)) {
    return _json_string(
      yyjson_mut_get_str(value), yyjson_mut_get_len(value),
      %"convert"
    );
  }
  if (yyjson_mut_is_arr(value)) {
    Array array = Array.new();
    yyjson_mut_arr_iter iter = yyjson_mut_arr_iter_with(value);
    yyjson_mut_val *child = NULL;
    while ((child = yyjson_mut_arr_iter_next(&iter))) {
      Var converted = _json_from_mut_value(child, depth + 1);
      if (converted is void) return void;
      array.push(converted);
    }
    return array;
  }
  if (yyjson_mut_is_obj(value)) {
    Map map = Map.new();
    yyjson_mut_obj_iter iter = yyjson_mut_obj_iter_with(value);
    yyjson_mut_val *key = NULL;
    while ((key = yyjson_mut_obj_iter_next(&iter))) {
      String name = _json_string(
        yyjson_mut_get_str(key), yyjson_mut_get_len(key),
        %"convert"
      );
      if (!name && yyjson_mut_get_len(key)) return void;
      Var converted = _json_from_mut_value(
        yyjson_mut_obj_iter_get_val(key), depth + 1
      );
      if (converted is void) return void;
      map[name] = converted;
    }
    return map;
  }

  String kind = _json_message(yyjson_mut_get_type_desc(value));
  raise %(bad-types (library "yyjson") (operation "convert") (type $kind));
}

Var Json.parse_opts(String source, yyjson_read_flag options) {
  if (options & YYJSON_READ_INSITU) {
    raise %(bad-arg (library "yyjson") (operation "parse")
            (reason "in-situ parsing requires the raw API"));
  }
  JsonDocument document = JsonDocument.parse_opts(source, options);
  if (!document) {
    return void;
  }
  defer document.free();
  return document.to_x2c();
}

Var Json.parse(String source) {
  return Json.parse_opts(source, YYJSON_READ_NOFLAG);
}

/*  Reads `path` into ordinary x2c values. This is the converting path, so it
    loses object order, duplicate names, and the signed/unsigned/real
    distinction exactly as Json.parse does. Use JsonDocument.read_file when
    the file's own shape has to survive.
*/
Var Json.read_file_opts(String path, yyjson_read_flag options) {
  JsonDocument document = JsonDocument.read_file_opts(path, options);
  if (!document) {
    return void;
  }
  defer document.free();
  return document.to_x2c();
}

Var Json.read_file(String path) {
  return Json.read_file_opts(path, YYJSON_READ_NOFLAG);
}

static yyjson_mut_val *_json_to_value(
  yyjson_mut_doc *document, Var value, unsigned depth) {
  if (depth > JSON_MAX_DEPTH) {
    raise %(size-limit (library "yyjson") (operation "stringify")
            (reason "x2c value nesting exceeds client limit")
            (depth $depth));
  }
  if (value.is_null()) return yyjson_mut_null(document);
  if (value is <yyjson--bo>)
    return yyjson_mut_bool(document, value.boolean().truth());
  if (value is <string>) {
    String string = value;
    return yyjson_mut_strncpy(document, string, string.len());
  }
  if (value.is_integer()) {
    if (value is <u8> || value is <u16> || value is <u32> ||
        value is <u48> || value is <ulong> || value is <ullong>) {
      uint64_t number = value is <ulong>
        ? (uint64_t) value.ulong_value()
        : value is <ullong>
          ? (uint64_t) value.ulong_long_value()
          : (uint64_t) value.integer();
      return yyjson_mut_uint(document, number);
    }
    int64_t number = value is <llong>
      ? (int64_t) value.long_long_value()
      : (int64_t) value.integer();
    return yyjson_mut_sint(document, number);
  }
  if (value.is_floating()) return yyjson_mut_real(document, value.floating());
  if (value is <array> || value is <list>) {
    yyjson_mut_val *result = yyjson_mut_arr(document);
    if (!result) return NULL;
    if (value is <array>) {
      foreach(Var child, value.array()) {
        yyjson_mut_val *converted = _json_to_value(document, child, depth + 1);
        if (!converted || !yyjson_mut_arr_append(result, converted))
          return NULL;
      }
    }
    else {
      foreach(Var child, value.list()) {
        yyjson_mut_val *converted = _json_to_value(document, child, depth + 1);
        if (!converted || !yyjson_mut_arr_append(result, converted))
          return NULL;
      }
    }
    return result;
  }
  if (value is <map>) {
    yyjson_mut_val *result = yyjson_mut_obj(document);
    if (!result) return NULL;
    foreach(Var (key, child), value.map()) {
      if (key is not <string>) {
        Symbol tag = key.tag();
        raise %(bad-types (library "yyjson") (operation "stringify")
                (want "String object key") (tag $tag));
      }
      String name = key;
      yyjson_mut_val *json_key = yyjson_mut_strncpy(
        document, name, name.len()
      );
      yyjson_mut_val *converted = _json_to_value(document, child, depth + 1);
      if (!json_key || !converted ||
          !yyjson_mut_obj_add(result, json_key, converted)) return NULL;
    }
    return result;
  }

  Symbol tag = value.tag();
  raise %(bad-types (library "yyjson") (operation "stringify") (tag $tag));
}

static yyjson_mut_doc *_json_document(Var value, String operation) {
  yyjson_mut_doc *document = yyjson_mut_doc_new(NULL);
  if (!document) {
    raise %(alloc-fail (library "yyjson") (operation $operation));
  }
  yyjson_mut_val *root = _json_to_value(document, value, 0);
  if (!root) {
    yyjson_mut_doc_free(document);
    raise %(alloc-fail (library "yyjson") (operation $operation));
  }
  yyjson_mut_doc_set_root(document, root);
  return document;
}

String Json.stringify_opts(Var value, yyjson_write_flag options) {
  yyjson_mut_doc *document = _json_document(value, %"stringify");
  defer yyjson_mut_doc_free(document);

  size_t length = 0;
  yyjson_write_err error = { 0 };
  char *bytes = yyjson_mut_write_opts(
    document, options, NULL, &length, &error
  );
  if (!bytes) {
    _json_write_error(&error, %"stringify");
    return NULL;
  }
  defer free(bytes);
  return _json_string(bytes, length, %"stringify");
}

/*  Writes an x2c value to `path` as JSON. Pass
    YYJSON_WRITE_PRETTY_TWO_SPACES for the indented form.
*/
void Json.write_file_opts(Var value, String path, yyjson_write_flag options) {
  yyjson_mut_doc *document = _json_document(value, %"write_file");
  defer yyjson_mut_doc_free(document);

  yyjson_write_err error = { 0 };
  if (!yyjson_mut_write_file(
        path ? path : "", document, options, NULL, &error
      )) {
    _json_write_error(&error, %"write_file");
  }
}

void Json.write_file(Var value, String path) {
  Json.write_file_opts(value, path, YYJSON_WRITE_NOFLAG);
}

String Var.json(Var value) {
  return Json.stringify_opts(value, YYJSON_WRITE_NOFLAG);
}

String Var.pretty_json(Var value) {
  return Json.stringify_opts(value, YYJSON_WRITE_PRETTY_TWO_SPACES);
}

int Var.try_json_pointer(Var value, String pointer, Var *out) {
  if (!out) return 0;
  yyjson_mut_doc *document = _json_document(value, %"pointer");
  defer yyjson_mut_doc_free(document);

  yyjson_ptr_err error = { 0 };
  yyjson_mut_val *found = yyjson_mut_doc_ptr_getx(
    document, pointer ? pointer : "", pointer.len(), NULL, &error
  );
  if (!found) {
    if (error.code == YYJSON_PTR_ERR_NONE ||
        error.code == YYJSON_PTR_ERR_RESOLVE) return 0;
    unsigned code = error.code;
    ulong offset = (ulong) error.pos;
    String message = _json_message(error.msg);
    raise %(bad-arg (library "yyjson") (operation "pointer")
            (code $code) (message $message) (offset $offset)
            (pointer $pointer));
  }
  Var converted = _json_from_mut_value(found, 0);
  if (converted is void) return 0;
  *out = converted;
  return 1;
}

Var Var.json_pointer(Var value, String pointer) {
  Var out;
  return value.try_json_pointer(pointer, &out) ? out : void;
}

Var Var.json_patch(Var value, Var patch) {
  yyjson_mut_doc *document = yyjson_mut_doc_new(NULL);
  if (!document) {
    raise %(alloc-fail (library "yyjson") (operation "patch"));
  }
  defer yyjson_mut_doc_free(document);

  yyjson_mut_val *original = _json_to_value(document, value, 0);
  yyjson_mut_val *operations = _json_to_value(document, patch, 0);
  if (!original || !operations) return void;

  yyjson_patch_err error = { 0 };
  yyjson_mut_val *result = yyjson_mut_patch(
    document, original, operations, &error
  );
  if (!result) {
    unsigned code = error.code;
    ulong index = (ulong) error.idx;
    String message = _json_message(error.msg);
    raise %(bad-arg (library "yyjson") (operation "patch")
            (code $code) (message $message) (index $index));
  }
  return _json_from_mut_value(result, 0);
}

Var Var.json_merge_patch(Var value, Var patch) {
  yyjson_mut_doc *document = yyjson_mut_doc_new(NULL);
  if (!document) {
    raise %(alloc-fail (library "yyjson") (operation "merge_patch"));
  }
  defer yyjson_mut_doc_free(document);

  yyjson_mut_val *original = _json_to_value(document, value, 0);
  yyjson_mut_val *changes = _json_to_value(document, patch, 0);
  if (!original || !changes) return void;
  yyjson_mut_val *result = yyjson_mut_merge_patch(document, original, changes);
  if (!result) {
    raise %(bad-arg (library "yyjson") (operation "merge_patch"));
  }
  return _json_from_mut_value(result, 0);
}

static void _json_document_live(JsonDocument document, String operation) {
  if (document && document.native) return;
  raise %(bad-state (library "yyjson") (operation $operation)
          (reason "freed or null JsonDocument"));
}

static JsonDocument _json_document_wrap(yyjson_doc *native) {
  if (!native) return NULL;
  JsonDocument document = Scope.calloc(1, sizeof(struct JsonDocument));
  document.native = native;
  return document;
}

static JsonValue _json_value_new(JsonDocument document, yyjson_val *native) {
  if (!native) return NULL;
  _json_document_live(document, %"value");
  JsonValue value = Scope.calloc(1, sizeof(struct JsonValue));
  value.document = document;
  value.native = native;
  return value;
}

static void _json_value_live(JsonValue value, String operation) {
  if (!value) {
    raise %(bad-state (library "yyjson") (operation $operation)
            (reason "null JsonValue"));
  }
  _json_document_live(value.document, operation);
}

JsonDocument JsonDocument.parse_opts(String source, yyjson_read_flag options) {
  if (options & YYJSON_READ_INSITU) {
    raise %(bad-arg (library "yyjson") (operation "document parse")
            (reason "in-situ parsing requires the raw API"));
  }
  yyjson_read_err error = { 0 };
  yyjson_doc *native = yyjson_read_opts(
    (char *) (source ? source : ""), source.len(),
    options, NULL, &error
  );
  if (!native) {
    _json_read_error(&error);
    return NULL;
  }
  return _json_document_wrap(native);
}

JsonDocument JsonDocument.parse(String source) {
  return JsonDocument.parse_opts(source, YYJSON_READ_NOFLAG);
}

/*  Reads a document straight from `path` through yyjson, so content that an
    x2c String cannot hold still parses and a failure keeps yyjson's own code,
    message, and byte offset. A missing or unreadable file arrives on the same
    <malformed> channel as malformed content, distinguished by the code.
*/
JsonDocument JsonDocument.read_file_opts(
  String path, yyjson_read_flag options) {
  if (options & YYJSON_READ_INSITU) {
    raise %(bad-arg (library "yyjson") (operation "document read_file")
            (reason "in-situ parsing requires the raw API"));
  }
  yyjson_read_err error = { 0 };
  yyjson_doc *native = yyjson_read_file(
    path ? path : "", options, NULL, &error
  );
  if (!native) {
    _json_read_error(&error);
    return NULL;
  }
  return _json_document_wrap(native);
}

JsonDocument JsonDocument.read_file(String path) {
  return JsonDocument.read_file_opts(path, YYJSON_READ_NOFLAG);
}

JsonDocument JsonDocument.free(JsonDocument document) {
  if (!document) return NULL;
  if (document.native) {
    yyjson_doc_free(document.native);
    document.native = NULL;
  }
  return NULL;
}

yyjson_doc *JsonDocument.native(JsonDocument document) {
  _json_document_live(document, %"native");
  return document.native;
}

JsonValue JsonDocument.root(JsonDocument document) {
  _json_document_live(document, %"root");
  return _json_value_new(document, yyjson_doc_get_root(document.native));
}

Var JsonDocument.to_x2c(JsonDocument document) {
  JsonValue root = document.root();
  return root ? root.to_x2c() : void;
}

Var JsonValue.var(JsonValue value) {
  return Var.new(<yyjson--js>, value);
}

JsonValue Var.jsonvalue(Var value) {
  return value is <yyjson--js> ? (JsonValue) value.pointer() : NULL;
}

yyjson_val *JsonValue.native(JsonValue value) {
  _json_value_live(value, %"native");
  return value.native;
}

String JsonValue.str(JsonValue value) {
  if (!value) return NULL;
  _json_value_live(value, %"str");
  if (yyjson_is_str(value.native)) return value.string();
  return value.json();
}

Symbol JsonValue.kind(JsonValue value) {
  _json_value_live(value, %"kind");
  with value.native {
    if (yyjson_is_null(_)) return <null>;
    if (yyjson_is_bool(_)) return <bool>;
    if (yyjson_is_sint(_)) return <sint>;
    if (yyjson_is_uint(_)) return <uint>;
    if (yyjson_is_real(_)) return <real>;
    if (yyjson_is_str(_)) return <string>;
    if (yyjson_is_arr(_)) return <array>;
    if (yyjson_is_obj(_)) return <object>;
  }
  return <void>;
}

static void _json_value_expect(
  JsonValue value, Symbol want, String operation) {
  _json_value_live(value, operation);
  Symbol actual = value.kind();
  if (actual == want) return;
  raise %(bad-types (library "yyjson") (operation $operation)
          (want $want) (actual $actual));
}

int JsonValue.is_null(JsonValue value) {
  if (!value) return 0;
  _json_value_live(value, %"is_null");
  return yyjson_is_null(value.native);
}

int JsonValue.boolean(JsonValue value) {
  _json_value_expect(value, <bool>, %"boolean");
  return yyjson_get_bool(value.native);
}

long long JsonValue.sint(JsonValue value) {
  _json_value_expect(value, <sint>, %"sint");
  return (long long) yyjson_get_sint(value.native);
}

unsigned long long JsonValue.uint(JsonValue value) {
  _json_value_expect(value, <uint>, %"uint");
  return (unsigned long long) yyjson_get_uint(value.native);
}

double JsonValue.real(JsonValue value) {
  _json_value_expect(value, <real>, %"real");
  return yyjson_get_real(value.native);
}

String JsonValue.string(JsonValue value) {
  _json_value_expect(value, <string>, %"string");
  return _json_string(
    yyjson_get_str(value.native), yyjson_get_len(value.native), %"string"
  );
}

JsonArray JsonValue.array(JsonValue value) {
  _json_value_expect(value, <array>, %"array");
  JsonArray array = Scope.calloc(1, sizeof(struct JsonArray));
  array.document = value.document;
  array.native = value.native;
  return array;
}

JsonObject JsonValue.object(JsonValue value) {
  _json_value_expect(value, <object>, %"object");
  JsonObject object = Scope.calloc(1, sizeof(struct JsonObject));
  object.document = value.document;
  object.native = value.native;
  return object;
}

Var JsonValue.to_x2c(JsonValue value) {
  _json_value_live(value, %"to_x2c");
  return _json_from_value(value.native, 0);
}

int JsonArray.len(JsonArray array) {
  if (!array) return 0;
  _json_document_live(array.document, %"array len");
  return (int) yyjson_arr_size(array.native);
}

JsonValue JsonArray.getindex(JsonArray array, int index) {
  int length = array.len();
  if (index < 0) index += length;
  if (index < 0 || index >= length) return NULL;
  return _json_value_new(
    array.document, yyjson_arr_get(array.native, (size_t) index)
  );
}

static int _json_array_next(Iter iter, Var *out) {
  JsonArray array = iter.obj;
  int index = iter.state.int();
  if (index >= array.len()) return 0;
  JsonValue value = array.getindex(index);
  if (!value) return 0;
  *out = value;
  iter.state = index + 1;
  return 1;
}

Iter JsonArray.iter(JsonArray array, Iter dest) {
  if (!array) return NULL;
  _json_document_live(array.document, %"array iter");
  return dest.init((void *) array, _json_array_next, 0);
}

int JsonObject.len(JsonObject object) {
  if (!object) return 0;
  _json_document_live(object.document, %"object len");
  return (int) yyjson_obj_size(object.native);
}

JsonValue JsonObject.getindex(JsonObject object, String key) {
  if (!object) return NULL;
  _json_document_live(object.document, %"object index");
  yyjson_val *native = yyjson_obj_getn(
    object.native, key ? key : "", key.len()
  );
  return native ? _json_value_new(object.document, native) : NULL;
}

JsonValue JsonObject.require(JsonObject object, String key) {
  JsonValue value = object.getindex(key);
  if (value) return value;
  raise %(bad-arg (library "yyjson") (operation "object require")
          (reason "missing object member") (key $key));
}

static JsonMember _json_member(JsonDocument document, yyjson_val *key) {
  String name = _json_string(
    yyjson_get_str(key), yyjson_get_len(key), %"member key"
  );
  if (!name && yyjson_get_len(key)) return NULL;
  JsonValue value = _json_value_new(document, yyjson_obj_iter_get_val(key));
  return value ? %($name $value) : NULL;
}

static int _json_object_next(Iter iter, Var *out) {
  JsonObjectCursor cursor = iter.obj;
  yyjson_val *key = yyjson_obj_iter_next(&cursor.iterator);
  if (!key) return 0;
  JsonMember member = _json_member(cursor.object.document, key);
  if (!member) return 0;
  *out = member;
  return 1;
}

Iter JsonObject.iter(JsonObject object, Iter dest) {
  if (!object) return NULL;
  _json_document_live(object.document, %"object iter");
  JsonObjectCursor cursor = Scope.calloc(1, sizeof(struct JsonObjectCursor));
  cursor.object = object;
  cursor.iterator = yyjson_obj_iter_with(object.native);
  return dest.init((void *) cursor, _json_object_next, 0);
}

List JsonObject.all(JsonObject object, String key) {
  if (!object) return NULL;
  _json_document_live(object.document, %"object all");
  List values = NULL;
  yyjson_obj_iter iterator = yyjson_obj_iter_with(object.native);
  yyjson_val *native_key = NULL;
  while ((native_key = yyjson_obj_iter_next(&iterator))) {
    size_t length = yyjson_get_len(native_key);
    if (length != (size_t) key.len() ||
        memcmp(yyjson_get_str(native_key), key ? key : "", length))
      continue;
    JsonValue value = _json_value_new(
      object.document, yyjson_obj_iter_get_val(native_key)
    );
    if (!value) return NULL;
    values = cons(value, values);
  }
  return values.reverse();
}

JsonMember Var.jsonmember(Var value) {
  return value is <list> ? (JsonMember) value.list() : NULL;
}

String JsonMember.key(JsonMember member) {
  return member ? member.getindex(0).string() : NULL;
}

JsonValue JsonMember.value(JsonMember member) {
  return member ? member.getindex(1).jsonvalue() : NULL;
}

static String _json_write_document(
  JsonDocument document, yyjson_write_flag options) {
  _json_document_live(document, %"document write");
  size_t length = 0;
  yyjson_write_err error = { 0 };
  char *bytes = yyjson_write_opts(
    document.native, options, NULL, &length, &error
  );
  if (!bytes) {
    _json_write_error(&error, %"document write");
    return NULL;
  }
  defer free(bytes);
  return _json_string(bytes, length, %"document write");
}

String JsonDocument.json(JsonDocument document) {
  return _json_write_document(document, YYJSON_WRITE_NOFLAG);
}

String JsonDocument.pretty_json(JsonDocument document) {
  return _json_write_document(document, YYJSON_WRITE_PRETTY_TWO_SPACES);
}

/*  Writes the document to `path`. Pass YYJSON_WRITE_PRETTY_TWO_SPACES for the
    indented form; the document is returned so a write can chain.
*/
JsonDocument JsonDocument.write_file_opts(
  JsonDocument document, String path, yyjson_write_flag options) {
  _json_document_live(document, %"document write_file");
  yyjson_write_err error = { 0 };
  if (!yyjson_write_file(
        path ? path : "", document.native, options, NULL, &error
      )) {
    _json_write_error(&error, %"document write_file");
  }
  return document;
}

JsonDocument JsonDocument.write_file(JsonDocument document, String path) {
  return document.write_file_opts(path, YYJSON_WRITE_NOFLAG);
}

String JsonValue.json(JsonValue value) {
  _json_value_live(value, %"value write");
  size_t length = 0;
  yyjson_write_err error = { 0 };
  char *bytes = yyjson_val_write_opts(
    value.native, YYJSON_WRITE_NOFLAG, NULL, &length, &error
  );
  if (!bytes) {
    _json_write_error(&error, %"value write");
    return NULL;
  }
  defer free(bytes);
  return _json_string(bytes, length, %"value write");
}

JsonDocument JsonDocument.patch(JsonDocument document, Var patch) {
  _json_document_live(document, %"document patch");
  yyjson_mut_doc *mutable = yyjson_doc_mut_copy(document.native, NULL);
  if (!mutable) {
    raise %(alloc-fail (library "yyjson") (operation "document patch"));
  }
  defer yyjson_mut_doc_free(mutable);

  yyjson_mut_val *operations = _json_to_value(mutable, patch, 0);
  if (!operations) return NULL;
  yyjson_patch_err error = { 0 };
  yyjson_mut_val *result = yyjson_mut_patch(
    mutable, yyjson_mut_doc_get_root(mutable), operations, &error
  );
  if (!result) {
    unsigned code = error.code;
    ulong index = (ulong) error.idx;
    String message = _json_message(error.msg);
    raise %(bad-arg (library "yyjson") (operation "document patch")
            (code $code) (message $message) (index $index));
  }

  yyjson_doc *immutable = yyjson_mut_val_imut_copy(result, NULL);
  if (!immutable) {
    raise %(alloc-fail (library "yyjson") (operation "document patch"));
  }
  return _json_document_wrap(immutable);
}

/*  The Lisp surface uses the converting path, not JsonDocument, so a Lisp
    session holds copied values rather than borrowed document views. False is
    Lisp nil, while null is a package value that remains distinct from false.
    The documented conversion still loses object order, duplicate names, and
    the signed/unsigned/real distinction.
*/

static Var _json_to_lisp(Var value) {
  if (value.is_null()) {
    NullValue null = &_json_null;
    return null;
  }
  if (value is <yyjson--bo> && !value.boolean().truth()) return %();
  if (value is <array>) {
    Array result = Array.new();
    foreach(Var child, value.array()) result.push(_json_to_lisp(child));
    return result;
  }
  if (value is <map>) {
    Map result = Map.new();
    foreach(Var (key, child), value.map())
      result[key] = _json_to_lisp(child);
    return result;
  }
  return value;
}

static Var _json_from_lisp(Var value) {
  if (value is <yyjson--nu>) return Var.null();
  if (value.is_nil()) return Json.bool(0);
  if (value is <array>) {
    Array result = Array.new();
    foreach(Var child, value.array()) result.push(_json_from_lisp(child));
    return result;
  }
  if (value is <map>) {
    Map result = Map.new();
    foreach(Var (key, child), value.map())
      result[key] = _json_from_lisp(child);
    return result;
  }
  if (value is <list>) {
    List result = NULL;
    foreach(Var child, value.list())
      result = cons(_json_from_lisp(child), result);
    return result.reverse();
  }
  return value;
}

$lisp.binding(json_lisp, "json-parse")
static Var _lisp_json_parse(String source) {
  return _json_to_lisp(Json.parse(source));
}

$lisp.binding(json_lisp, "json-stringify")
static String _lisp_json_stringify(Var value) {
  return _json_from_lisp(value).json();
}

$lisp.binding(json_lisp, "json-pretty")
static String _lisp_json_pretty(Var value) {
  return _json_from_lisp(value).pretty_json();
}

$lisp.binding(json_lisp, "json-read-file")
static Var _lisp_json_read_file(String path) {
  return _json_to_lisp(Json.read_file(path));
}

$lisp.binding(json_lisp, "json-write-file")
static Var _lisp_json_write_file(Var value, String path) {
  Json.write_file(_json_from_lisp(value), path);
  return value;
}

$lisp.binding(json_lisp, "json-pointer")
static Var _lisp_json_pointer(Var value, String pointer) {
  Var found;
  if (_json_from_lisp(value).try_json_pointer(pointer, &found))
    return _json_to_lisp(found);
  return %();
}

$lisp.binding(json_lisp, "json-null?")
static Var _lisp_json_null(Var value) {
  if (value is <yyjson--nu>) return <true>;
  return %();
}

/*  A parsed array is an x2c Array and a parsed object is a Map, so Lisp's own
    car, cdr, and length do not apply to them. These three read the pair
    directly, and json-list crosses an array into the List that Lisp does
    operate on.
*/

$lisp.binding(json_lisp, "json-len")
static int _lisp_json_len(Var value) {
  if (value is Array) return value.array().len();
  if (value is Map) return value.map().len();
  if (value is String) return value.string().len();
  Symbol tag = value.tag();
  raise %(bad-types (library "yyjson") (operation "json-len") (tag $tag));
}

$lisp.binding(json_lisp, "json-keys")
static List _lisp_json_keys(Var value) {
  if (value is not Map) {
    Symbol tag = value.tag();
    raise %(bad-types (library "yyjson") (operation "json-keys") (tag $tag));
  }
  List keys = NULL;
  foreach(Var (key, child), value.map()) keys = cons(key, keys);
  return keys.reverse();
}

$lisp.binding(json_lisp, "json-list")
static List _lisp_json_list(Var value) {
  if (value is not Array) {
    Symbol tag = value.tag();
    raise %(bad-types (library "yyjson") (operation "json-list") (tag $tag));
  }
  List items = NULL;
  foreach(Var item, value.array()) items = cons(item, items);
  return items.reverse();
}

/*  Installs json-parse, json-stringify, json-pretty, json-read-file,
    json-write-file, json-pointer, json-null?, json-len, json-keys, and
    json-list into `lisp`. Malformed input raises out of the binding as the
    same <malformed> an x2c caller would see.
*/
void JsonLisp.install(Lisp lisp) {
  $lisp.install(lisp, json_lisp);
}
