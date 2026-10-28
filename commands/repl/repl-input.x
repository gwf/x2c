/*  repl-input.x -- inline terminal editing for the x2c REPL

    Derived from Linenoise commit
    a473823d74b93eab2ba83480df16ed37617493f2:
      https://github.com/antirez/linenoise
      linenoise.c sha256
      4bc28faf2a46ccaea11d07aa056e21aa2e9a748b4dc6962346a3f658593103a8
      linenoise.h sha256
      5f94c6295e3b62e0f8b4b62b0a2f351433d0b6b21029607aec0c9abbc60acff7

    ReplInput owns terminal restoration and bounded session history. Each read
    owns its edit buffer, display state, and mutable history view.

    Copyright (c) 2010-2023, Salvatore Sanfilippo
    <antirez at gmail dot com>
    Copyright (c) 2010-2013, Pieter Noordhuis
    <pcnoordhuis at gmail dot com>

    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are
    met:

     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.

     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
    A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
    OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
    SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
    LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
    DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
    THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
    (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
    OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#pragma once
#include "common.x"

/** Owns terminal restoration and this process's bounded REPL history. */
typedef struct ReplInput *ReplInput;

/** `status` is line, eof, or cancelled. `text` is present for line, including
    an accepted empty line. */
typedef struct ReplInputResult {
  Symbol status;
  String text;
} ReplInputResult;

/** Completion candidates are `(kind "spelling")` rows that replace
    `[start,end)` in the edited UTF-8 buffer. */
typedef struct ReplInputCompletion {
  size_t start, end;
  List candidates;
} ReplInputCompletion;

/** Computes completion synchronously from borrowed text and a byte cursor.
    Returned candidates must remain live through the editor's synchronous
    completion handling. */
typedef ReplInputCompletion (*ReplInputComplete)(
  void *context, String text, size_t cursor);

#include <stdint.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

#include "file.x"
#include "scope/scope.x"
#include "string/string.x"

#define REPL_HISTORY_MAX 100
#define LINENOISE_MAX_FOLDS 16

static struct ReplInput {
  Scope storage;
  char **history;
  int history_len, open;
  struct termios original;
  int raw, ifd, ofd;
};

static typedef struct EditState {
  ReplInput input;
  char *buf, **history;
  size_t buflen;
  const char *prompt;
  size_t plen, pos, len, cols, oldrows;
  int oldrpos, history_index, history_len, fold_count;
  ReplInputComplete complete;
  void *completion_context;
  int completion_pending;
  size_t fold_start[LINENOISE_MAX_FOLDS];
  size_t fold_end[LINENOISE_MAX_FOLDS];
} EditState;

#define LINENOISE_MAX_LINE (1024*1024)
#define LINENOISE_INITIAL_BUFLEN 4096
#define PASTE_FOLD_THRESHOLD 200
#define PASTE_FOLD_CONTEXT 8
static const char *unsupported_term[] = {"dumb", "cons25", "emacs", NULL};

// UTF-8 movement and display width

/* Return the number of bytes that compose the UTF-8 character starting at
 * 'c'. This function assumes a valid UTF-8 encoding and handles the four
 * standard byte patterns:
 *   0xxxxxxx -> 1 byte (ASCII)
 *   110xxxxx -> 2 bytes
 *   1110xxxx -> 3 bytes
 *   11110xxx -> 4 bytes */
static int _utf8_byte_len(char c) {
  unsigned char uc = (unsigned char)c;
  if ((uc & 0x80) == 0)    return 1;   /* 0xxxxxxx: ASCII */
  if ((uc & 0xE0) == 0xC0) return 2;   /* 110xxxxx: 2-byte seq */
  if ((uc & 0xF0) == 0xE0) return 3;   /* 1110xxxx: 3-byte seq */
  if ((uc & 0xF8) == 0xF0) return 4;   /* 11110xxx: 4-byte seq */
  return 1; /* Fallback for invalid encoding, treat as single byte. */
}

/* Decode one codepoint without reading beyond the available input. Invalid
 * or incomplete sequences remain independently editable bytes. */
static uint32_t _utf8_decode(const char *s, size_t available, size_t &len) {
  const unsigned char *p = (const unsigned char *)s;
  int expected;

  if (!available) {
    len = 0;
    return 0;
  }
  expected = _utf8_byte_len(*p);
  if (expected == 1 || (size_t)expected > available) {
    len = 1;
    return *p;
  }
  for (int i = 1; i < expected; i++) {
    if ((p[i] & 0xc0) != 0x80) {
      len = 1;
      return *p;
    }
  }

  len = expected;
  if (expected == 2)
    return ((*p & 0x1f) << 6) | (p[1] & 0x3f);
  if (expected == 3)
    return ((*p & 0x0f) << 12) | ((p[1] & 0x3f) << 6) |
           (p[2] & 0x3f);
  return ((*p & 0x07) << 18) | ((p[1] & 0x3f) << 12) |
         ((p[2] & 0x3f) << 6) | (p[3] & 0x3f);
}

/* U+FE0E and U+FE0F select text or emoji presentation. */
static int _is_variation_selector(uint32_t cp) {
  return cp == 0xFE0E || cp == 0xFE0F;  /* Text/emoji style */
}

/* The Fitzpatrick modifiers U+1F3FB through U+1F3FF. */
static int _is_skin_tone_modifier(uint32_t cp) {
  return cp >= 0x1F3FB && cp <= 0x1F3FF;
}

/* U+200D joins emoji into one grapheme. */
static int _is_joiner(uint32_t cp) {
  return cp == 0x200D;
}

/* A pair of these forms one flag emoji. */
static int _is_regional_indicator(uint32_t cp) {
  return cp >= 0x1F1E6 && cp <= 0x1F1FF;
}

/* Also covers other zero-width characters. */
static int _is_combining_mark(uint32_t cp) {
  return (cp >= 0x0300 && cp <= 0x036F) ||   /* Combining Diacriticals */
      (cp >= 0x1AB0 && cp <= 0x1AFF) || /* Diacriticals Extended */
      (cp >= 0x1DC0 && cp <= 0x1DFF) || /* Diacriticals Supplement */
      (cp >= 0x20D0 && cp <= 0x20FF) || /* Diacriticals for Symbols */
      (cp >= 0xFE20 && cp <= 0xFE2F);   /* Combining Half Marks */
}

/* Grapheme extensions stay attached to their preceding codepoint. */
static int _is_grapheme_extension(uint32_t cp) {
  return _is_variation_selector(cp) || _is_skin_tone_modifier(cp) ||
      _is_joiner(cp) || _is_combining_mark(cp);
}

/* Decode the UTF-8 codepoint ending at position 'pos' (exclusive) and
 * return its value. Also sets cplen to the byte length of the codepoint. */
static uint32_t _utf8_decode_previous(
  const char *buf, size_t pos, size_t &cplen) {
  if (pos == 0) {
    cplen = 0;
    return 0;
  }
  /* Scan backwards to find the start byte. */
  size_t i = pos;
  do i--;
  while (i > 0 && (pos - i) < 4 &&
         ((unsigned char)buf[i] & 0xC0) == 0x80);
  cplen = pos - i;
  size_t dummy;
  return _utf8_decode(buf + i, pos - i, dummy);
}

/* Given a buffer and a position, return the byte length of the grapheme
 * cluster before that position. A grapheme cluster includes:
 * - The base character
 * - Any following variation selectors, skin tone modifiers
 * - ZWJ sequences (emoji joined by Zero Width Joiner)
 * - Regional indicator pairs (flag emoji) */
static size_t _previous_grapheme_len(const char *buf, size_t pos) {
  if (pos == 0) return 0;

  size_t total = 0;
  size_t curpos = pos;

  /* First, get the last codepoint. */
  size_t cplen;
  uint32_t cp = _utf8_decode_previous(buf, curpos, cplen);
  if (cplen == 0) return 0;
  total += cplen;
  curpos -= cplen;

  /* If we're at an extending character, we need to find what it extends.
   * Keep going back through the grapheme cluster. */
  while (curpos > 0) {
    size_t prevlen;
    uint32_t prevcp = _utf8_decode_previous(buf, curpos, prevlen);
    if (prevlen == 0) break;

    if (_is_joiner(prevcp)) {
      /* ZWJ joins two emoji. Include the ZWJ and continue to get
       * the preceding character. */
      total += prevlen;
      curpos -= prevlen;
      /* Now get the character before ZWJ. */
      prevcp = _utf8_decode_previous(buf, curpos, prevlen);
      if (prevlen == 0) break;
      total += prevlen;
      curpos -= prevlen;
      cp = prevcp;
      continue;  /* Check if there's more extending before this. */
    } else if (_is_grapheme_extension(cp)) {
      /* Current cp is an extending character; include previous. */
      total += prevlen;
      curpos -= prevlen;
      cp = prevcp;
      continue;
    } else if (_is_regional_indicator(cp) && _is_regional_indicator(prevcp)) {
      /* Regional indicators form one flag pair. */
      total += prevlen;
      curpos -= prevlen;
      break;
    } else break;
  }

  return total;
}

/* Given a buffer, position and total length, return the byte length of the
 * grapheme cluster at the current position. */
static size_t _next_grapheme_len(const char *buf, size_t pos, size_t len) {
  if (pos >= len) return 0;

  size_t total = 0;
  size_t curpos = pos;

  /* Get the first codepoint. */
  size_t cplen;
  uint32_t cp = _utf8_decode(buf + curpos, len - curpos, cplen);
  total += cplen;
  curpos += cplen;

  int regional = _is_regional_indicator(cp);

  /* Consume any extending characters that follow. */
  while (curpos < len) {
    size_t nextlen;
    uint32_t nextcp = _utf8_decode(buf + curpos, len - curpos, nextlen);

    if (_is_joiner(nextcp) && curpos + nextlen < len) {
      /* ZWJ: include it and the following character. */
      total += nextlen;
      curpos += nextlen;
      /* Get the character after ZWJ. */
      nextcp = _utf8_decode(buf + curpos, len - curpos, nextlen);
      total += nextlen;
      curpos += nextlen;
      continue;  /* Check for more extending after the joined char. */
    } else if (_is_grapheme_extension(nextcp)) {
      /* Variation selector, skin tone, combining mark, etc. */
      total += nextlen;
      curpos += nextlen;
      continue;
    } else if (regional && _is_regional_indicator(nextcp)) {
      /* Second regional indicator for a flag pair. */
      total += nextlen;
      curpos += nextlen;
      regional = 0;  /* Only pair once. */
      continue;
    } else break;
  }

  return total;
}

/* Return the display width of a Unicode codepoint. This is a heuristic
 * that works for most common cases:
 * - Control chars and zero-width: 0 columns
 * - Grapheme-extending chars (VS, skin tone, ZWJ): 0 columns
 * - ASCII printable: 1 column
 * - Wide chars (CJK, emoji, fullwidth): 2 columns
 * - Everything else: 1 column
 *
 * This is not a full wcwidth() implementation, but a minimal heuristic
 * that handles emoji and CJK characters reasonably well. */
static int _codepoint_width(uint32_t cp) {
  /* Control characters and combining marks: zero width. */
  if (cp < 32 || (cp >= 0x7F && cp < 0xA0)) return 0;
  if (_is_combining_mark(cp)) return 0;

  /* Grapheme extensions modify the preceding character and take no space. */
  if (_is_variation_selector(cp)) return 0;
  if (_is_skin_tone_modifier(cp)) return 0;
  if (_is_joiner(cp)) return 0;

  /* Wide character ranges - these display as 2 columns:
   * - CJK Unified Ideographs and Extensions
   * - Fullwidth forms
   * - Various emoji ranges */
  if (cp >= 0x1100 &&
    (cp <= 0x115F ||                      /* Hangul Jamo */
     cp == 0x2329 || cp == 0x232A ||      /* Angle brackets */
     (cp >= 0x231A && cp <= 0x231B) ||    /* Watch, Hourglass */
     (cp >= 0x23E9 && cp <= 0x23F3) ||    /* Media controls, clocks */
     (cp >= 0x23F8 && cp <= 0x23FA) ||    /* Pause, stop, record */
     (cp >= 0x25AA && cp <= 0x25AB) ||    /* Small squares */
     (cp >= 0x25B6 && cp <= 0x25C0) ||    /* Play/reverse buttons */
     (cp >= 0x25FB && cp <= 0x25FE) ||    /* Squares */
     (cp >= 0x2600 && cp <= 0x26FF) ||    /* Misc Symbols (sun, cloud, etc) */
     (cp >= 0x2700 && cp <= 0x27BF) ||    /* Dingbats */
     (cp >= 0x2934 && cp <= 0x2935) ||    /* Arrows */
     (cp >= 0x2B05 && cp <= 0x2B07) ||    /* Arrows */
     (cp >= 0x2B1B && cp <= 0x2B1C) ||    /* Squares */
     cp == 0x2B50 || cp == 0x2B55 ||      /* Star, circle */
     (cp >= 0x2E80 && cp <= 0xA4CF &&
     cp != 0x303F) ||                    /* CJK ... Yi */
     (cp >= 0xAC00 && cp <= 0xD7A3) ||    /* Hangul Syllables */
     (cp >= 0xF900 && cp <= 0xFAFF) ||    /* CJK Compatibility Ideographs */
     (cp >= 0xFE10 && cp <= 0xFE1F) ||    /* Vertical forms */
     (cp >= 0xFE30 && cp <= 0xFE6F) ||    /* CJK Compatibility Forms */
     (cp >= 0xFF00 && cp <= 0xFF60) ||    /* Fullwidth Forms */
     (cp >= 0xFFE0 && cp <= 0xFFE6) ||    /* Fullwidth Signs */
     (cp >= 0x1F1E6 && cp <= 0x1F1FF) ||  /* Regional Indicators (flags) */
     (cp >= 0x1F300 && cp <= 0x1F64F) ||  /* Misc Symbols and Emoticons */
     (cp >= 0x1F680 && cp <= 0x1F6FF) ||  /* Transport and Map Symbols */
     (cp >= 0x1F900 && cp <= 0x1F9FF) ||  /* Supplemental Symbols */
     (cp >= 0x1FA00 && cp <= 0x1FAFF) ||  /* Chess, Extended-A */
     (cp >= 0x20000 && cp <= 0x2FFFF)))   /* CJK Extension B and beyond */
    return 2;

  return 1; /* Default: single width */
}

/* If s[] points at an ANSI CSI escape sequence (e.g. a color change like
 * ESC [ 1 ; 32 m), return its length in bytes. Otherwise return 0.
 *
 * The caller must have already verified that s[0] == ESC (0x1b). The
 * sequence layout follows ECMA-48: ESC '[' , parameter bytes (0x30-0x3f),
 * intermediate bytes (0x20-0x2f), and a final byte (0x40-0x7e). */
static size_t _ansi_escape_len(const char *s, size_t len) {
  size_t i;
  if (len < 2 || s[1] != '[') return 0;
  i = 2;
  while (i < len && (unsigned char)s[i] >= 0x30 &&
         (unsigned char)s[i] <= 0x3f) i++;
  while (i < len && (unsigned char)s[i] >= 0x20 &&
         (unsigned char)s[i] <= 0x2f) i++;
  if (i >= len || (unsigned char)s[i] < 0x40 ||
      (unsigned char)s[i] > 0x7e) return 0;
  return i + 1;
}

/* Calculate the display width of a UTF-8 string of 'len' bytes.
 * This is used for cursor positioning in the terminal.
 * Handles grapheme clusters: characters joined by ZWJ contribute 0 width
 * after the first character in the sequence.
 * ANSI CSI escape sequences (e.g. color codes in the prompt) are treated
 * as zero-width. */
static size_t _display_width(const char *s, size_t len) {
  size_t width = 0;
  size_t i = 0;
  int after_zwj = 0;  /* Track if previous char was ZWJ */

  while (i < len) {
    size_t clen;
    uint32_t cp = _utf8_decode(s + i, len - i, clen);

    /* Skip ANSI CSI escape sequences entirely: they produce no
     * glyph, so they must not contribute to the display width.
     * Checked before the ZWJ state so a stray ZWJ immediately
     * followed by ESC cannot swallow the ESC byte. */
    if (cp == 0x1b) {
      size_t skip = _ansi_escape_len(s + i, len - i);
      if (skip > 0) {
        i += skip;
        continue;
      }
    }

    if (after_zwj) after_zwj = 0;
    else width += _codepoint_width(cp);

    /* Check if this is a ZWJ - next char will be joined. */
    if (_is_joiner(cp)) after_zwj = 1;

    i += clen;
  }
  return width;
}

static enum KEY_ACTION {
  KEY_NULL = 0,
  CTRL_A = 1,
  CTRL_B = 2,
  CTRL_C = 3,
  CTRL_D = 4,
  CTRL_E = 5,
  CTRL_F = 6,
  CTRL_H = 8,
  TAB = 9,
  CTRL_K = 11,
  CTRL_L = 12,
  ENTER = 13,
  CTRL_N = 14,
  CTRL_P = 16,
  CTRL_T = 20,
  CTRL_U = 21,
  CTRL_W = 23,
  ESC = 27,
  BACKSPACE = 127
};

#define REFRESH_CLEAN (1 << 0)
#define REFRESH_WRITE (1 << 1)
#define REFRESH_ALL (REFRESH_CLEAN | REFRESH_WRITE)
// terminal state

/* These terminals do not support the escape sequences used by the editor. */
static int _unsupported_terminal(void) {
  const char *term = getenv("TERM");
  int j;

  if (term == NULL) return 0;
  for (j = 0; unsupported_term[j]; j++)
    if (!strcasecmp(term,unsupported_term[j])) return 1;
  return 0;
}

static void _io_fail(Symbol operation) {
  int error = errno;
  raise %(io-fail (operation $operation) (errno $error));
}

/* The edit buffer never grows past its fixed limit. */
static void _size_limit(void) {
  int limit = LINENOISE_MAX_LINE;
  raise %(size-limit (operation "ReplInput.read") (limit $limit));
}

static void _write_bytes(int fd, const char *bytes, size_t length) {
  size_t written = 0;
  while (written < length) {
    ssize_t count = write(fd, bytes + written, length - written);
    if (count > 0) written += (size_t) count;
    else if (count < 0 && errno == EINTR) continue;
    else _io_fail(<write>);
  }
}

static void _enable_raw(ReplInput input) {
  struct termios raw;

  if (tcgetattr(input.ifd, &input.original) == -1)
    _io_fail(<tcgetattr>);
  raw = input.original;
  /* input modes: no break, no CR to NL, no parity check, no strip char,
   * no start/stop output control. */
  raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
  /* output modes - disable post processing */
  raw.c_oflag &= ~(OPOST);
  /* control modes - set 8 bit chars */
  raw.c_cflag |= (CS8);
  /* local modes - choing off, canonical off, no extended functions,
   * no signal chars (^Z,^C) */
  raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
  /* control chars - set return condition: min number of bytes and timer.
   * We want read to return every single byte, without timeout. */
  raw.c_cc[VMIN] = 1; raw.c_cc[VTIME] = 0; /* 1 byte, no timer */

  /* put terminal in raw mode after flushing */
  if (tcsetattr(input.ifd, TCSAFLUSH, &raw) < 0)
    _io_fail(<tcsetattr>);
  input.raw = 1;
}

/* Cleanup stays best effort so an earlier failure remains the reported one. */
static void _restore(ReplInput input) {
  if (!input || !input.raw) return;
  if (write(input.ofd, "\x1b[?2004l", 8) < 0) {}
  tcsetattr(input.ifd, TCSAFLUSH, &input.original);
  input.raw = 0;
}

/* Use the ESC [6n escape sequence to query the horizontal cursor position
 * and return it. On error -1 is returned, on success the position of the
 * cursor. */
static int _cursor_column(int ifd, int ofd) {
  char buf[32];
  int cols, rows;
  unsigned int i = 0;

  /* Report cursor location */
  if (write(ofd, "\x1b[6n", 4) != 4) return -1;

  /* Read the response: ESC [ rows ; cols R */
  while (i < sizeof(buf)-1) {
    if (read(ifd,buf+i,1) != 1) break;
    if (buf[i] == 'R') break;
    i++;
  }
  buf[i] = '\0';

  /* Parse it. */
  if (buf[0] != ESC || buf[1] != '[') return -1;
  if (sscanf(buf+2,"%d;%d",&rows,&cols) != 2) return -1;
  return cols;
}

/* Try to get the number of columns in the current terminal, or assume 80
 * if it fails. */
static int _terminal_columns(int ifd, int ofd) {
  struct winsize ws;

  if (ioctl(ofd, TIOCGWINSZ, &ws) == -1 || ws.ws_col == 0) {
    /* ioctl() failed. Try to query the terminal itself. */
    int start, cols;

    /* Get the initial position so we can restore it later. */
    start = _cursor_column(ifd,ofd);
    if (start == -1) goto failed;

    /* Go to right margin and get position. */
    if (write(ofd,"\x1b[999C",6) != 6) goto failed;
    cols = _cursor_column(ifd,ofd);
    if (cols == -1) goto failed;

    /* Restore position. A failed restore leaves the width known. */
    if (cols > start) {
      char seq[32];
      snprintf(seq,32,"\x1b[%dD",cols-start);
      if (write(ofd,seq,strlen(seq)) < 0) {}
    }
    return cols;
  }
  return ws.ws_col;

failed:
  return 80;
}

/* Handles ctrl+l. */
static void _clear_screen(EditState &l) {
  _write_bytes(l.input.ofd, "\x1b[H\x1b[2J", 7);
}

static void _beep(void) {
  fprintf(stderr, "\x7");
  fflush(stderr);
}

// editable buffer and display folds

/* Folds are sorted, non-overlapping ranges in the real edit buffer.
   Rendering replaces each range with a marker; editing uses its endpoints. */
/* Return the number of logical lines in the range. */
static size_t _fold_line_count(const char *buf, size_t len) {
  size_t lines = 1, j;
  for (j = 0; j < len; j++) if (buf[j] == '\n') lines++;
  return lines;
}

/* Return true if the text should be folded: if it contains newlines or is at
 * least PASTE_FOLD_THRESHOLD bytes long. */
static int _should_fold(const char *buf, size_t len) {
  return memchr(buf, '\n', len) != NULL || len >= PASTE_FOLD_THRESHOLD;
}

/* Restore one fold from a history entry. History stores
 * the real text, but not the original paste boundaries, so we reconstruct
 * an approximation of text we want to hide on the fly: if it is long or
 * contains newlines. */
static void _history_fold(EditState &l) {
  size_t start = 0, end = 0;
  if (l.len == 0) return;
  if (!_should_fold(l.buf,l.len)) return;

  start = 0;
  end = l.len;
  if (l.len > PASTE_FOLD_CONTEXT*2) {
    size_t pos = 0, chars = 0;
    int nl = 0;

    /* We leave (if possible) a few chars on
     * the start before the fold, to give context. */
    while (pos < l.len && chars < PASTE_FOLD_CONTEXT) {
      size_t step = _next_grapheme_len(l.buf,pos,l.len);
      if (step == 0 || pos + step > l.len) break;
      if (l.buf[pos] == '\n') nl = 1;
      pos += step;
      chars++;
    }
    start = nl ? 0 : pos;

    /* And also on the end side. */
    pos = l.len;
    chars = 0;
    nl = 0;
    while (pos > 0 && chars < PASTE_FOLD_CONTEXT) {
      size_t step = _previous_grapheme_len(l.buf,pos);
      if (step == 0 || step > pos) break;
      pos -= step;
      if (l.buf[pos] == '\n') nl = 1;
      chars++;
    }
    end = nl ? l.len : pos;
    if (start >= end) {
      start = 0;
      end = l.len;
    }
  }
  _fold_add(l, start, end);
}

/* Writes the visible gaps and fold markers, translating the byte cursor
   into the rendered buffer. Stored fold ranges stay in the edit buffer. */
static void _render_buffer(EditState &l, Buffer out, size_t &outpos) {
  size_t source = 0;
  int positioned = 0;
  for (int i = 0; i < l.fold_count; i++) {
    size_t start = l.fold_start[i], end = l.fold_end[i];
    if (!positioned && l.pos <= start) {
      outpos = out.len() + l.pos - source;
      positioned = 1;
    }
    out.write_len(l.buf + source, start - source);
    size_t lines = _fold_line_count(l.buf + start, end - start);
    if (lines > 1) out.printf("[... %zu pasted lines ...]", lines);
    else out.printf("[... %zu pasted chars ...]", end - start);
    if (!positioned && l.pos <= end) {
      outpos = out.len();
      positioned = 1;
    }
    source = end;
  }
  if (!positioned) outpos = out.len() + l.pos - source;
  out.write_len(l.buf + source, l.len - source);
}

/* Return the number of bytes to move right from pos. If pos is at the start of
 * a folded range, the whole hidden range is skipped by one cursor movement. */
static size_t _next_edit_len(EditState &l, size_t pos) {
  for (int i = 0; i < l.fold_count; i++)
    if (pos == l.fold_start[i]) return l.fold_end[i] - l.fold_start[i];
  return _next_grapheme_len(l.buf, pos, l.len);
}

/* A left move at a fold's end skips the same stored range. */
static size_t _previous_edit_len(EditState &l, size_t pos) {
  for (int i = 0; i < l.fold_count; i++)
    if (pos == l.fold_end[i]) return l.fold_end[i] - l.fold_start[i];
  return _previous_grapheme_len(l.buf, pos);
}

/* Keeps the fold array sorted by start offset. */
static void _fold_add(EditState &l, size_t start, size_t end) {
  int j;

  if (start >= end || l.fold_count == LINENOISE_MAX_FOLDS) return;
  j = l.fold_count;
  while (j > 0 && start < l.fold_start[j-1]) {
    l.fold_start[j] = l.fold_start[j-1];
    l.fold_end[j] = l.fold_end[j-1];
    j--;
  }
  l.fold_start[j] = start;
  l.fold_end[j] = end;
  l.fold_count++;
}

static void _fold_clear(EditState &l) {
  l.fold_count = 0;
}

static void _fold_remove(EditState &l, int j) {
  memmove(
    l.fold_start+j, l.fold_start+j+1,
    sizeof(size_t)*(l.fold_count-j-1));
  memmove(
    l.fold_end+j, l.fold_end+j+1,
    sizeof(size_t)*(l.fold_count-j-1));
  l.fold_count--;
}

/* Return true if [pos,pos+len) overlaps any folded range. */
static int _overlaps_fold(EditState &l, size_t pos, size_t len) {
  size_t end = pos + len;
  int j;

  for (j = 0; j < l.fold_count; j++)
    if (end > l.fold_start[j] && pos < l.fold_end[j]) return 1;
  return 0;
}

/* Adjust fold ranges after an insertion. If insertion somehow lands inside a
 * fold, remove that fold because it no longer maps to an unchanged range. */
static void _adjust_folds_after_insert(
  EditState &l, size_t pos, size_t len) {
  int j = 0;

  while (j < l.fold_count) {
    if (pos <= l.fold_start[j]) {
      l.fold_start[j] += len;
      l.fold_end[j] += len;
      j++;
    } else if (pos < l.fold_end[j]) _fold_remove(l, j);
    else j++;
  }
}

/* Adjust fold ranges after a deletion. If deletion overlaps a fold, remove
 * that fold because it no longer maps to an unchanged range. */
static void _adjust_folds_after_delete(
  EditState &l, size_t pos, size_t len) {
  size_t end = pos + len;
  int j = 0;

  while (j < l.fold_count) {
    if (end <= l.fold_start[j]) {
      l.fold_start[j] -= len;
      l.fold_end[j] -= len;
      j++;
    } else if (pos >= l.fold_end[j]) j++;
    else _fold_remove(l, j);
  }
}

/* Rewrite the wrapped display using terminal columns and codepoint widths,
   batching escape sequences into one write to reduce flicker. */
static void _render(EditState &l, int flags) {
  size_t pwidth = _display_width(l.prompt, l.plen);
  char *render = l.buf;
  size_t render_len = l.len, render_pos = l.pos;
  size_t bufwidth;
  size_t poswidth;
  int rows; /* rows used by current rendered buffer. */
  int rpos = l.oldrpos;   /* cursor relative row from previous refresh. */
  int rpos2; /* rpos after refresh. */
  int col; /* column position, zero-based. */
  int old_rows = l.oldrows;
  int fd = l.input.ofd, j;

  Buffer folded = auto l.fold_count ? Buffer.new(0) : NULL;
  if (l.fold_count) {
    _render_buffer(l, folded, render_pos);
    render = folded.content.bytes;
    render_len = folded.len();
  }
  bufwidth = _display_width(render, render_len);
  poswidth = _display_width(render, render_pos);
  rows = (pwidth+bufwidth+l.cols-1)/l.cols;
  l.oldrows = rows;

  /* First step: clear all the lines used before. To do so start by
   * going to the last row. */
  Buffer ab = auto Buffer.new(0);

  if (flags & REFRESH_CLEAN) {
    if (old_rows-rpos > 0) ab.printf("\x1b[%dB", old_rows-rpos);

    /* Now for every row clear it, go up. */
    for (j = 0; j < old_rows-1; j++) ab.write("\r\x1b[0K\x1b[1A");
  }

  if (flags & REFRESH_ALL) {
    /* Clean the top line. */
    ab.write("\r\x1b[0K");
  }

  if (flags & REFRESH_WRITE) {
    /* Write the prompt and the current buffer content */
    ab.write_len(l.prompt, l.plen).write_len(render, render_len);
    /* If we are at the very end of the screen with our prompt, we need to
     * emit a newline and move the prompt to the first column. */
    if (l.pos &&
      render_pos == render_len &&
      (poswidth+pwidth) % l.cols == 0)
    {
      ab.write("\n\r");
      rows++;
      if (rows > (int)l.oldrows) l.oldrows = rows;
    }

    /* Move cursor to right position. */
    rpos2 = (pwidth+poswidth+l.cols)/l.cols;

    /* Go up till we reach the expected position. */
    if (rows-rpos2 > 0) ab.printf("\x1b[%dA", rows-rpos2);

    /* Set column. */
    col = (pwidth+poswidth) % l.cols;
    ab.write("\r");
    if (col) ab.printf("\x1b[%dC", col);
  }

  if (flags & REFRESH_WRITE) l.oldrpos = rpos2;

  _write_bytes(fd, ab.content.bytes, ab.len());
}

static void _refresh_line(EditState &l) {
  _render(l, REFRESH_ALL);
}

/* Stops at the fixed interactive-input limit. */
static int _grow(EditState &l, size_t needed) {
  size_t newlen;
  char *newbuf;

  if (needed <= l.buflen) return 0;

  if (needed > LINENOISE_MAX_LINE) return -1;

  /* Grow exponentially, but stop at the input limit before the
   * doubling would overflow or go past it. */
  newlen = l.buflen ? l.buflen : 16;
  while (newlen < needed) {
    if (newlen > LINENOISE_MAX_LINE/2) {
      newlen = LINENOISE_MAX_LINE;
      break;
    }
    newlen *= 2;
  }

  /* Allocate one extra byte for the nul terminator. */
  newbuf = xrealloc(l.buf, newlen + 1);
  l.buf = newbuf;
  l.buflen = newlen;
  return 0;
}

/* Insert bytes into l.buf without repainting the prompt. The paste path uses
 * this to first store the real pasted bytes, then mark their range as folded,
 * and only then refresh so raw pasted newlines are never printed directly. */
static int _insert_raw(EditState &l, const char *c, size_t clen) {
  size_t insert_pos = l.pos;

  if (_grow(l, l.len+clen) == -1) return -1;

  if (l.len == l.pos) memcpy(l.buf+l.pos,c,clen);
  else {
    memmove(l.buf+l.pos+clen,l.buf+l.pos,l.len-l.pos);
    memcpy(l.buf+l.pos,c,clen);
  }
  l.pos += clen;
  l.len += clen;
  l.buf[l.len] = '\0';
  _adjust_folds_after_insert(l, insert_pos,clen);
  return 0;
}

static void _insert(EditState &l, const char *c, size_t clen) {
  if (_insert_raw(l, c, clen) == -1) _size_limit();
  _refresh_line(l);
}

/* Move cursor on the left. Moves by one UTF-8 character, not byte. */
static void _move_left(EditState &l) {
  if (l.pos > 0) {
    l.pos -= _previous_edit_len(l, l.pos);
    _refresh_line(l);
  }
}

/* Move cursor on the right. Moves by one UTF-8 character, not byte. */
static void _move_right(EditState &l) {
  if (l.pos != l.len) {
    l.pos += _next_edit_len(l, l.pos);
    _refresh_line(l);
  }
}

/* Move cursor to the start of the line. */
static void _move_home(EditState &l) {
  if (l.pos != 0) {
    l.pos = 0;
    _refresh_line(l);
  }
}

static void _move_end(EditState &l) {
  if (l.pos != l.len) {
    l.pos = l.len;
    _refresh_line(l);
  }
}

/* Substitute the currently edited line with the next or previous history
 * entry as specified by 'dir'. */
#define LINENOISE_HISTORY_NEXT 0
#define LINENOISE_HISTORY_PREV 1
static void _recall(EditState &l, int dir) {
  if (l.history_len > 1) {
    const char *src;
    size_t len;

    /* Update the current history entry before to
     * overwrite it with the next one. */
    int current = l.history_len - 1 - l.history_index;
    xfree(l.history[current]);
    l.history[current] = xmemdup(l.buf, l.len + 1);
    /* Show the new entry */
    l.history_index += (dir == LINENOISE_HISTORY_PREV) ? 1 : -1;
    if (l.history_index < 0) {
      l.history_index = 0;
      return;
    } else if (l.history_index >= l.history_len) {
      l.history_index = l.history_len - 1;
      return;
    }

    /* Copy the selected entry into the mutable history view. */
    src = l.history[l.history_len - 1 - l.history_index];
    len = strlen(src);
    if (_grow(l, len) == -1) _size_limit();
    memcpy(l.buf,src,len);
    l.buf[len] = '\0';
    l.len = l.pos = len;
    _fold_clear(l);

    /* History stores the real text, but not the original paste ranges.
     * If the recalled entry needs folding, create one display fold now
     * so text typed after recall remains outside the folded range. */
    _history_fold(l);
    _refresh_line(l);
  }
}

/* Delete the character at the right of the cursor without altering the cursor
 * position. Basically this is what happens with the "Delete" keyboard key.
 * Now handles multi-byte UTF-8 characters. */
static void _delete(EditState &l) {
  if (l.len > 0 && l.pos < l.len) {
    size_t clen = _next_edit_len(l, l.pos);
    _adjust_folds_after_delete(l, l.pos,clen);
    memmove(l.buf+l.pos, l.buf+l.pos+clen, l.len-l.pos-clen);
    l.len -= clen;
    l.buf[l.len] = '\0';
    _refresh_line(l);
  }
}

/* Deletes the whole UTF-8 character before the cursor. */
static void _backspace(EditState &l) {
  if (l.pos > 0 && l.len > 0) {
    size_t clen = _previous_edit_len(l, l.pos);
    _adjust_folds_after_delete(l, l.pos-clen,clen);
    memmove(l.buf+l.pos-clen, l.buf+l.pos, l.len-l.pos);
    l.pos -= clen;
    l.len -= clen;
    l.buf[l.len] = '\0';
    _refresh_line(l);
  }
}

/* Delete the previous word, maintaining the cursor at the start of the
 * current word. Handles UTF-8 by moving character-by-character. */
static void _delete_previous_word(EditState &l) {
  size_t old_pos = l.pos;
  size_t diff;

  /* Skip spaces before the word (move backwards by UTF-8 chars). */
  while (l.pos > 0 && l.buf[l.pos-1] == ' ')
    l.pos -= _previous_edit_len(l, l.pos);
  /* Skip non-space characters (move backwards by UTF-8 chars). */
  while (l.pos > 0 && l.buf[l.pos-1] != ' ')
    l.pos -= _previous_edit_len(l, l.pos);
  diff = old_pos - l.pos;
  _adjust_folds_after_delete(l, l.pos,diff);
  memmove(l.buf+l.pos, l.buf+old_pos, l.len-old_pos+1);
  l.len -= diff;
  _refresh_line(l);
}

static char *_copy_text(const char *text) =>
  xmemdup(text, strlen(text) + 1);

static void _prepare(
  EditState &l, ReplInput input, String prompt,
  ReplInputComplete complete, void *completion_context) {
  l = (EditState) {0};
  l.input = input;
  input.ifd = STDIN_FILENO;
  input.ofd = STDOUT_FILENO;
  l.buf = xmalloc(LINENOISE_INITIAL_BUFLEN);
  l.buflen = LINENOISE_INITIAL_BUFLEN - 1;
  l.prompt = prompt;
  l.plen = prompt.len();
  l.complete = complete;
  l.completion_context = completion_context;
  l.oldrpos = 1;
  l.buf[0] = '\0';

  l.history_len = input.history_len + 1;
  l.history = xcalloc(l.history_len, sizeof(char *));
  for (int i = 0; i < input.history_len; i++)
    l.history[i] = _copy_text(input.history[i]);
  l.history[l.history_len - 1] = _copy_text("");
}

static void _close(EditState &l) {
  for (int i = 0; i < l.history_len; i++) xfree(l.history[i]);
  xfree(l.history);
  xfree(l.buf);
}

/* Stage bytes within the remaining edit-buffer limit. The caller drains
   an oversized paste before reporting it; allocation failures transfer. */
static int _append_paste(
  EditState &l, Block &bytes, const char *source, size_t count,
  size_t maximum) {
  size_t used = bytes.len();
  if (count > maximum - used) return -1;
  _grow(l, l.len + used + count);
  if (bytes == NULL) {
    bytes = Block.new(sizeof(char));
    bytes.reserve(64);
  }
  bytes.append(source, count);
  return 0;
}

static int _read_byte(EditState &l, char &out) {
  while (1) {
    ssize_t count = read(l.input.ifd, &out, 1);
    if (count == 1) return 1;
    if (count == 0) return 0;
    if (errno != EINTR) _io_fail(<read>);
  }
}

/* Read a bracketed paste until ESC[201~ and insert the real bytes. If folding
 * is needed, remember the inserted range so only rendering is shortened. */
static void _paste(EditState &l) {
  static const char END[] = "\x1b[201~";
  const size_t ENDLEN = sizeof(END)-1;
  auto Block bytes = NULL;
  size_t match = 0, maxlen = LINENOISE_MAX_LINE - l.len;
  int overflowed = 0;

  /* Consume an excess folded paste before reporting the size limit. */
  if (l.fold_count == LINENOISE_MAX_FOLDS) maxlen = 0;

  while (1) {
    char c;
    if (!_read_byte(l, c)) break;

    /* Track a possible ESC[201~ terminator without copying it into the
     * paste. If it turns out to be ordinary input, flush the partial
     * match below. */
    if (c == END[match]) {
      match++;
      if (match == ENDLEN) break;
      continue;
    }

    if (match > 0) {
      if (!overflowed &&
        _append_paste(l, bytes, END, match, maxlen) == -1)
        overflowed = 1;
      match = 0;
      if (c == END[0]) {
        match = 1;
        continue;
      }
    }

    if (!overflowed &&
      _append_paste(l, bytes, &c, 1, maxlen) == -1)
      overflowed = 1;
  }

  if (overflowed) _size_limit();
  size_t len = bytes.len();
  if (!len) return;
  char *buf = bytes.bytes;

  {
    /* Normalize pasted CR and CRLF to LF, so the edit buffer uses one
     * internal newline representation, and drop NUL as typed input does. */
    size_t r = 0, w = 0;
    while (r < len) {
      if (buf[r] == '\r') {
        buf[w++] = '\n';
        r += (r+1 < len && buf[r+1] == '\n') ? 2 : 1;
      } else if (buf[r]) buf[w++] = buf[r++];
      else r++;
    }
    len = w;
  }

  if (_should_fold(buf,len)) {
    size_t start = l.pos;
    if (_insert_raw(l, buf,len) == -1) _size_limit();
    _fold_add(l, start,start+len);
    _refresh_line(l);
  } else _insert(l, buf,len);
}

static void _replace_completion(
  EditState &l, size_t start, size_t end, String replacement) {
  size_t added = replacement.len(), removed = end - start;
  size_t length = l.len - removed + added;
  if (_grow(l, length) == -1) _size_limit();
  memmove(l.buf + start + added, l.buf + end, l.len - end + 1);
  memcpy(l.buf + start, replacement, added);
  l.len = length;
  l.pos = start + added;
  _fold_clear(l);
  _refresh_line(l);
}

static String _completion_spelling(Var candidate) {
  match (candidate) case %(? ?(String spelling)): return spelling;
  return NULL;
}

static Symbol _completion_kind(Var candidate) {
  match (candidate) case %(?(Symbol kind) ?): return kind;
  return 0;
}

static size_t _completion_common(List candidates) {
  String first = _completion_spelling(candidates.car());
  size_t common = first.len();
  foreach (Var row, candidates.cdr()) {
    String candidate = _completion_spelling(row);
    if (candidate.len() < common) common = candidate.len();
    size_t i = 0;
    while (i < common && first[i] == candidate[i]) i++;
    common = i;
  }
  return common;
}

static int _show_completion_group(
  EditState &l, List candidates, Symbol kind, String heading) {
  int found = 0;
  size_t column = 2;
  foreach (Var row, candidates) {
    if (_completion_kind(row) != kind) continue;
    String spelling = _completion_spelling(row);
    size_t width = _display_width(spelling, spelling.len());
    if (!found) {
      _write_bytes(l.input.ofd, heading, heading.len());
      _write_bytes(l.input.ofd, ":\r\n  ", 5);
      found = 1;
    }
    else if (column + 2 + width > l.cols) {
      _write_bytes(l.input.ofd, "\r\n  ", 4);
      column = 2;
    }
    else {
      _write_bytes(l.input.ofd, "  ", 2);
      column += 2;
    }
    _write_bytes(l.input.ofd, spelling, spelling.len());
    column += width;
  }
  if (found) _write_bytes(l.input.ofd, "\r\n", 2);
  return found;
}

static void _show_completions(EditState &l, List candidates) {
  _render(l, REFRESH_CLEAN);
  _write_bytes(l.input.ofd, "\r", 1);
  _show_completion_group(l, candidates, <command>, "Commands");
  _show_completion_group(l, candidates, <keyword>, "Keywords");
  _show_completion_group(l, candidates, <session>, "Session");
  _show_completion_group(l, candidates, <type>, "Types");
  _show_completion_group(l, candidates, <callable>, "Functions and macros");
  _show_completion_group(l, candidates, <name>, "Names");
  _show_completion_group(l, candidates, <member>, "Members");
  l.oldrows = 0;
  l.oldrpos = 1;
  _refresh_line(l);
}

static void _complete(EditState &l) {
  if (!l.complete) { _beep(); return; }
  String text = String.new_len(l.buf, l.len);
  ReplInputCompletion completion =
    l.complete(l.completion_context, text, l.pos);
  List candidates = completion.candidates;
  if (!candidates || completion.start > completion.end ||
      completion.end > l.len) {
    l.completion_pending = 0;
    _beep();
    return;
  }
  size_t common = _completion_common(candidates);
  size_t present = completion.end - completion.start;
  if (!candidates.cdr() || common > present) {
    String first = _completion_spelling(candidates.car());
    String replacement = String.new_len(first, common);
    _replace_completion(l, completion.start, completion.end, replacement);
    l.completion_pending = 0;
    return;
  }
  if (l.completion_pending) {
    _show_completions(l, candidates);
    l.completion_pending = 0;
  }
  else {
    l.completion_pending = 1;
    _beep();
  }
}

static Symbol _feed(EditState &l) {
  char c, seq[3];
  if (!_read_byte(l, c)) return <eof>;

  if (c != TAB) l.completion_pending = 0;

  switch(c) {
  case KEY_NULL: break;
  case TAB:
    _complete(l);
    break;
  case ENTER:
    _move_end(l);
    return <line>;
  case CTRL_C:
    return <cancelled>;
  case BACKSPACE:   /* backspace */
  case 8:     /* ctrl-h */
    _backspace(l);
    break;
  case CTRL_D:     /* ctrl-d, remove char at right of cursor, or if the
            line is empty, act as end-of-file. */
    if (l.len > 0) _delete(l);
    else return <eof>;
    break;
  case CTRL_T:    /* ctrl-t, swaps current character with previous. */
    /* Handle UTF-8: swap the two UTF-8 characters around cursor. */
    if (l.pos > 0 && l.pos < l.len) {
      char tmp[32];
      size_t prevlen = _previous_edit_len(l, l.pos);
      size_t currlen = _next_edit_len(l, l.pos);
      size_t prevstart = l.pos - prevlen;
      if (prevlen > sizeof(tmp) || currlen > sizeof(tmp)) break;
      if (_overlaps_fold(l, prevstart,prevlen+currlen)) {
        _beep();
        break;
      }
      /* Copy current char to tmp, move previous char right, paste tmp. */
      memcpy(tmp, l.buf + l.pos, currlen);
      memmove(l.buf + prevstart + currlen, l.buf + prevstart, prevlen);
      memcpy(l.buf + prevstart, tmp, currlen);
      if (l.pos + currlen <= l.len) l.pos += currlen;
      _refresh_line(l);
    }
    break;
  case CTRL_B:     /* ctrl-b */
    _move_left(l);
    break;
  case CTRL_F:     /* ctrl-f */
    _move_right(l);
    break;
  case CTRL_P:    /* ctrl-p */
    _recall(l, LINENOISE_HISTORY_PREV);
    break;
  case CTRL_N:    /* ctrl-n */
    _recall(l, LINENOISE_HISTORY_NEXT);
    break;
  case ESC:
    /* Read the next two bytes representing the escape sequence.
     * Use two calls to handle slow terminals returning the two
     * chars at different times. */
    if (!_read_byte(l, seq[0]) || !_read_byte(l, seq[1])) break;

    /* ESC [ sequences. */
    if (seq[0] == '[') {
      if (seq[1] >= '0' && seq[1] <= '9') {
        char param[8];
        size_t plen = 1;
        char final = 0;

        param[0] = seq[1];
        while (plen < sizeof(param)) {
          char p;
          if (!_read_byte(l, p)) break;
          if (p >= '0' && p <= '9') param[plen++] = p;
          else {
            final = p;
            break;
          }
        }
        if (final == '~') {
          if (plen == 1 && param[0] == '3') _delete(l);
          else if (plen == 3 && memcmp(param,"200",3) == 0) _paste(l);
        }
      } else {
        switch(seq[1]) {
        case 'A': /* Up */
          _recall(l, LINENOISE_HISTORY_PREV);
          break;
        case 'B': /* Down */
          _recall(l, LINENOISE_HISTORY_NEXT);
          break;
        case 'C': /* Right */
          _move_right(l);
          break;
        case 'D': /* Left */
          _move_left(l);
          break;
        case 'H': /* Home */
          _move_home(l);
          break;
        case 'F': /* End*/
          _move_end(l);
          break;
        }
      }
    }

    /* ESC O sequences. */
    else if (seq[0] == 'O') {
      switch(seq[1]) {
      case 'H': /* Home */
        _move_home(l);
        break;
      case 'F': /* End*/
        _move_end(l);
        break;
      }
    }
    break;
  default:
    /* Handle UTF-8 multi-byte sequences. When we receive the first byte
     * of a multi-byte UTF-8 character, read the remaining bytes to
     * complete the sequence before inserting. */
    {
      char utf8[4];
      int utf8len = _utf8_byte_len(c);
      utf8[0] = c;
      int length = 1;
      while (length < utf8len && _read_byte(l, utf8[length])) length++;
      _insert(l, utf8, length);
    }
    break;
  case CTRL_U: /* Ctrl+u, delete the whole line. */
    l.buf[0] = '\0';
    l.pos = l.len = 0;
    _fold_clear(l);
    _refresh_line(l);
    break;
  case CTRL_K: /* Ctrl+k, delete from current to end of line. */
    _adjust_folds_after_delete(l, l.pos,l.len-l.pos);
    l.buf[l.pos] = '\0';
    l.len = l.pos;
    _refresh_line(l);
    break;
  case CTRL_A: /* Ctrl+a, go to the start of the line */
    _move_home(l);
    break;
  case CTRL_E: /* ctrl+e, go to the end of the line */
    _move_end(l);
    break;
  case CTRL_L: /* ctrl+l, clear screen */
    _clear_screen(l);
    _refresh_line(l);
    break;
  case CTRL_W:
    _delete_previous_word(l);
    break;
  }
  return <editing>;
}

static ReplInputResult _read_interactive(
  ReplInput input, String prompt, ReplInputComplete complete,
  void *completion_context) {
  EditState edit;
  _prepare(edit, input, prompt, complete, completion_context);
  defer _close(edit);

  _enable_raw(input);
  defer _restore(input);
  _write_bytes(input.ofd, "\x1b[?2004h", 8);
  edit.cols = _terminal_columns(input.ifd, input.ofd);
  _write_bytes(input.ofd, prompt, prompt.len());

  Symbol status;
  while ((status = _feed(edit)) == <editing>) {}
  String text = status == <line> ? String.new(edit.buf) : NULL;
  _restore(input);
  _write_bytes(input.ofd, "\n", 1);
  return (ReplInputResult) { .status = status, .text = text };
}

/** Creates an interactive terminal owner with empty in-memory history. */
ReplInput ReplInput.new(void) {
  ReplInput input = xcalloc(1, sizeof(struct ReplInput));
  input.storage = Scope.new_named("repl-input");
  input.history = Scope.calloc_in(
    &input.storage, REPL_HISTORY_MAX, sizeof(char *));
  input.open = 1;
  return input;
}

/** Reads one accepted line, EOF, or cancellation. Supported terminals use
    inline editing; other terminal types use the basic line reader. Terminal
    mode is restored before return or transfer of an allocation, size, or I/O
    cause. */
ReplInputResult ReplInput.read(
  ReplInput r, String prompt, ReplInputComplete complete,
  void *completion_context) {
  if (!r || !r.open)
    return (ReplInputResult) { .status = <eof> };
  if (_unsupported_terminal()) {
    _write_bytes(STDOUT_FILENO, prompt, prompt.len());
    String text = Stdin.readline();
    if (!text) return (ReplInputResult) { .status = <eof> };
    text = text.remove_suffix("\n").remove_suffix("\r");
    return (ReplInputResult) { .status = <line>, .text = text };
  }
  return _read_interactive(r, prompt, complete, completion_context);
}

/** Records one nonempty entry, suppressing an adjacent duplicate and
    evicting the oldest entry beyond 100. */
void ReplInput.remember(ReplInput r, String text) {
  if (!r || !r.open || !text || !text.len()) return;
  if (r.history_len && !strcmp(r.history[r.history_len - 1], text)) return;

  char *copy = Scope.memdup_in(&r.storage, text, text.len() + 1);
  if (r.history_len == REPL_HISTORY_MAX) {
    xfree(r.history[0]);
    memmove(
      r.history, r.history + 1,
      sizeof(char *) * (REPL_HISTORY_MAX - 1));
    r.history_len--;
  }
  r.history[r.history_len++] = copy;
}

/** Restores the terminal and releases editor-owned history storage. */
void ReplInput.close(ReplInput r) {
  if (!r || !r.open) return;
  _restore(r);
  r.storage.destroy();
  r.history = NULL;
  r.history_len = 0;
  r.open = 0;
}
