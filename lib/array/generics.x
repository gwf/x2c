/*  generics.x -- fixed-width Array family generation

    Copyright (c) 2026 Gary William Flake

    The core family generates storage and sequence algorithms that do not
    depend on an element's missing-value, update, boxing, or rendering
    policy. Array and the typed families put their public behavior
    around these generated element operations.

    The typed family's bracket members are inline native indexing on a
    concrete element pointer, without a null test, index normalization, or a
    bounds test. An index outside the elements is undefined as it is for the
    equivalent C pointer. `try_get` is the checked read.

    Compound update is native too. A float element has no `%` and no bitwise
    operators, so compound update is defined in separate update macros instead
    of the typed family. Numeric families use generated C operators; C
    promotions and conversions determine their results.
*/

/*  Generates `postfixindex` for an element family whose `updateindex`
    applies `+` and `-`.
*/
macro Unit $array.typed.postfix(Type $array, Type $element) {
  inline $element $array.postfixindex($array, int, Symbol);

  /** Applies `++` or `--` at raw `index` and returns the previous value.
      The index has the unchecked C-pointer preconditions of bracket access.
      Raises: `<bad-op>` for another operator. The failure does not return.
  */
  inline $element $array.postfixindex($array array, int index, Symbol op) {
    $element old = array[index];
    if (op == <++>) array[index] += 1;
    else if (op == <-->) array[index] -= 1;
    // no owner detail: a String literal here would put a lazy interning
    // guard at the top of every increment
    else raise %(bad-op (op $op));
    return old;
  }
}

/*  Generates `updateindex` and `postfixindex` for a signed integer element.
    The same-width unsigned type `$unsigned` holds raw operands and results.
    The C operators apply integer promotions, so this does not
    promise narrow-width wrapping. Division and shift raise before storing
    anything, so a failed update leaves the element as it was.
*/
macro Unit $array.typed.update.integer(
  Type $family, Type $element, Type $unsigned
) {
  inline $element $family.updateindex($family, int, Symbol, $element);

  /** Applies integer `op` to raw element `index` and returns the stored value.
      The index has the unchecked C-pointer preconditions of bracket access.
      Arithmetic follows the generated C operators, integer promotions, and
      result conversion. A failing operation leaves the element unchanged.
      Raises: `<div-zero>`, `<bad-shift>`, or `<bad-op>` for its corresponding
      invalid operation.
  */
  inline $element $family.updateindex(
    $family array, int index, Symbol op, $element rhs) {
    $element *slot = (($element *) array.bytes) + index;
    $element lhs = *slot;
    $unsigned a = ($unsigned) lhs, b = ($unsigned) rhs, raw;
    switch (op) {
      case <+>: raw = a + b; break;
      case <->: raw = a - b; break;
      case <*>: raw = a * b; break;
      case <&>: raw = a & b; break;
      case <|>: raw = a | b; break;
      case <^>: raw = a ^ b; break;
      case </>: case <%>: {
        if (!rhs) raise %(div-zero (op $op));
        // the one signed pair whose quotient is not representable
        $element floor = ($element) ~(($unsigned) -1 >> 1);
        if (lhs == floor && rhs == -1) raw = op == </> ? ($unsigned) lhs : 0;
        else raw = ($unsigned) (op == </> ? lhs / rhs : lhs % rhs);
        break;
      }
      case <"<<">: case <">>">: {
        int width = (int) (sizeof($element) * 8);
        if (rhs < 0 || (long long) rhs >= width) {
          long long count = rhs;
          raise %(bad-shift (op $op) (count $count) (width $width));
        }
        raw = op == <"<<"> ? a << b : ($unsigned) (lhs >> rhs);
        break;
      }
      default: raise %(bad-op (op $op));
    }
    return *slot = ($element) raw;
  }

  $array.typed.postfix($family, $element);
}

/*  Generates `updateindex` and `postfixindex` for a floating element.
    Only the four arithmetic operators are defined on a float; the rest
    raise `<bad-types>`, matching the boxed path.
*/
macro Unit $array.typed.update.floating(Type $family, Type $element) {
  inline $element $family.updateindex($family, int, Symbol, $element);

  /** Applies a floating arithmetic `op` and returns the stored value.
      The supported operators are `+`, `-`, `*`, and `/`; the raw index has
      the unchecked C-pointer preconditions of bracket access.
      Raises: `<bad-types>` for another operator, before changing the element.
  */
  inline $element $family.updateindex(
    $family array, int index, Symbol op, $element rhs) {
    $element *slot = (($element *) array.bytes) + index;
    switch (op) {
      case <+>: return *slot += rhs;
      case <->: return *slot -= rhs;
      case <*>: return *slot *= rhs;
      case </>: return *slot /= rhs;
    }
    raise %(bad-types (op $op));
  }

  $array.typed.postfix($family, $element);
}

/* Generates String concatenation for compound update. Postfix update has no
   String operation and always raises before touching the array. */
macro Unit $array.typed.update.string(Type $array) {
  inline String $array.updateindex($array, int, Symbol, String);
  inline String $array.postfixindex($array, int, Symbol);

  /** Concatenates `rhs` onto the String at raw `index` and returns the stored
      canonical String. The index has the unchecked C-pointer preconditions of
      bracket access. Raises: `<bad-op>` for any operation other than `+`.
      A failure leaves the element unchanged.
  */
  inline String $array.updateindex(
    $array array, int index, Symbol op, String rhs) {
    if (op != <+>) raise %(bad-op (op $op));
    String *slot = ((String *) array.bytes) + index;
    String result = slot[0] + rhs;
    return slot[0] = result;
  }

  /** Raises `<bad-op>` because String elements have no postfix operation. */
  inline String $array.postfixindex($array array, int index, Symbol op) {
    (void) array; (void) index;
    raise %(bad-op (op $op));
  }
}

/* These unchecked element operations are shared by separate family
   expansions. Their dotted names let typed aliases inherit the base family's
   operations through ordinary method lookup. The `element` qualifier keeps
   each one apart from the public operation that checks and calls it. */

macro Unit $array.core.family(Type $array, Type $element) {
  static int $array.shift_element($array array, $element *out) {
    if (!array.length) return 0;
    size_t n = array.length;
    $element *data = ($element *) array.bytes;
    *out = data[0];
    if (n > 1) memmove(data, data + 1, (n - 1) * sizeof($element));
    array.length = n - 1;
    return 1;
  }

  static int $array.insert_element($array array, int index, $element value) {
    int n = (int) array.length;
    if (index < 0) index += n + 1;
    if (index < 0 || index > n) return 0;
    Block_append((Block) array, &value, 1);
    $element *data = ($element *) array.bytes;
    if (index < n)
      memmove(data + index + 1, data + index, (n - index) * sizeof($element));
    data[index] = value;
    return 1;
  }

  static int $array.remove_element($array array, int index, $element *out) {
    int n = (int) array.length;
    index = x2c_normalize_index(index, n);
    if (index < 0) return 0;
    $element *data = ($element *) array.bytes;
    *out = data[index];
    if (index < n - 1)
      memmove(
        data + index, data + index + 1,
        (n - index - 1) * sizeof($element));
    array.length = n - 1;
    return 1;
  }

  static $array $array.copy_elements($array array) {
    $array copy = ($array) Block_new(sizeof($element));
    Block_append((Block) copy, array.bytes, array.length);
    return copy;
  }

  static $array $array.slice_elements(
    $array array, int start, int end, int step) {
    $array slice = ($array) Block_new(sizeof($element));
    int newlen = x2c_normalize_slice(start, end, step, (int) array.length);
    if (newlen <= 0) return slice;
    if (step == 1) {
      Block_append(
        (Block) slice,
        (unsigned char *) array.bytes + start * sizeof($element), newlen);
      return slice;
    }
    $element *data = ($element *) array.bytes;
    if (step < 0) {
      for (int i = start; i > end; i += step)
        Block_append((Block) slice, data + i, 1);
    }
    else {
      for (int i = start; i < end; i += step)
        Block_append((Block) slice, data + i, 1);
    }
    return slice;
  }

  /* Normalizes `index` in the start domain, where a negative value counts
     from the last element. `splice` names one position this way; the region
     operations normalize a start and a stop together instead, so that their
     `end` means what the same `end` means in a slice. */
  static inline int _normalize_bound($array array, int index) {
    int length = (int) array.length;
    int start = index, stop = index;
    x2c_normalize_slice(start, stop, 1, length);
    return start;
  }

  /* One shared call decides both bounds, so `array[start:end]` and
     `setslice(start, end, ...)` select the same region. A reversed pair is
     swapped. */
  static inline void _normalize_span($array array, int &start, int &end) {
    x2c_normalize_slice(start, end, 1, (int) array.length);
    if (end < start) {
      int tmp = start;
      start = end;
      end = tmp;
    }
  }

  static void $array.replace_elements(
    $array array, int start, int end, $array values) {
    int n = (int) array.length;
    _normalize_span(array, start, end);
    int remove = end - start;
    int insert = values ? (int) values.length : 0;
    int delta = insert - remove;
    auto $array copied = NULL;
    $array source = values;
    if (insert > 0 && values.bytes == array.bytes)
      source = copied = values.copy_elements();
    if (delta > 0) {
      if (delta > INT_MAX - n) {
        size_t size = (size_t) n + (size_t) delta;
        raise %(size-limit (size $size));
      }
      Block_append((Block) array, NULL, delta);
    }
    $element *data = ($element *) array.bytes;
    int tail = n - end;
    if (tail > 0 && delta != 0)
      memmove(data + start + insert, data + end, tail * sizeof($element));
    if (insert > 0)
      memcpy(data + start, source.bytes, insert * sizeof($element));
    if (delta < 0) array.length = n + delta;
  }

  static $array $array.cut_elements($array array, int start, int end) {
    int n = (int) array.length;
    _normalize_span(array, start, end);
    if (start >= end) return ($array) Block_new(sizeof($element));
    $array removed = array.slice_elements(start, end, 1);
    $element *data = ($element *) array.bytes;
    int tail = n - end;
    if (tail > 0)
      memmove(data + start, data + end, tail * sizeof($element));
    array.length = n - (end - start);
    return removed;
  }

  static $array $array.splice_elements(
    $array array, int index, int remove_count, $array values) {
    if (remove_count < 0) remove_count = 0;
    int n = (int) array.length;
    int start = _normalize_bound(array, index);
    long long target = (long long) start + remove_count;
    int end = target > n ? n : (int) target;
    $array removed = array.slice_elements(start, end, 1);
    array.replace_elements(start, end, values);
    return removed;
  }

  static int $array.index_element($array array, $element value) {
    $element *data = ($element *) array.bytes;
    int n = (int) array.length;
    for (int i = 0; i < n; i++) if (data[i] == value) return i;
    return -1;
  }

  static int $array.count_element($array array, $element value) {
    $element *data = ($element *) array.bytes;
    int n = (int) array.length, total = 0;
    for (int i = 0; i < n; i++) if (data[i] == value) total++;
    return total;
  }

  static $array $array.concat_elements($array a, $array b) {
    $array output = a.copy_elements();
    if (b && b.length) Block_append((Block) output, b.bytes, b.length);
    return output;
  }

  static $array $array.reverse_elements($array array) {
    if (array == NULL || array.length < 2) return array;
    $element *data = ($element *) array.bytes;
    for (size_t i = 0, j = array.length - 1; i < j; i++, j--) {
      $element tmp = data[i];
      data[i] = data[j];
      data[j] = tmp;
    }
    return array;
  }

  static int $array.equal_elements($array a, $array b) {
    if ((void *) a == (void *) b) return 1;
    if (a == NULL || b == NULL ||
        a.length != b.length || a.width != b.width) return 0;
    $element *adata = ($element *) a.bytes;
    $element *bdata = ($element *) b.bytes;
    for (size_t i = 0; i < a.length; i++) if (adata[i] != bdata[i]) return 0;
    return 1;
  }
}

macro Unit $array.typed.operations(Type $array, Type $element, Literal $zero,
  Literal $owner, Literal $boxed
) {
  $array $array.new(void);
  int $array.try_next($array array, int &?cursor, $element &?out);
  $element $array.push($array, $element);
  int $array.try_take_last($array array, $element &?out);
  $element $array.take_last($array);
  $element $array.shift($array);
  $element $array.unshift($array, $element);
  $element $array.insert($array, int, $element);
  $element $array.remove($array, int);
  Self $array.copy(Self);
  Self $array.getslice(Self, int, int, int);
  Self $array.setslice(Self, int, int, Self);
  Self $array.remslice(Self, int, int);
  Self $array.splice(Self, int, int, Self);
  int $array.index($array, $element);
  Var $array.find($array, Func);
  Iter $array.iter($array, Iter);
  int $array.contains($array, $element);
  int $array.count($array, $element);
  Self $array.concat(Self, Self);
  Self $array.reverse(Self);
  int $array.equal($array, $array);

  /** Returns a fresh empty array in the active allocation scope.
      Raises: `<alloc-fail>` when storage cannot be allocated.
  */
  $array $array.new(void) {
    return ($array) Block_new(sizeof($element));
  }

  /** Writes the next native element, advances `cursor`, and returns one.
      Initialize the caller-owned cursor to zero. A null argument, negative
      cursor, exhaustion, or an array outside the integer index domain returns
      zero without changing `cursor` or `out`. Structural mutation invalidates
      the cursor.
  */
  int $array.try_next($array array, int &?cursor, $element &?out) {
    if (!cursor) return 0;
    if (!out) return 0;
    if (array == NULL || cursor < 0 || array.length > INT_MAX ||
        cursor >= (int) array.length) {
      if ($boxed && array && cursor >= 0 && array.length > INT_MAX)
        _size_limit($owner, array.length);
      return 0;
    }
    out = (($element *) array.bytes)[cursor];
    cursor += 1;
    return 1;
  }

  /** Appends `value` and returns it.
      Boxed `Array` returns `void` for a null array.
      Raises: `<bad-arg>` for a null typed array, `<void-op>` for a `void`
      value, `<size-limit>` at the integer index limit, or `<alloc-fail>`
      when storage cannot grow.
  */
  $element $array.push($array array, $element value) {
    if (array == NULL) {
      if ($boxed) return $zero;
      _bad_operation($owner, <push>);
    }
    if ($boxed && (Var) value is void) raise %(void-op);
    if (array.length >= INT_MAX) _size_limit($owner, array.length);
    Block_append((Block) array, &value, 1);
    return value;
  }

  /** Removes the last element into `out` and returns one when present.
      A null or empty array, or null `out`, returns zero without writing or
      changing the array.
  */
  int $array.try_take_last($array array, $element &?out) {
    return array != NULL && out ? Block_try_pop((Block) array, &out) : 0;
  }

  /** Removes and returns the last element.
      Boxed `Array` returns `void` for a null or empty array.
      Raises: `<bad-arg>` for a null or empty typed array.
  */
  $element $array.take_last($array array) {
    $element value = $zero;
    if (array.try_take_last(value)) return value;
    if ($boxed) return $zero;
    _bad_operation($owner, <take-last>);
  }

  /** Removes and returns the first element, shifting the remainder left.
      This operation is O(n). Boxed `Array` returns `void` for a null or
      empty array.
      Raises: `<bad-arg>` for a null or empty typed array, or `<size-limit>`
      when the length exceeds the integer index domain in either family.
  */
  $element $array.shift($array array) {
    $element value = $zero;
    if (array && array.length <= INT_MAX && array.shift_element(&value))
      return value;
    if (array && array.length > INT_MAX)
      _size_limit($owner, array.length);
    if ($boxed) return $zero;
    _bad_operation($owner, <shift>);
  }

  /** Inserts `value` at the front and returns it, shifting elements right.
      This operation is O(n).
      Boxed `Array` returns `void` for a null array.
      Raises: `<bad-arg>` for a null typed array, `<void-op>` for a `void`
      value, `<size-limit>` at the integer index limit, or `<alloc-fail>`
      when storage cannot grow.
  */
  $element $array.unshift($array array, $element value) {
    if (array == NULL) {
      if ($boxed) return $zero;
      _bad_operation($owner, <unshift>);
    }
    if ($boxed && (Var) value is void) raise %(void-op);
    if (array.length >= INT_MAX) _size_limit($owner, array.length);
    array.insert_element(0, value);
    return value;
  }

  /** Inserts `value` at normalized `index` and returns it.
      The accepted range includes the position after the last element;
      negative indices are normalized against that wider range.
      Boxed `Array` returns `void` for a null array or out-of-range index
      without mutation.
      Raises: `<bad-arg>` for a null typed array or out-of-range typed-array
      index, `<void-op>` for a `void` value, `<size-limit>` at the integer
      index limit, or `<alloc-fail>` when storage cannot grow.
  */
  $element $array.insert($array array, int index, $element value) {
    if ($boxed) {
      if (array == NULL) return $zero;
      if (array.length > INT_MAX) _size_limit($owner, array.length);
      int n = (int) array.length;
      if (index < 0) index += n + 1;
      if (index < 0 || index > n) return $zero;
      if (n == INT_MAX) _size_limit($owner, n);
      if ((Var) value is void) raise %(void-op);
      array.insert_element(index, value);
      return value;
    }
    if (array == NULL || array.length >= INT_MAX ||
        !array.insert_element(index, value)) {
      if (array && array.length >= INT_MAX)
        _size_limit($owner, array.length);
      size_t size = array ? array.length : 0;
      _bad_index($owner, index, size);
    }
    return value;
  }

  /** Removes and returns the element at normalized `index`.
      Negative indices count from the end; following elements shift left.
      Boxed `Array` returns `void` for a null array or out-of-range index.
      Raises: `<bad-arg>` for a null typed array or out-of-range typed-array
      index, or `<size-limit>` when the length exceeds the integer index
      domain in either family.
  */
  $element $array.remove($array array, int index) {
    $element value = $zero;
    if (array && array.length <= INT_MAX &&
        array.remove_element(index, &value))
      return value;
    if (array && array.length > INT_MAX)
      _size_limit($owner, array.length);
    if ($boxed) return $zero;
    size_t size = array ? array.length : 0;
    _bad_index($owner, index, size);
  }

  /** Returns a fresh packed copy, or NULL for a null array.
      The result has independent mutable storage containing the same stored
      values.
      Raises: `<size-limit>` or `<alloc-fail>` when the copy cannot be
      represented or allocated.
  */
  Self $array.copy(Self array) {
    if (array == NULL) return NULL;
    if (array.length > INT_MAX) _size_limit($owner, array.length);
    return array.copy_elements();
  }

  /** Returns a fresh packed array for normalized `[start:end:step]`.
      A negative `start` counts elements from the end. A negative `end` on a
      forward step counts endpoints from the end: -1 is the length, so
      `[:-1]` is the whole array and `[:-2]` omits the last element. A
      negative `step` walks backward, and its negative `end` names the
      element the slice stops before. The
      [collections guide](../../guide/collections.md#indexing-and-slicing)
      shows the forward rule, which `setslice` and `remslice` share.
      Raises: `<bad-arg>` for a null array or zero step, `<size-limit>` outside
      the integer index domain, or `<alloc-fail>` on allocation failure.
  */
  Self $array.getslice(Self array, int start, int end, int step) {
    if (array == NULL || !step) _bad_step($owner, step);
    if (array.length > INT_MAX) _size_limit($owner, array.length);
    return array.slice_elements(start, end, step);
  }

  /** Replaces the region `array[start:end]` and returns `array`.
      Bounds normalize as slice bounds, so a negative `end` is a stop.
      Reversed bounds are swapped; null `values` deletes the region. Passing
      `array` itself as `values` is supported and copies before mutation.
      Raises: `<bad-arg>` for a null array, `<size-limit>` outside the integer
      index domain, or `<alloc-fail>` while copying self-aliased values or
      growing storage for the replacement. These failures leave `array`
      unchanged.
  */
  Self $array.setslice(Self array, int start, int end, Self values) {
    if (array == NULL) _bad_operation($owner, <setslice>);
    if (array.length > INT_MAX) _size_limit($owner, array.length);
    if (values && values.length > INT_MAX)
      _size_limit($owner, values.length);
    array.replace_elements(start, end, values);
    return array;
  }

  /** Removes the region `array[start:end]` and returns a fresh packed array.
      Bounds normalize as slice bounds, so a negative `end` is a stop.
      Reversed bounds are swapped, and the removed values retain their order.
      Raises: `<bad-arg>` for a null array, `<size-limit>` outside the integer
      index domain, or `<alloc-fail>` on allocation failure.
  */
  Self $array.remslice(Self array, int start, int end) {
    if (array == NULL) _bad_operation($owner, <remslice>);
    if (array.length > INT_MAX) _size_limit($owner, array.length);
    return array.cut_elements(start, end);
  }

  /** Replaces `remove_count` values at normalized `index` and returns them.
      The result is a fresh packed array. A nonpositive count removes nothing;
      null `values` performs deletion, and self-splicing is supported.
      Raises: `<bad-arg>` for a null array, `<size-limit>` outside the integer
      index domain, or `<alloc-fail>` on allocation failure.
  */
  Self $array.splice(Self array, int index, int remove_count, Self values) {
    if (array == NULL) _bad_operation($owner, <splice>);
    if (array.length > INT_MAX) _size_limit($owner, array.length);
    if (values && values.length > INT_MAX)
      _size_limit($owner, values.length);
    return array.splice_elements(index, remove_count, values);
  }

  /** Returns the first index whose native element equals `value`, or -1.
      A null array returns -1; the scan is linear and preserves source order.
      Raises: `<size-limit>` when the length exceeds the integer index domain.
  */
  int $array.index($array array, $element value) {
    if (array == NULL) return -1;
    if (array.length > INT_MAX) _size_limit($owner, array.length);
    return array.index_element(value);
  }

  /** Reports whether a native element equals `value`.
      The scan is linear. Raises: `<size-limit>` when the length exceeds the
      integer index domain.
  */
  int $array.contains($array array, $element value) {
    return array.index(value) != -1;
  }

  /** Returns how many native elements equal `value`.
      A null array returns zero; the scan is linear.
      Raises: `<size-limit>` when the length exceeds the integer index domain.
  */
  int $array.count($array array, $element value) {
    if (array == NULL) return 0;
    if (array.length > INT_MAX) _size_limit($owner, array.length);
    return array.count_element(value);
  }

  /** Returns the first element accepted by `pred`'s ordinary `Var` truth,
      or `void` when absent. A null array or predicate returns `void`.
      Elements are boxed as in iteration; the array and its storage are
      unchanged. Raises: any cause from boxing, `pred`, or its result's truth
      operation.
  */
  Var $array.find($array array, Func pred) {
    if (!array) return void;
    struct Iter storage;
    return array.iter(&storage).find(pred);
  }

  /** Returns a fresh array holding `a` followed by `b`.
      Neither input is modified. A null `a` returns NULL, while a null `b`
      produces an independent copy of `a`.
      Raises: `<size-limit>` or `<alloc-fail>` when the result cannot be
      represented or allocated.
  */
  Self $array.concat(Self a, Self b) {
    if (a == NULL) return NULL;
    if (a.length > INT_MAX) _size_limit($owner, a.length);
    if (b && b.length > INT_MAX - a.length)
      _size_limit($owner, b.length);
    return a.concat_elements(b);
  }

  /** Reverses `array` in place and returns that same array.
      A null or one-element array is returned unchanged.
  */
  Self $array.reverse(Self array) {
    return array.reverse_elements();
  }

  /** Reports elementwise native equality.
      Two null arrays compare equal; one null array or different lengths
      compare unequal.
  */
  int $array.equal($array a, $array b) {
    return a.equal_elements(b);
  }
}

macro Unit $array.core.observe(
  Type $array, Type $element, Name $compare_element
) {
  static int $array.compare_elements($array a, $array b) {
    if ((void *) a == (void *) b) return 0;
    if (a == NULL) return -1;
    if (b == NULL) return 1;
    size_t asz = a.length, bsz = b.length;
    size_t n = asz < bsz ? asz : bsz;
    $element *adata = ($element *) a.bytes;
    $element *bdata = ($element *) b.bytes;
    for (size_t i = 0; i < n; i++) {
      int comparison = $compare_element(adata[i], bdata[i]);
      if (comparison) return comparison;
    }
    if (asz == bsz) return 0;
    return asz < bsz ? -1 : 1;
  }

  static Buffer $array.write_elements(
    $array array, Buffer out, Symbol mode) {
    RenderPath path;
    if (!path.enter(array))
      return out.printf("<array: 0x%012lX>", (long) array);
    defer path.leave();
    $element *data = array ? ($element *) array.bytes : NULL;
    size_t n = array ? array.length : 0;
    out.write("[ ");
    for (size_t i = 0; i < n; i++) {
      Var element = data[i];
      if (mode == <str>) element.write_str(out);
      else element.write_repr(out);
      if (i < n - 1) out.write(", ");
    }
    return out.write(" ]");
  }
}

macro Unit $array.typed.observe(
  Type $family, Type $element, Name $compare_element
) {
  $array.core.observe($family, $element, $compare_element);
  int $family.compare($family, $family);
  String $family.str($family);
  String $family.repr($family);
  Buffer $family.write_str($family, Buffer);
  Buffer $family.write_repr($family, Buffer);

  /** Compares packed Arrays lexicographically with the element family's
      ordering. Identical handles compare equal and NULL sorts first.
  */
  int $family.compare($family a, $family b) {
    return a.compare_elements(b);
  }

  /** Appends the readable packed-Array representation to `out`. */
  Buffer $family.write_repr($family array, Buffer out) {
    return array.write_elements(out, <repr>);
  }

  /** Appends the packed-Array display text to `out`. */
  Buffer $family.write_str($family array, Buffer out) {
    return array.write_elements(out, <str>);
  }

  /** Returns the packed-Array display String. */
  String $family.str($family array) {
    Buffer out = Buffer_new(0);
    array.write_str(out);
    return out.str_free();
  }

  /** Returns the readable packed-Array representation. */
  String $family.repr($family array) {
    Buffer out = Buffer_new(0);
    array.write_repr(out);
    return out.str_free();
  }
}

macro Unit $array.typed.iterate(Type $array, Type $element, Name $unbox) {
  Iter $array.iter($array, Iter);
  static int _next(Iter iter, Var *out) {
    $array array = iter.obj.$unbox();
    int index = iter.state.int();
    $element element;
    if (!array.try_next(index, element)) return 0;
    *out = element;
    iter.state = index;
    return 1;
  }

  /** Initializes `dest` to lazily yield boxed elements in index order.
      Returns `dest`, whose storage is caller-owned. The iterator borrows
      `array` and reads its current storage on each step, so both must remain
      live and mutation can change the remaining traversal. A null `dest`
      returns NULL. A null array, or one longer than the integer index domain,
      is exhausted. A boxed wide element is `Scope`-owned;
      retaining one after a
      pull requires its owning `Scope` to remain live.
      Raises: any cause from boxing an element.
  */
  Iter $array.iter($array array, Iter dest) {
    if (dest == NULL) return NULL;
    if (array == NULL) return Iter_init(dest, void, NULL, 0);
    return Iter_init(dest, array, _next, 0);
  }

}

macro Unit $array.typed.box(Type $family, Type $element, Literal $owner) {
  Array $family.array($family);
  /** Returns a fresh ordinary Array containing boxed elements in source order.
      A null input returns NULL. The typed Array and its storage are unchanged.
      Raises: any cause from boxing or appending an element.
  */
  Array $family.array($family array) {
    if (array == NULL) return NULL;
    if (array.length > INT_MAX) _size_limit($owner, array.length);
    Array boxed = [], result = NULL;
    defer if (result == NULL) Block_free((Block) boxed);
    $element *data = ($element *) array.bytes;
    for (size_t i = 0; i < array.length; i++) {
      Var element = data[i];
      Block_append((Block) boxed, &element, 1);
    }
    return result = boxed;
  }

}

macro Unit $array.typed.publish(Type $array, Type $element, Name $unbox,
  Literal $tag, Name $prepare_export
) {
  Var $array.var($array);
  Block $array.block($array);
  $array Var.$unbox(Var);
  $array Array.$unbox(Array);
  Iter $array.iter($array, Iter);
  static $array $array.export_context($array, Context);

  /** Boxes `array` with its registered packed-array tag without copying.
      The boxed and typed values share the same mutable object identity.
  */
  inline Var $array.var($array array) {
    return Var_new($tag, array);
  }

  /** Views `array` as the same underlying `Block` storage. */
  inline Block $array.block($array array) {
    return (Block) array;
  }

  /** Returns the packed-array pointer carried by `value`.
      `value` must carry this array family's registered tag; the converter
      does not validate the tag before reading its pointer payload.
  */
  inline $array Var.$unbox(Var value) {
    return ($array) value.pointer();
  }

  /** Packs `values` into a fresh array in source order.
      A null input returns NULL. Each element goes through its `Var`
      conversion; the source is unchanged and a failing conversion or
      allocation releases the partial result before transferring its cause.
  */
  $array Array.$unbox(Array values) {
    if (values == NULL) return NULL;
    $array packed = ($array) Block_new(sizeof($element)), result = NULL;
    defer if (result == NULL) packed.free();
    for (size_t i = 0; i < values.length; i++) packed.push(values[i]);
    return result = packed;
  }

  static $array $array.export_context($array array, Context source) {
    if (array == NULL || !source.owns(array)) return array;
    auto $array staged = $prepare_export(array, source);
    if (staged == NULL) {
      source.move_block(array);
      return array;
    }

    source.move_block(array);
    Scope owner = Scope.owner(array), temporary = Scope.owner(staged);
    Scope.move((unsigned char *) staged.bytes - sizeof(Block), &owner);
    Scope.move((unsigned char *) array.bytes - sizeof(Block), &temporary);
    Bytes old_bytes = array.bytes;
    size_t old_length = array.length, old_cap = array.cap;
    array.bytes = staged.bytes;
    array.length = staged.length;
    array.cap = staged.cap;
    *((Block *) ((unsigned char *) array.bytes - sizeof(Block))) = array;
    staged.bytes = old_bytes;
    staged.length = old_length;
    staged.cap = old_cap;
    staged.free();
    staged = NULL;
    return array;
  }

  protocol Block($array);
  protocol Iter($array);
  protocol Var($array) tag $tag;
}

macro Unit $array.typed.checked_reader(
  Type $array, Type $element, Literal $owner
) {
  /** Reads normalized `index` into `out` and reports whether it exists.
      Negative indices count from the end. A null array, null `out`, or
      out-of-range index returns zero without writing; success returns one.
      Raises: `<size-limit>` when the length exceeds the integer index domain.
  */
  int $array.try_get($array array, int index, $element &?out) {
    if (array == NULL) return 0;
    if (!out) return 0;
    if (array.length > INT_MAX) _size_limit($owner, array.length);
    index = x2c_normalize_index(index, (int) array.length);
    if (index < 0) return 0;
    out = (($element *) array.bytes)[index];
    return 1;
  }
}

macro Unit $array.typed.index(Type $array, Type $element) {
  inline $element $array.getindex($array, int);
  inline $element $array.setindex($array, int, $element);
  /** Reads raw `index` with the bounds and null preconditions of a C pointer.
      Negative indices are not normalized. Use `try_get` for a checked read.
  */
  inline $element $array.getindex($array array, int index) {
    return (($element *) array.bytes)[index];
  }
  /** Stores and returns `value` at raw `index`, with C-pointer preconditions.
      Negative indices are not normalized; the caller supplies a valid index.
  */
  inline $element $array.setindex($array array, int index, $element value) {
    return (($element *) array.bytes)[index] = value;
  }
}

macro Unit $array.typed.family(Type $family, Type $element, Literal $zero,
  Literal $owner
) {
  $array.typed.operations($family, $element, $zero, $owner, 0);
  $array.typed.checked_reader($family, $element, $owner);
  $array.typed.index($family, $element);
}
