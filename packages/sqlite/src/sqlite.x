/*  sqlite.x -- SQLite connections, prepared statements, and copied rows */

#include "sqlite-3.h"

typedef struct Database *Database;
typedef struct Statement *Statement;
typedef enum SqliteLisp { SQLITE_LISP_NAMESPACE } SqliteLisp;

protocol Var(Database);
protocol Var(Statement);
protocol Iter(Statement);

#pragma private

#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <string.h>

struct Database {
  sqlite3 *handle;
};

struct Statement {
  Database database;
  sqlite3_stmt *handle;
  int result;
};

/** Boxes a borrowed database wrapper without extending its lifetime. */
Var Database.var(Database database) => Var.new(<sqlite--da>, database);

/** Reads a database wrapper from its registered Var representation. */
Database Var.database(Var value) => (Database)value.pointer();

/** Boxes a borrowed statement wrapper without extending its lifetime. */
Var Statement.var(Statement statement) => Var.new(<sqlite--st>, statement);

/** Reads a statement wrapper from its registered Var representation. */
Statement Var.statement(Var value) => (Statement)value.pointer();

static void _sqlite_error(Database database, String operation, int code) {
  String message = String.new(database && database.handle
    ? sqlite3_errmsg(database.handle) : sqlite3_errstr(code));
  List detail = %((library "SQLite") (operation $operation)
                  (code $code) (message $message));
  if (database && database.handle) {
    int offset = sqlite3_error_offset(database.handle);
    if (offset >= 0) detail = cons(%(offset $offset), detail);
  }
  Error.raise(<bad-state>, detail);
}

static void _sqlite_check(Database database, String operation, int code) {
  if (code != SQLITE_OK) _sqlite_error(database, operation, code);
}

static void _database_live(Database database, String operation) {
  if (database && database.handle) return;
  raise %(bad-state (library "SQLite") (operation $operation)
          (reason "closed or null Database"));
}

static void _statement_live(Statement statement, String operation) {
  if (!statement || !statement.handle)
    raise %(bad-state (library "SQLite") (operation $operation)
            (reason "freed or null Statement"));
  _database_live(statement.database, operation);
}

/** Opens a Scope-owned connection using SQLite's native flags.
    Free prepared statements before closing their borrowed connection.
    The wrapper and native handle are not concurrently usable.
*/
Database Database.open_with(String filename, int flags) {
  if (!filename)
    raise %(bad-arg (library "SQLite") (operation "sqlite3_open_v2")
            (reason "null filename"));
  Database database = Scope.calloc(1, sizeof(struct Database));
  int ready = 0;
  defer if (!ready && database.handle) sqlite3_close_v2(database.handle);
  int code = sqlite3_open_v2(filename, &database.handle, flags, NULL);
  _sqlite_check(database, "sqlite3_open_v2", code);
  _sqlite_check(database, "sqlite3_extended_result_codes",
    sqlite3_extended_result_codes(database.handle, 1));
  ready = 1;
  return database;
}

/** Opens a read/write database, creating the file when absent. */
Database Database.open(String filename) =>
  Database.open_with(filename, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE);

/** Releases the native connection once; NULL and repeated close are harmless.
    Outstanding statements must still be freed, but cannot be used afterward.
*/
Database Database.close(Database database) {
  if (!database || !database.handle) return NULL;
  _sqlite_check(database, "sqlite3_close_v2",
    sqlite3_close_v2(database.handle));
  database.handle = NULL;
  return NULL;
}

/** Borrows the same native connection until close. */
sqlite3 *Database.native(Database database) {
  _database_live(database, "native");
  return database.handle;
}

/** Sets SQLite's busy wait in milliseconds; nonpositive values disable it. */
Database Database.busy_timeout(Database database, int milliseconds) {
  _database_live(database, "sqlite3_busy_timeout");
  _sqlite_check(database, "sqlite3_busy_timeout",
    sqlite3_busy_timeout(database.handle, milliseconds));
  return database;
}

/** Executes a SQL batch, discarding rows. Use prepare for parameters. */
Database Database.execute(Database database, String sql) {
  _database_live(database, "sqlite3_exec");
  _sqlite_check(database, "sqlite3_exec",
    sqlite3_exec(database.handle, sql ? sql : "", NULL, NULL, NULL));
  return database;
}

/** Returns the rows changed by the latest INSERT, UPDATE, or DELETE. */
sqlite3_int64 Database.changes(Database database) {
  _database_live(database, "sqlite3_changes64");
  return sqlite3_changes64(database.handle);
}

/** Returns SQLite's last successful rowid insertion on this connection. */
sqlite3_int64 Database.last_insert_rowid(Database database) {
  _database_live(database, "sqlite3_last_insert_rowid");
  return sqlite3_last_insert_rowid(database.handle);
}

/** Prepares exactly one statement. SQLite parses trailing whitespace/comments.
    The Scope-owned wrapper borrows database; free releases its native handle.
*/
Statement Database.prepare(Database database, String sql) {
  _database_live(database, "sqlite3_prepare_v2");
  Statement statement = Scope.calloc(1, sizeof(struct Statement));
  statement.database = database;
  int ready = 0;
  defer if (!ready && statement.handle) sqlite3_finalize(statement.handle);
  const char *tail = NULL;
  _sqlite_check(database, "sqlite3_prepare_v2",
    sqlite3_prepare_v2(database.handle, sql ? sql : "", -1,
      &statement.handle, &tail));
  if (!statement.handle)
    raise %(bad-arg (library "SQLite") (operation "sqlite3_prepare_v2")
            (reason "expected one SQL statement"));
  while (tail && *tail) {
    sqlite3_stmt *extra = NULL;
    defer if (extra) sqlite3_finalize(extra);
    _sqlite_check(database, "sqlite3_prepare_v2",
      sqlite3_prepare_v2(database.handle, tail, -1, &extra, &tail));
    if (extra)
      raise %(bad-arg (library "SQLite") (operation "sqlite3_prepare_v2")
              (reason "expected one SQL statement"));
  }
  ready = 1;
  return statement;
}

/** Releases the native statement once, without repeating its step error. */
Statement Statement.free(Statement statement) {
  if (statement && statement.handle) {
    sqlite3_finalize(statement.handle);
    statement.handle = NULL;
  }
  return NULL;
}

/** Borrows the native statement until free; reset before wrapper reuse. */
sqlite3_stmt *Statement.native(Statement statement) {
  _statement_live(statement, "native");
  return statement.handle;
}

/** Restarts execution while retaining bindings. A previously reported step
    error is not raised twice; a new deferred reset error still propagates.
*/
Statement Statement.reset(Statement statement) {
  _statement_live(statement, "sqlite3_reset");
  int previous = statement.result;
  int code = sqlite3_reset(statement.handle);
  statement.result = SQLITE_OK;
  if (code != previous)
    _sqlite_check(statement.database, "sqlite3_reset", code);
  return statement;
}

static void _statement_bind(Statement statement, int index, Var value) {
  sqlite3_stmt *native = statement.handle;
  int code;
  String operation;
  if (value.is_null()) {
    operation = "sqlite3_bind_null";
    code = sqlite3_bind_null(native, index);
  }
  else if (value is String) {
    String text = value;
    operation = "sqlite3_bind_text64";
    code = sqlite3_bind_text64(native, index, text ? text : "", text.len(),
      SQLITE_TRANSIENT, SQLITE_UTF8);
  }
  else if (value is Bytes) {
    Bytes bytes = value;
    Block block = bytes;
    sqlite3_uint64 length = (void *)block != NULL
      ? (sqlite3_uint64)block.len() * block.width : 0;
    operation = "sqlite3_bind_blob64";
    code = sqlite3_bind_blob64(native, index,
      (void *)bytes != NULL ? (void *)bytes : (void *)"", length,
      SQLITE_TRANSIENT);
  }
  else {
    X2CVarNumeric numeric;
    Var.numeric_decode(value, &numeric);
    if (numeric.floating) {
      operation = "sqlite3_bind_double";
      double real = (double)numeric.floating_value;
      if (isnan(real) ||
          (isfinite(numeric.floating_value) && !isfinite(real)))
        raise %(conv-range (library "SQLite") (operation $operation)
                (reason "real cannot be represented without loss of kind"));
      code = sqlite3_bind_double(native, index, real);
    }
    else {
      if (numeric.unsigned_value && numeric.raw > LLONG_MAX)
        raise %(conv-range (library "SQLite") (operation "sqlite3_bind_int64")
                (reason "integer exceeds SQLite signed 64-bit range"));
      sqlite3_int64 integer = numeric.unsigned_value
        ? (sqlite3_int64)numeric.raw
        : (sqlite3_int64)Var.signed_from_bits(numeric.raw, numeric.bits);
      operation = "sqlite3_bind_int64";
      code = sqlite3_bind_int64(native, index, integer);
    }
  }
  _sqlite_check(statement.database, operation, code);
}

static void _statement_clear(Statement statement) {
  statement.reset();
  _sqlite_check(statement.database, "sqlite3_clear_bindings",
    sqlite3_clear_bindings(statement.handle));
}

/** Resets and replaces all bindings in SQLite's one-based parameter order. */
Statement Statement.bind(Statement statement, List values) {
  _statement_live(statement, "bind");
  int count = sqlite3_bind_parameter_count(statement.handle);
  if (values.len() != count)
    raise %(bad-arg (library "SQLite") (operation "bind")
            (reason "parameter count mismatch") (count $count));
  _statement_clear(statement);
  int index = 1;
  foreach (Var value, values) _statement_bind(statement, index++, value);
  return statement;
}

/** Resets and replaces all named bindings. Keys are exact SQLite parameter
    names including their :, @, or $ prefix; unnamed/gapped slots are rejected.
*/
Statement Statement.bind_named(Statement statement, Map values) {
  _statement_live(statement, "bind_named");
  int count = sqlite3_bind_parameter_count(statement.handle);
  if (values.len() != count)
    raise %(bad-arg (library "SQLite") (operation "bind_named")
            (reason "parameter count mismatch") (count $count));
  _statement_clear(statement);
  for (int index = 1; index <= count; index++) {
    const char *native_name = sqlite3_bind_parameter_name(
      statement.handle, index);
    Var value;
    if (!native_name || !values.try_get(String.new(native_name), &value))
      raise %(bad-arg (library "SQLite") (operation "bind_named")
              (reason "missing named parameter") (index $index));
    _statement_bind(statement, index, value);
  }
  return statement;
}

/** Copies column names in result order, preserving duplicate names. */
List Statement.columns(Statement statement) {
  _statement_live(statement, "sqlite3_column_name");
  Array names = %[];
  int count = sqlite3_column_count(statement.handle);
  for (int index = 0; index < count; index++) {
    const char *name = sqlite3_column_name(statement.handle, index);
    if (!name)
      _sqlite_error(statement.database, "sqlite3_column_name", SQLITE_NOMEM);
    names.push(String.new(name));
  }
  return names.list_free();
}

static Var _statement_column(Statement statement, int index) {
  sqlite3_stmt *native = statement.handle;
  int type = sqlite3_column_type(native, index);
  switch (type) {
    case SQLITE_NULL: return Var.null();
    case SQLITE_INTEGER: {
      long long value = sqlite3_column_int64(native, index);
      return value;
    }
    case SQLITE_FLOAT: {
      double value = sqlite3_column_double(native, index);
      return value;
    }
  }
  const void *data = type == SQLITE_TEXT
    ? (const void *)sqlite3_column_text(native, index)
    : sqlite3_column_blob(native, index);
  if (!data && sqlite3_errcode(statement.database.handle) == SQLITE_NOMEM)
    _sqlite_error(statement.database,
      type == SQLITE_TEXT ? "sqlite3_column_text" : "sqlite3_column_blob",
      SQLITE_NOMEM);
  int length = sqlite3_column_bytes(native, index);
  if (type == SQLITE_TEXT && (!length || !memchr(data, 0, length)))
    return String.new_len((char *)data, length);
  return Bytes.new(1).append(data, length);
}

static int _statement_step(Statement statement) {
  _statement_live(statement, "sqlite3_step");
  if (statement.result == SQLITE_DONE) return SQLITE_DONE;
  if (statement.result != SQLITE_OK && statement.result != SQLITE_ROW)
    raise %(bad-state (library "SQLite") (operation "sqlite3_step")
            (reason "reset statement after failed execution"));
  statement.result = sqlite3_step(statement.handle);
  if (statement.result != SQLITE_DONE && statement.result != SQLITE_ROW)
    _sqlite_error(statement.database, "sqlite3_step", statement.result);
  return statement.result;
}

/** Advances to a copied positional row; NULL means exhaustion, not SQL NULL.
    Text with embedded NUL and BLOBs are Scope-owned Bytes. Other text is
    String. Rows survive stepping/reset/free, within their x2c value lifetimes.
*/
List Statement.next(Statement statement) {
  if (_statement_step(statement) == SQLITE_DONE) return NULL;
  Array row = %[];
  int count = sqlite3_column_count(statement.handle);
  for (int index = 0; index < count; index++)
    row.push(_statement_column(statement, index));
  return row.list_free();
}

/** Executes to completion, discarding rows. Bind or reset before reusing. */
Statement Statement.execute(Statement statement) {
  while (_statement_step(statement) == SQLITE_ROW) {}
  return statement;
}

static int _statement_next(Iter iterator, Var *out) {
  Statement statement = (Statement)iterator.obj.pointer();
  List row = statement.next();
  if (!row) return 0;
  *out = row;
  return 1;
}

/** Borrows the statement at its current position. No overlapping traversal. */
Iter Statement.iter(Statement statement, Iter dest) {
  _statement_live(statement, "iter");
  return dest.init((void *)statement, _statement_next, 0);
}

/** Runs one callback in a transaction and returns its result. Nested native
    transactions are rejected. The callback must not change transaction state.
    An Error rolls back without replacing that Error with cleanup failures.
*/
Var Database.transaction(Database database, Func callback) {
  _database_live(database, "transaction");
  if (!sqlite3_get_autocommit(database.handle))
    raise %(bad-state (library "SQLite") (operation "transaction")
            (reason "nested transaction"));
  database.execute("BEGIN");
  try {
    Var result = callback();
    database.execute("COMMIT");
    return result;
  }
  catch %(?cause *detail): {
    sqlite3_exec(database.handle, "ROLLBACK", NULL, NULL, NULL);
    Error.raise(cause, detail);
  }
  return void;
}


$lisp.binding(sqlite_lisp, "sqlite-query")
static List _lisp_sqlite_query(String path, String sql, List parameters) {
  Database db = Database.open(path);
  defer db.close();
  Statement statement = db.prepare(sql);
  defer statement.free();
  statement.bind(parameters);
  List rows = NULL;
  foreach (List row, statement) rows = cons(row, rows);
  return rows.reverse();
}

$lisp.binding(sqlite_lisp, "sqlite-execute")
static long long _lisp_sqlite_execute(
  String path, String sql, List parameters) {
  Database db = Database.open(path);
  defer db.close();
  Statement statement = db.prepare(sql);
  defer statement.free();
  statement.bind(parameters);
  statement.execute();
  return db.changes();
}

$lisp.binding(sqlite_lisp, "sqlite-null")
static Var _lisp_sqlite_null(void) => Var.null();

$lisp.binding(sqlite_lisp, "sqlite-null?")
static Var _lisp_sqlite_is_null(Var value) {
  if (value.is_null()) return <true>;
  return %();
}

$lisp.binding(sqlite_lisp, "sqlite-bytes")
static Var _lisp_sqlite_bytes(List octets) {
  Bytes bytes = Bytes.new(1);
  foreach (Var value, octets) {
    if (!value.is_integer() || value < 0 || value > 255)
      raise %(bad-arg (library "SQLite") (operation "sqlite-bytes")
              (value $value));
    unsigned char octet = value.integer();
    bytes = bytes.append(&octet, 1);
  }
  return bytes;
}

$lisp.binding(sqlite_lisp, "sqlite-bytes-list")
static List _lisp_sqlite_bytes_list(Var value) {
  if (value is not Bytes)
    raise %(bad-types (library "SQLite") (operation "sqlite-bytes-list"));
  Bytes bytes = value.bytes();
  Block block = bytes.block();
  if ((void *)block == NULL)
    raise %(bad-arg (library "SQLite") (operation "sqlite-bytes-list"));
  size_t size = block.len() * block.width;
  unsigned char *data = bytes;
  List result = NULL;
  for (size_t i = 0; i < size; i++) result = cons((int) data[i], result);
  return result.reverse();
}

/** Installs query, execute, NULL, and byte operations into `lisp`.
    Queries return Lists of copied positional row Lists. Each call opens and
    closes its own database connection; use a filename to retain changes
    between calls. Returned Bytes belong to the active Scope.
*/
void SqliteLisp.install(Lisp lisp) {
  $lisp.install(lisp, sqlite_lisp);
}
