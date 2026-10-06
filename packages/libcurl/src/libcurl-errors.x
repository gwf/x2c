#pragma once

/* libcurl diagnostic cases. */

macro Stmt $error.curl.native_failed(
  Expr $operation, Expr $native_code, Expr $message, Expr $url,
  Expr $response_code, Expr $effective_url) {
  raise %(io-fail (library "libcurl") (operation ${$operation})
          (code ${$native_code}) (message ${$message}) (url ${$url})
          (http-code ${$response_code})
          (final-url ${$effective_url}));
}

macro Stmt $error.curl.buffer_limit(
  Expr $operation, Expr $channel, Expr $limit, Expr $attempted, Expr $url) {
  raise %(size-limit (library "libcurl") (operation ${$operation})
          (channel ${$channel}) (limit ${$limit}) (attempted ${$attempted})
          (url ${$url}));
}

macro Stmt $error.curl.buffer_alloc(
  Expr $operation, Expr $channel, Expr $attempted, Expr $url) {
  raise %(alloc-fail (library "libcurl")
          (operation ${$operation}) (channel ${$channel})
          (attempted ${$attempted}) (url ${$url}));
}

macro Stmt $error.curl.buffer_overflow(
  Expr $operation, Expr $channel, Expr $url) {
  raise %(size-limit (library "libcurl") (operation ${$operation})
          (channel ${$channel}) (reason "callback size overflow")
          (url ${$url}));
}

macro Stmt $error.curl.header_size(Expr $operation, Expr $length) {
  raise %(size-limit (library "libcurl") (operation ${$operation})
          (length ${$length}));
}

macro Stmt $error.curl.header_nul(Expr $operation) {
  raise %(bad-enc (library "libcurl") (operation ${$operation})
          (reason "HTTP header contains NUL"));
}

macro Stmt $error.curl.cleanup_busy() {
  raise %(bad-state (library "libcurl") (operation "easy_cleanup")
          (reason "easy handle is performing a transfer"));
}

macro Stmt $error.curl.decode_nul() {
  raise %(bad-enc (library "libcurl") (operation "unescape")
          (reason "decoded value contains NUL"));
}

macro Stmt $error.curl.request_busy() {
  raise %(bad-state (library "libcurl") (operation "easy_perform")
          (reason "easy handle is not reentrant"));
}

macro Stmt $error.curl.download_write(Expr $path, Expr $url) {
  raise %(io-fail (library "libcurl") (operation "download")
          (reason "writing the response body failed") (path ${$path})
          (url ${$url}));
}

macro Stmt $error.curl.multi_failed(
  Expr $operation, Expr $code, Expr $message) {
  raise %(io-fail (library "libcurl") (operation ${$operation})
          (code ${$code})
          (message ${$message}));
}

macro Stmt $error.curl.batch_released(Expr $operation) {
  raise %(bad-state (library "libcurl") (operation ${$operation})
          (reason "released or null batch"));
}

macro Stmt $error.curl.batch_index(Expr $index) {
  raise %(bad-arg (library "libcurl") (operation "batch.response")
          (index ${$index}));
}

macro Stmt $error.curl.batch_busy() {
  raise %(bad-state (library "libcurl") (operation "request_all")
          (reason "easy handle is not reentrant"));
}

macro Stmt $error.curl.response_released(Expr $operation) {
  raise %(bad-state (library "libcurl") (operation ${$operation})
          (reason "released or null response"));
}

macro Stmt $error.curl.response_file(Expr $operation, Expr $path) {
  raise %(bad-state (library "libcurl") (operation ${$operation})
          (reason "response body was written to a file")
          (path ${$path}));
}

macro Stmt $error.curl.response_streamed(Expr $operation) {
  raise %(bad-state (library "libcurl") (operation ${$operation})
          (reason "response body was passed to a callback"));
}

macro Stmt $error.curl.body_nul() {
  raise %(bad-enc (library "libcurl") (operation "text")
          (reason "response body contains NUL; use body()"));
}

macro Stmt $error.curl.body_size(Expr $length) {
  raise %(size-limit (library "libcurl") (operation "text")
          (length ${$length}));
}
