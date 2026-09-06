/*  blis.x -- Owned BLIS objects and mutable non-owning views.

    BlisObject owns one obj_t descriptor and either owns the BLIS-allocated
    numerical buffer or retains the root object whose buffer it views.
*/

#include "blis-21.h"

typedef enum Blis {
  BLIS_NAMESPACE
} Blis;

typedef struct BlisObject *BlisObject;

protocol Blis(T) {
  T T.add(T, T);
  T T.sub(T, T);
  T T.mul(T, T);
  T T.neg(T);
}

#pragma private

#include <math.h>
#include <string.h>

struct BlisObject {
  obj_t native;
  BlisObject owner;
  ulong generation;
  ulong owner_generation;
  int owns_buffer;
  int released;
  int transposed;
  int row_offset;
  int column_offset;
  void *scoped_buffer;
};

static void _blis_bad_state(String operation, String reason) {
  raise %(bad-state (library "BLIS") (operation $operation) (reason $reason));
}

static void _blis_bad_type(String operation, num_t storage) {
  int datatype = storage;
  raise %(bad-types (library "BLIS") (operation $operation)
          (want "BLIS_FLOAT or BLIS_DOUBLE") (datatype $datatype));
}

static void _blis_precision_mismatch(
  String operation, num_t destination, num_t source) {
  int destination_datatype = destination, source_datatype = source;
  raise %(bad-types (library "BLIS") (operation $operation)
          (reason "storage precisions differ")
          (dest-type $destination_datatype)
          (src-type $source_datatype));
}

static double _blis_numeric_value(Var value, String operation) {
  Var converted = value.convert(<f64>);
  if (converted is not <f64> || !isfinite(converted.double())) {
    Symbol tag = converted.tag();
    raise %(bad-arg (library "BLIS") (operation $operation)
            (want "finite numeric value") (tag $tag));
  }
  return converted.double();
}

static void _blis_bad_shape(
  String operation, int left_rows, int left_columns, int right_rows,
  int right_columns) {
  raise %(bad-arg (library "BLIS") (operation $operation)
          (reason "incompatible dimensions")
          (left-rows $left_rows) (left-cols $left_columns)
          (right-rows $right_rows) (right-cols $right_columns));
}

static void _blis_bad_index(
  String operation, int row, int column, int rows, int columns) {
  raise %(bad-arg (library "BLIS") (operation $operation)
          (reason "index outside the object")
          (row $row) (column $column)
          (rows $rows) (columns $columns));
}

static int _blis_supported_storage(num_t storage) {
  return storage == BLIS_FLOAT || storage == BLIS_DOUBLE;
}

static void _blis_live(BlisObject object, String operation) {
  if (!object) {
    _blis_bad_state(operation, %"null BlisObject");
  }
  BlisObject owner = object.owner ? object.owner : object;
  if (owner.released || object.owner_generation != owner.generation) {
    _blis_bad_state(operation, %"released owner or invalidated view");
  }
}

static BlisObject _blis_owned(
  num_t storage, int rows, int columns, String operation) {
  if (!_blis_supported_storage(storage)) {
    _blis_bad_type(operation, storage);
  }
  if (rows < 0 || columns < 0) {
    _blis_bad_shape(operation, rows, columns, 0, 0);
  }

  BlisObject object = Scope.calloc(1, sizeof(struct BlisObject));
  bli_obj_create(storage, (dim_t) rows, (dim_t) columns, 0, 0, &object.native);
  object.owner = object;
  object.generation = 1;
  object.owner_generation = 1;
  object.owns_buffer = 1;
  return object;
}

static BlisObject _blis_scoped(
  num_t storage, int rows, int columns, String operation) {
  if (!_blis_supported_storage(storage)) {
    _blis_bad_type(operation, storage);
  }
  if (rows < 0 || columns < 0) {
    _blis_bad_shape(operation, rows, columns, 0, 0);
  }

  BlisObject object = Scope.calloc(1, sizeof(struct BlisObject));
  size_t count = (size_t) rows * (size_t) columns;
  size_t width = storage == BLIS_FLOAT ? sizeof(float) : sizeof(double);
  object.scoped_buffer = Scope.calloc(count ? count : 1, width);
  bli_obj_create_with_attached_buffer(
    storage, (dim_t) rows, (dim_t) columns, object.scoped_buffer,
    1, (inc_t) rows, &object.native
  );
  object.owner = object;
  object.generation = 1;
  object.owner_generation = 1;
  object.owns_buffer = 1;
  return object;
}

static BlisObject _blis_view(BlisObject source) {
  BlisObject view = Scope.calloc(1, sizeof(struct BlisObject));
  view.owner = source.owner;
  view.owner_generation = source.owner.generation;
  view.transposed = source.transposed;
  view.row_offset = source.row_offset;
  view.column_offset = source.column_offset;
  return view;
}

static int _blis_sequence_length(Var values, String operation) {
  if (values is <null>) return 0;
  if (values is <list>) return values.list().len();
  if (values is <array>) return values.array().len();
  Symbol tag = values.tag();
  raise %(bad-types (library "BLIS") (operation $operation)
          (want "List or Array") (tag $tag));
}

static Var _blis_sequence_value(Var values, int index) {
  return values is <list> ? values.list()[index] : values.array()[index];
}

static void _blis_numeric_rows(Var rows, int *columns) {
  *columns = 0;
  int row_count = _blis_sequence_length(rows, %"copy_rows");
  if (!row_count) return;
  Var first = _blis_sequence_value(rows, 0);
  *columns = _blis_sequence_length(first, %"copy_rows");

  for (int row_index = 0; row_index < row_count; row_index++) {
    Var row = _blis_sequence_value(rows, row_index);
    int row_length = _blis_sequence_length(row, %"copy_rows");
    if (row_length != *columns) {
      _blis_bad_shape(
        %"copy_rows", row_count, *columns, row_count, row_length
      );
    }
    for (int column = 0; column < row_length; column++) {
      Var value = _blis_sequence_value(row, column);
      if (!value.is_integer() && !value.is_floating()) {
        Symbol tag = value.tag();
        raise %(bad-types (library "BLIS") (operation "copy_rows")
                (want "numeric values") (tag $tag));
      }
      _blis_numeric_value(value, %"copy_rows");
    }
  }
}

static void _blis_numeric_vector(Var values) {
  int length = _blis_sequence_length(values, %"copy_vector");
  for (int index = 0; index < length; index++) {
    Var value = _blis_sequence_value(values, index);
    if (!value.is_integer() && !value.is_floating()) {
      Symbol tag = value.tag();
      raise %(bad-types (library "BLIS") (operation "copy_vector")
              (want "numeric values") (tag $tag));
    }
    _blis_numeric_value(value, %"copy_vector");
  }
}

static void _blis_scalar(
  double value, num_t storage, obj_t *scalar, float *single, double *wide) {
  if (storage == BLIS_FLOAT) {
    *single = (float) value;
    bli_obj_create_1x1_with_attached_buffer(storage, single, scalar);
  }
  else {
    *wide = value;
    bli_obj_create_1x1_with_attached_buffer(storage, wide, scalar);
  }
}

/*  Bulk read-back walks the numerical buffer directly. bli_getijm behind
    `at` dispatches on datatype and bounds per element, which is the one
    place this wrapper charges per element instead of per operation.
*/
static double _blis_read(void *buffer, num_t storage, inc_t offset) {
  if (storage == BLIS_FLOAT) return (double) ((float *) buffer)[offset];
  return ((double *) buffer)[offset];
}

static int _blis_vector(BlisObject object, String operation) {
  _blis_live(object, operation);
  if (bli_obj_is_vector(&object.native)) return 1;
  _blis_bad_shape(
    operation, object.rows(), object.columns(), object.rows(), 1
  );
}

static void _blis_same_vector_shape(
  BlisObject destination, BlisObject source, String operation) {
  _blis_vector(destination, operation);
  _blis_vector(source, operation);
  if (destination.length() != source.length()) {
    _blis_bad_shape(
      operation, destination.rows(), destination.columns(),
      source.rows(), source.columns()
    );
  }
  num_t destination_storage = bli_obj_dt(&destination.native);
  num_t source_storage = bli_obj_dt(&source.native);
  if (destination_storage != source_storage) {
    _blis_precision_mismatch(operation, destination_storage, source_storage);
  }
}

void Blis.initialize(void) {
  bli_init();
}

void Blis.shutdown(void) {
  bli_finalize();
}

String Blis.version(void) {
  return String.new((char *) bli_info_get_version_str());
}

BlisObject BlisObject.new(num_t storage, int rows, int columns) {
  return _blis_owned(storage, rows, columns, %"new");
}

BlisObject BlisObject.copy_rows(Var rows, num_t storage) {
  int columns = 0;
  _blis_numeric_rows(rows, &columns);
  int row_count = _blis_sequence_length(rows, %"copy_rows");
  BlisObject object = _blis_owned(
    storage, row_count, columns, %"copy_rows"
  );

  for (int row = 0; row < row_count; row++)
    for (int column = 0; column < columns; column++)
      object.put(
        row, column,
        _blis_sequence_value(_blis_sequence_value(rows, row), column)
          .convert(<f64>).double()
      );
  return object;
}

BlisObject BlisObject.copy_vector(Var values, num_t storage) {
  _blis_numeric_vector(values);
  int length = _blis_sequence_length(values, %"copy_vector");
  BlisObject object = _blis_owned(storage, length, 1, %"copy_vector");
  for (int index = 0; index < length; index++)
    object.put(
      index, 0, _blis_sequence_value(values, index).convert(<f64>).double()
    );
  return object;
}

BlisObject BlisObject.free(BlisObject object) {
  if (!object) return NULL;
  if (!object.owns_buffer) {
    _blis_bad_state(%"free", %"a view does not own its numerical buffer");
  }
  if (object.released) return NULL;
  if (object.scoped_buffer) {
    Scope.free(object.scoped_buffer);
    object.scoped_buffer = NULL;
  }
  else {
    bli_obj_free(&object.native);
  }
  memset(&object.native, 0, sizeof(object.native));
  object.released = 1;
  object.generation++;
  return NULL;
}

int BlisObject.rows(BlisObject object) {
  _blis_live(object, %"rows");
  return (int) bli_obj_length(&object.native);
}

/** Returns the borrowed BLIS descriptor, valid until the owner is freed. */
obj_t *BlisObject.native(BlisObject object) {
  _blis_live(object, %"native");
  return &object.native;
}

int BlisObject.columns(BlisObject object) {
  _blis_live(object, %"columns");
  return (int) bli_obj_width(&object.native);
}

int BlisObject.length(BlisObject object) {
  _blis_vector(object, %"length");
  return (int) bli_obj_vector_dim(&object.native);
}

long BlisObject.row_stride(BlisObject object) {
  _blis_live(object, %"row_stride");
  return (long) bli_obj_row_stride(&object.native);
}

long BlisObject.column_stride(BlisObject object) {
  _blis_live(object, %"column_stride");
  return (long) bli_obj_col_stride(&object.native);
}

int BlisObject.row_offset(BlisObject object) {
  _blis_live(object, %"row_offset");
  return object.row_offset;
}

int BlisObject.column_offset(BlisObject object) {
  _blis_live(object, %"column_offset");
  return object.column_offset;
}

int BlisObject.transposed(BlisObject object) {
  _blis_live(object, %"transposed");
  return object.transposed;
}

int BlisObject.is_view(BlisObject object) {
  _blis_live(object, %"is_view");
  return !object.owns_buffer;
}

Symbol BlisObject.orientation(BlisObject object) {
  _blis_live(object, %"orientation");
  int rows = object.rows(), columns = object.columns();
  if (rows == 1 && columns == 1) return <scalar>;
  if (columns == 1) return <column>;
  if (rows == 1) return <row>;
  return <matrix>;
}

String BlisObject.storage_precision(BlisObject object) {
  _blis_live(object, %"storage_precision");
  return bli_obj_dt(&object.native) == BLIS_FLOAT ? %"single" : %"double";
}

String BlisObject.computation_precision(BlisObject object) {
  _blis_live(object, %"computation_precision");
  return bli_obj_comp_prec(&object.native) == BLIS_SINGLE_PREC
    ? %"single" : %"double";
}

BlisObject BlisObject.set_computation_precision(
  BlisObject object, prec_t precision) {
  _blis_live(object, %"set_computation_precision");
  if (precision != BLIS_SINGLE_PREC && precision != BLIS_DOUBLE_PREC) {
    int value = precision;
    raise %(bad-arg (library "BLIS")
            (operation "set_computation_precision")
            (precision $value));
  }
  bli_obj_set_comp_prec(precision, &object.native);
  return object;
}

double BlisObject.at(BlisObject object, int row, int column) {
  _blis_live(object, %"at");
  int rows = object.rows(), columns = object.columns();
  row = x2c_normalize_index(row, rows);
  column = x2c_normalize_index(column, columns);
  if (row < 0 || column < 0) {
    _blis_bad_index(%"at", row, column, rows, columns);
  }
  double real = 0.0, imaginary = 0.0;
  err_t result = bli_getijm(
    (dim_t) row, (dim_t) column, &object.native, &real, &imaginary
  );
  if (result != BLIS_SUCCESS) {
    int code = result;
    raise %(bad-state (library "BLIS") (operation "getijm") (code $code));
  }
  return real;
}

BlisObject BlisObject.put(
  BlisObject object, int row, int column, double value) {
  _blis_live(object, %"put");
  int rows = object.rows(), columns = object.columns();
  row = x2c_normalize_index(row, rows);
  column = x2c_normalize_index(column, columns);
  if (row < 0 || column < 0) {
    _blis_bad_index(%"put", row, column, rows, columns);
  }
  err_t result = bli_setijm(
    value, 0.0, (dim_t) row, (dim_t) column, &object.native
  );
  if (result != BLIS_SUCCESS) {
    int code = result;
    raise %(bad-state (library "BLIS") (operation "setijm") (code $code));
  }
  return object;
}

Array BlisObject.to_rows(BlisObject object) {
  _blis_live(object, %"to_rows");
  num_t storage = bli_obj_dt(&object.native);
  void *buffer = bli_obj_buffer_at_off(&object.native);
  inc_t row_stride = bli_obj_row_stride(&object.native);
  inc_t column_stride = bli_obj_col_stride(&object.native);
  int rows = object.rows(), columns = object.columns();

  Array table = %[];
  table.block().reserve(rows);
  for (int row = 0; row < rows; row++) {
    Array values = %[];
    values.block().reserve(columns);
    for (int column = 0; column < columns; column++)
      values.push(
        _blis_read(buffer, storage, row * row_stride + column * column_stride)
      );
    table.push(values);
  }
  return table;
}

Array BlisObject.to_values(BlisObject object) {
  _blis_vector(object, %"to_values");
  num_t storage = bli_obj_dt(&object.native);
  void *buffer = bli_obj_buffer_at_off(&object.native);
  inc_t stride = bli_obj_vector_inc(&object.native);
  int length = object.length();

  Array values = %[];
  values.block().reserve(length);
  for (int index = 0; index < length; index++)
    values.push(_blis_read(buffer, storage, index * stride));
  return values;
}

BlisObject BlisObject.part(
  BlisObject object, int row, int column, int rows, int columns) {
  _blis_live(object, %"part");
  int source_rows = object.rows(), source_columns = object.columns();
  if (row < 0) row += source_rows;
  if (column < 0) column += source_columns;
  if (rows < 0 || columns < 0 || row < 0 || column < 0 ||
      row > source_rows || column > source_columns ||
      rows > source_rows - row || columns > source_columns - column) {
    _blis_bad_index(%"part", row, column, source_rows, source_columns);
  }

  BlisObject view = _blis_view(object);
  bli_acquire_mpart(
    (dim_t) row, (dim_t) column, (dim_t) rows, (dim_t) columns,
    &object.native, &view.native
  );
  view.row_offset += row;
  view.column_offset += column;
  return view;
}

BlisObject BlisObject.column(BlisObject object, int index) {
  _blis_live(object, %"column");
  int columns = object.columns();
  int normalized = x2c_normalize_index(index, columns);
  if (normalized < 0) {
    _blis_bad_index(%"column", 0, index, object.rows(), columns);
  }
  return object.part(0, normalized, object.rows(), 1);
}

BlisObject BlisObject.transpose_view(BlisObject object) {
  _blis_live(object, %"transpose_view");
  BlisObject view = _blis_view(object);
  bli_obj_alias_to(&object.native, &view.native);
  bli_obj_induce_trans(&view.native);
  view.transposed = !object.transposed;
  int offset = view.row_offset;
  view.row_offset = view.column_offset;
  view.column_offset = offset;
  return view;
}

BlisObject BlisObject.fill(BlisObject object, double value) {
  _blis_live(object, %"fill");
  float single = 0.0f;
  double wide = 0.0;
  obj_t scalar;
  _blis_scalar(value, bli_obj_dt(&object.native), &scalar, &single, &wide);
  bli_setm(&scalar, &object.native);
  return object;
}

BlisObject BlisObject.copy_from(BlisObject destination, BlisObject source) {
  _blis_live(destination, %"copy_from");
  _blis_live(source, %"copy_from");
  if (destination.rows() != source.rows() ||
      destination.columns() != source.columns()) {
    _blis_bad_shape(
      %"copy_from", destination.rows(), destination.columns(),
      source.rows(), source.columns()
    );
  }
  num_t storage = bli_obj_dt(&destination.native);
  num_t source_storage = bli_obj_dt(&source.native);
  if (storage != source_storage) {
    _blis_precision_mismatch(%"copy_from", storage, source_storage);
  }
  bli_copym(&source.native, &destination.native);
  return destination;
}

double BlisObject.dotv(BlisObject left, BlisObject right) {
  _blis_same_vector_shape(left, right, %"dotv");
  num_t storage = bli_obj_dt(&left.native);
  float single = 0.0f;
  double wide = 0.0;
  obj_t result;
  _blis_scalar(0.0, storage, &result, &single, &wide);
  bli_dotv(&left.native, &right.native, &result);
  return storage == BLIS_FLOAT ? single : wide;
}

BlisObject BlisObject.axpyv(
  BlisObject destination, double alpha, BlisObject source) {
  _blis_same_vector_shape(destination, source, %"axpyv");
  num_t storage = bli_obj_dt(&destination.native);
  float single = 0.0f;
  double wide = 0.0;
  obj_t scalar;
  _blis_scalar(alpha, storage, &scalar, &single, &wide);
  bli_axpyv(&scalar, &source.native, &destination.native);
  return destination;
}

double BlisObject.normfv(BlisObject object) {
  _blis_vector(object, %"normfv");
  num_t storage = bli_obj_dt(&object.native);
  float single = 0.0f;
  double wide = 0.0;
  obj_t result;
  _blis_scalar(0.0, storage, &result, &single, &wide);
  bli_normfv(&object.native, &result);
  return storage == BLIS_FLOAT ? single : wide;
}

BlisObject BlisObject.gemm(
  BlisObject destination, double alpha, BlisObject left, BlisObject right,
  double beta) {
  _blis_live(destination, %"gemm");
  _blis_live(left, %"gemm");
  _blis_live(right, %"gemm");
  if (left.columns() != right.rows() ||
      destination.rows() != left.rows() ||
      destination.columns() != right.columns()) {
    _blis_bad_shape(
      %"gemm", left.rows(), left.columns(),
      right.rows(), right.columns()
    );
  }

  num_t destination_storage = bli_obj_dt(&destination.native);
  num_t left_storage = bli_obj_dt(&left.native);
  num_t right_storage = bli_obj_dt(&right.native);
  if (!_blis_supported_storage(destination_storage)) {
    _blis_bad_type(%"gemm", destination_storage);
  }
  if (!_blis_supported_storage(left_storage)) {
    _blis_bad_type(%"gemm", left_storage);
  }
  if (!_blis_supported_storage(right_storage)) {
    _blis_bad_type(%"gemm", right_storage);
  }

  float alpha_single = 0.0f, beta_single = 0.0f;
  double alpha_wide = 0.0, beta_wide = 0.0;
  obj_t alpha_object, beta_object;
  _blis_scalar(
    alpha, destination_storage, &alpha_object,
    &alpha_single, &alpha_wide
  );
  _blis_scalar(
    beta, destination_storage, &beta_object,
    &beta_single, &beta_wide
  );
  bli_gemm(
    &alpha_object, &left.native, &right.native,
    &beta_object, &destination.native
  );
  return destination;
}

BlisObject BlisObject.add(BlisObject left, BlisObject right) {
  _blis_live(left, %"add");
  _blis_live(right, %"add");
  if (left.rows() != right.rows() || left.columns() != right.columns()) {
    _blis_bad_shape(
      %"add", left.rows(), left.columns(),
      right.rows(), right.columns()
    );
  }
  num_t storage = bli_obj_dt(&left.native);
  num_t right_storage = bli_obj_dt(&right.native);
  if (storage != right_storage) {
    _blis_precision_mismatch(%"add", storage, right_storage);
  }
  BlisObject result = _blis_scoped(
    storage, left.rows(), left.columns(), %"add"
  );
  bli_copym(&left.native, &result.native);
  bli_addm(&right.native, &result.native);
  return result;
}

BlisObject BlisObject.sub(BlisObject left, BlisObject right) {
  _blis_live(left, %"sub");
  _blis_live(right, %"sub");
  if (left.rows() != right.rows() || left.columns() != right.columns()) {
    _blis_bad_shape(
      %"sub", left.rows(), left.columns(),
      right.rows(), right.columns()
    );
  }
  num_t storage = bli_obj_dt(&left.native);
  num_t right_storage = bli_obj_dt(&right.native);
  if (storage != right_storage) {
    _blis_precision_mismatch(%"sub", storage, right_storage);
  }
  BlisObject result = _blis_scoped(
    storage, left.rows(), left.columns(), %"sub"
  );
  bli_copym(&left.native, &result.native);
  bli_subm(&right.native, &result.native);
  return result;
}

BlisObject BlisObject.scale(BlisObject object, double alpha) {
  _blis_live(object, %"scale");
  num_t storage = bli_obj_dt(&object.native);
  BlisObject result = _blis_scoped(
    storage, object.rows(), object.columns(), %"scale"
  );
  bli_copym(&object.native, &result.native);
  float single = 0.0f;
  double wide = 0.0;
  obj_t scalar;
  _blis_scalar(alpha, storage, &scalar, &single, &wide);
  bli_scalm(&scalar, &result.native);
  return result;
}

BlisObject BlisObject.neg(BlisObject object) {
  return object.scale(-1.0);
}

BlisObject BlisObject.mul(BlisObject left, BlisObject right) {
  _blis_live(left, %"mul");
  _blis_live(right, %"mul");
  if (left.columns() != right.rows()) {
    _blis_bad_shape(
      %"mul", left.rows(), left.columns(),
      right.rows(), right.columns()
    );
  }
  num_t storage = bli_obj_dt(&left.native);
  num_t right_storage = bli_obj_dt(&right.native);
  if (storage != right_storage) {
    _blis_precision_mismatch(%"mul", storage, right_storage);
  }
  BlisObject result = _blis_scoped(
    storage, left.rows(), right.columns(), %"mul"
  );
  float alpha_single = 0.0f, beta_single = 0.0f;
  double alpha_wide = 0.0, beta_wide = 0.0;
  obj_t alpha, beta;
  _blis_scalar(1.0, storage, &alpha, &alpha_single, &alpha_wide);
  _blis_scalar(0.0, storage, &beta, &beta_single, &beta_wide);
  bli_gemm(&alpha, &left.native, &right.native, &beta, &result.native);
  return result;
}

protocol Blis(BlisObject);
