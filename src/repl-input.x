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

/** Owns terminal restoration and the current process's bounded REPL history. */
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

#pragma private
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
#include "scope.x"
#include "string.x"

#define REPL_HISTORY_MAX 100
#define LINENOISE_MAX_FOLDS 16

struct ReplInput {
  Scope storage;
  char **history;
  int history_len, open;
  struct termios original;
  int raw, ifd, ofd;
};

struct EditState {
  ReplInput input;
  char *buf, **history;
  size_t buflen, buflen_max;
  const char *prompt;
  size_t plen, pos, oldpos, len, cols, oldrows;
  int oldrpos, history_index, history_len, fold_count;
  ReplInputComplete complete;
  void *completion_context;
  int completion_pending;
  size_t fold_start[LINENOISE_MAX_FOLDS];
  size_t fold_end[LINENOISE_MAX_FOLDS];
};

#define LINENOISE_MAX_LINE (1024*1024)
#define LINENOISE_INITIAL_BUFLEN 4096
#define PASTE_FOLD_THRESHOLD 200
#define PASTE_FOLD_CONTEXT 8
#define PASTE_MAX_BYTES LINENOISE_MAX_LINE
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
static uint32_t _utf8_decode(const char *s, size_t available, size_t *len) {
  const unsigned char *p = (const unsigned char *)s;
  int expected;

  if (!available) {
    *len = 0;
    return 0;
  }
  expected = _utf8_byte_len(*p);
  if (expected == 1 || (size_t)expected > available) {
    *len = 1;
    return *p;
  }
  for (int i = 1; i < expected; i++) {
    if ((p[i] & 0xc0) != 0x80) {
      *len = 1;
      return *p;
    }
  }

  *len = expected;
  if (expected == 2)
    return ((*p & 0x1f) << 6) | (p[1] & 0x3f);
  if (expected == 3)
    return ((*p & 0x0f) << 12) | ((p[1] & 0x3f) << 6) |
           (p[2] & 0x3f);
  return ((*p & 0x07) << 18) | ((p[1] & 0x3f) << 12) |
         ((p[2] & 0x3f) << 6) | (p[3] & 0x3f);
}

/* Check if codepoint is a variation selector (emoji style modifiers). */
static int _is_variation_selector(uint32_t cp) {
  return cp == 0xFE0E || cp == 0xFE0F;  /* Text/emoji style */
}

/* Check if codepoint is a skin tone modifier. */
static int _is_skin_tone_modifier(uint32_t cp) {
  return cp >= 0x1F3FB && cp <= 0x1F3FF;
}

/* Check if codepoint is Zero Width Joiner. */
static int _is_joiner(uint32_t cp) {
  return cp == 0x200D;
}

/* Check if codepoint is a Regional Indicator (for flag emoji). */
static int _is_regional_indicator(uint32_t cp) {
  return cp >= 0x1F1E6 && cp <= 0x1F1FF;
}

/* Check if codepoint is a combining mark or other zero-width character. */
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
 * return its value. Also sets *cplen to the byte length of the codepoint. */
static uint32_t _utf8_decode_previous(
  const char *buf, size_t pos, size_t *cplen) {
  if (pos == 0) {
    *cplen = 0;
    return 0;
  }
  /* Scan backwards to find the start byte. */
  size_t i = pos;
  do i--;
  while (i > 0 && (pos - i) < 4 &&
         ((unsigned char)buf[i] & 0xC0) == 0x80);
  *cplen = pos - i;
  size_t dummy;
  return _utf8_decode(buf + i, pos - i, &dummy);
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
  uint32_t cp = _utf8_decode_previous(buf, curpos, &cplen);
  if (cplen == 0) return 0;
  total += cplen;
  curpos -= cplen;

  /* If we're at an extending character, we need to find what it extends.
   * Keep going back through the grapheme cluster. */
  while (curpos > 0) {
    size_t prevlen;
    uint32_t prevcp = _utf8_decode_previous(buf, curpos, &prevlen);
    if (prevlen == 0) break;

    if (_is_joiner(prevcp)) {
      /* ZWJ joins two emoji. Include the ZWJ and continue to get
       * the preceding character. */
      total += prevlen;
      curpos -= prevlen;
      /* Now get the character before ZWJ. */
      prevcp = _utf8_decode_previous(buf, curpos, &prevlen);
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
  uint32_t cp = _utf8_decode(buf + curpos, len - curpos, &cplen);
  total += cplen;
  curpos += cplen;

  int regional = _is_regional_indicator(cp);

  /* Consume any extending characters that follow. */
  while (curpos < len) {
    size_t nextlen;
    uint32_t nextcp = _utf8_decode(buf + curpos, len - curpos, &nextlen);

    if (_is_joiner(nextcp) && curpos + nextlen < len) {
      /* ZWJ: include it and the following character. */
      total += nextlen;
      curpos += nextlen;
      /* Get the character after ZWJ. */
      nextcp = _utf8_decode(buf + curpos, len - curpos, &nextlen);
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
     (cp >= 0x23E9 && cp <= 0x23F3) ||    /* Various symbols */
     (cp >= 0x23F8 && cp <= 0x23FA) ||    /* Various symbols */
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
    uint32_t cp = _utf8_decode(s + i, len - i, &clen);

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

/* Return the display width of a single UTF-8 character at position 's'. */
static int _single_char_width(const char *s, size_t len) {
  if (len == 0) return 0;
  size_t clen;
  uint32_t cp = _utf8_decode(s, len, &clen);
  return _codepoint_width(cp);
}

enum KEY_ACTION {
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

/* Clear the screen. Used to handle ctrl+l */
static void _clear_screen(struct EditState *l) {
  _write_bytes(l.input.ofd, "\x1b[H\x1b[2J", 7);
}

static void _beep(void) {
  fprintf(stderr, "\x7");
  fflush(stderr);
}

// editable buffer and display folds

/* Rendering batches escape sequences into one write to reduce flicker. */
struct RenderBuffer {
  char *b;
  int len;
};

static void _render_buffer_init(struct RenderBuffer *ab) {
  ab.b = NULL;
  ab.len = 0;
}

static void _render_buffer_append(
  struct RenderBuffer *ab, const char *s, int len) {
  char *new = Scope.realloc(ab.b, (size_t) ab.len + len);
  memcpy(new+ab.len,s,len);
  ab.b = new;
  ab.len += len;
}

static void _render_buffer_close(struct RenderBuffer *ab) {
  Scope.free(ab.b);
}

/* A fold is a display-only replacement for a range in l.buf. The edited
 * buffer always keeps the real bytes; refresh code asks _render_buffer()
 * for a temporary printable version plus the cursor position inside it. */
struct EditFold {
  size_t start;
  size_t end;
  char display[64];
  size_t displaylen;
};

struct EditFolds {
  int count;
  struct EditFold fold[LINENOISE_MAX_FOLDS];
};

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

/* Fill f.display with the text shown instead of the folded range. */
static void _set_fold_text(struct EditFold *f, const char *buf) {
  size_t hidden = f.end - f.start;
  size_t lines = _fold_line_count(buf + f.start, hidden);
  int n;

  if (lines > 1)
    n = snprintf(
      f.display, sizeof(f.display), "[... %zu pasted lines ...]", lines);
  else
    n = snprintf(
      f.display, sizeof(f.display), "[... %zu pasted chars ...]", hidden);
  if (n < 0) n = 0;
  f.displaylen = (size_t)n;
}

/* Populate f with one fold reconstructed from a history entry. History stores
 * the real text, but not the original paste boundaries, so we reconstruct
 * an approximation of text we want to hide on the fly: if it is long or
 * contains newlines. */
static int _history_fold(struct EditState *l, struct EditFold *f) {
  f.start = f.end = f.displaylen = 0;
  if (l.len == 0) return 0;
  if (!_should_fold(l.buf,l.len)) return 0;

  f.start = 0;
  f.end = l.len;
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
    f.start = nl ? 0 : pos;

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
    f.end = nl ? l.len : pos;
    if (f.start >= f.end) {
      f.start = 0;
      f.end = l.len;
    }
  }
  _set_fold_text(f,l.buf);
  return 1;
}

/* Populate fs with the folds to render for the current buffer. As a side
 * effect, the rendered text of each fold is updated. Return 1 if folding
 * should be used, or 0 if the buffer should be rendered as-is. */
static int _render_folds(struct EditState *l, struct EditFolds *fs) {
  int j;

  fs.count = 0;
  if (l.len == 0) return 0;

  for (j = 0; j < l.fold_count; j++) {
    struct EditFold *f;
    size_t start = l.fold_start[j];
    size_t end = l.fold_end[j];

    if (start >= end || end > l.len) continue;
    f = fs.fold + fs.count++;
    f.start = start;
    f.end = end;
    _set_fold_text(f,l.buf);
  }
  return fs.count != 0;
}

/* Return the freshly allocated string content that is actually displayed in
 * the user prompt. It can be the actual edited line, or a special version
 * where pasted or multiline history ranges are replaced by their folded
 * "[...]" style versions. outpos is l.pos translated into this rendered
 * buffer. */
static void _render_buffer(
  struct EditState *l, char **out, size_t *outlen, size_t *outpos) {
  struct EditFolds fs;
  size_t len, pos, src, dst;
  char *r;
  int j, pos_set = 0;

  if (!_render_folds(l,&fs)) {
    /* Keep the refresh code simple: it always owns a temporary render
     * buffer, even when the render is identical to the real edit buffer. */
    r = Scope.malloc(l.len + 1);
    memcpy(r,l.buf,l.len);
    r[l.len] = '\0';
    *out = r;
    *outlen = l.len;
    *outpos = l.pos;
    return;
  }

  /* Gaps are copied as-is, folded ranges are replaced by their markers.
   * The bytes inside each [start,end) range stay in l.buf but are not
   * emitted to the terminal. */
  len = l.len;
  for (j = 0; j < fs.count; j++) {
    struct EditFold *f = fs.fold+j;
    len -= f.end - f.start;
    len += f.displaylen;
  }
  r = Scope.malloc(len + 1);

  src = dst = 0;
  pos = 0;
  for (j = 0; j < fs.count; j++) {
    struct EditFold *f = fs.fold+j;
    size_t gap = f.start - src;

    if (!pos_set && l.pos <= f.start) {
      pos = dst + (l.pos - src);
      pos_set = 1;
    }
    memcpy(r+dst,l.buf+src,gap);
    dst += gap;

    if (!pos_set && l.pos < f.end) {
      pos = dst + f.displaylen;
      pos_set = 1;
    }
    memcpy(r+dst,f.display,f.displaylen);
    dst += f.displaylen;
    if (!pos_set && l.pos == f.end) {
      pos = dst;
      pos_set = 1;
    }
    src = f.end;
  }
  if (!pos_set) pos = dst + (l.pos - src);
  memcpy(r+dst,l.buf+src,l.len-src);
  r[len] = '\0';

  *out = r;
  *outlen = len;
  *outpos = pos;
}

/* Return the number of bytes to move right from pos. If pos is at the start of
 * a folded range, the whole hidden range is skipped by one cursor movement. */
static size_t _next_edit_len(struct EditState *l, size_t pos) {
  struct EditFolds fs;
  int j;

  if (_render_folds(l,&fs))
    for (j = 0; j < fs.count; j++)
      if (pos == fs.fold[j].start)
        return fs.fold[j].end - fs.fold[j].start;
  return _next_grapheme_len(l.buf,pos,l.len);
}

/* Return the number of bytes to move left from pos. If pos is at the end of a
 * folded range, the whole hidden range is skipped by one cursor movement. */
static size_t _previous_edit_len(struct EditState *l, size_t pos) {
  struct EditFolds fs;
  int j;

  if (_render_folds(l,&fs))
    for (j = 0; j < fs.count; j++)
      if (pos == fs.fold[j].end)
        return fs.fold[j].end - fs.fold[j].start;
  return _previous_grapheme_len(l.buf,pos);
}

/* Add a fold range, keeping the array sorted by start offset. */
static void _fold_add(struct EditState *l, size_t start, size_t end) {
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

/* Clear all remembered fold ranges. */
static void _fold_clear(struct EditState *l) {
  l.fold_count = 0;
}

/* Remove one remembered fold range. */
static void _fold_remove(struct EditState *l, int j) {
  memmove(
    l.fold_start+j, l.fold_start+j+1,
    sizeof(size_t)*(l.fold_count-j-1));
  memmove(
    l.fold_end+j, l.fold_end+j+1,
    sizeof(size_t)*(l.fold_count-j-1));
  l.fold_count--;
}

/* Return true if [pos,pos+len) overlaps any folded range. */
static int _overlaps_fold(struct EditState *l, size_t pos, size_t len) {
  size_t end = pos + len;
  int j;

  for (j = 0; j < l.fold_count; j++)
    if (end > l.fold_start[j] && pos < l.fold_end[j]) return 1;
  return 0;
}

/* Adjust fold ranges after an insertion. If insertion somehow lands inside a
 * fold, remove that fold because it no longer maps to an unchanged range. */
static void _adjust_folds_after_insert(
  struct EditState *l, size_t pos, size_t len) {
  int j = 0;

  while (j < l.fold_count) {
    if (pos <= l.fold_start[j]) {
      l.fold_start[j] += len;
      l.fold_end[j] += len;
      j++;
    } else if (pos < l.fold_end[j]) _fold_remove(l,j);
    else j++;
  }
}

/* Adjust fold ranges after a deletion. If deletion overlaps a fold, remove
 * that fold because it no longer maps to an unchanged range. */
static void _adjust_folds_after_delete(
  struct EditState *l, size_t pos, size_t len) {
  size_t end = pos + len;
  int j = 0;

  while (j < l.fold_count) {
    if (end <= l.fold_start[j]) {
      l.fold_start[j] -= len;
      l.fold_end[j] -= len;
      j++;
    } else if (pos >= l.fold_end[j]) j++;
    else _fold_remove(l,j);
  }
}

/* Rewrite the wrapped display using terminal columns and codepoint widths. */
static void _render(struct EditState *l, int flags) {
  char seq[64];
  size_t pwidth = _display_width(l.prompt, l.plen);
  char *render = NULL;
  size_t render_len, render_pos;
  size_t bufwidth;
  size_t poswidth;
  int rows; /* rows used by current rendered buffer. */
  int rpos = l.oldrpos;   /* cursor relative row from previous refresh. */
  int rpos2; /* rpos after refresh. */
  int col; /* column position, zero-based. */
  int old_rows = l.oldrows;
  int fd = l.input.ofd, j;
  struct RenderBuffer ab;

  _render_buffer(l, &render, &render_len, &render_pos);
  defer Scope.free(render);
  bufwidth = _display_width(render, render_len);
  poswidth = _display_width(render, render_pos);
  rows = (pwidth+bufwidth+l.cols-1)/l.cols;
  l.oldrows = rows;

  /* First step: clear all the lines used before. To do so start by
   * going to the last row. */
  _render_buffer_init(&ab);
  defer _render_buffer_close(&ab);

  if (flags & REFRESH_CLEAN) {
    if (old_rows-rpos > 0) {
      snprintf(seq,64,"\x1b[%dB", old_rows-rpos);
      _render_buffer_append(&ab,seq,strlen(seq));
    }

    /* Now for every row clear it, go up. */
    for (j = 0; j < old_rows-1; j++) {
      snprintf(seq,64,"\r\x1b[0K\x1b[1A");
      _render_buffer_append(&ab,seq,strlen(seq));
    }
  }

  if (flags & REFRESH_ALL) {
    /* Clean the top line. */
    snprintf(seq,64,"\r\x1b[0K");
    _render_buffer_append(&ab,seq,strlen(seq));
  }

  if (flags & REFRESH_WRITE) {
    /* Write the prompt and the current buffer content */
    _render_buffer_append(&ab,l.prompt,l.plen);
    _render_buffer_append(&ab,render,render_len);
    /* If we are at the very end of the screen with our prompt, we need to
     * emit a newline and move the prompt to the first column. */
    if (l.pos &&
      render_pos == render_len &&
      (poswidth+pwidth) % l.cols == 0)
    {
      _render_buffer_append(&ab,"\n",1);
      snprintf(seq,64,"\r");
      _render_buffer_append(&ab,seq,strlen(seq));
      rows++;
      if (rows > (int)l.oldrows) l.oldrows = rows;
    }

    /* Move cursor to right position. */
    rpos2 = (pwidth+poswidth+l.cols)/l.cols;

    /* Go up till we reach the expected position. */
    if (rows-rpos2 > 0) {
      snprintf(seq,64,"\x1b[%dA", rows-rpos2);
      _render_buffer_append(&ab,seq,strlen(seq));
    }

    /* Set column. */
    col = (pwidth+poswidth) % l.cols;
    if (col)
      snprintf(seq,64,"\r\x1b[%dC", col);
    else
      snprintf(seq,64,"\r");
    _render_buffer_append(&ab,seq,strlen(seq));
  }

  l.oldpos = l.pos;
  if (flags & REFRESH_WRITE) l.oldrpos = rpos2;

  _write_bytes(fd, ab.b, ab.len);
}

static void _refresh_with_flags(struct EditState *l, int flags) {
  _render(l,flags);
}

static void _refresh_line(struct EditState *l) {
  _refresh_with_flags(l,REFRESH_ALL);
}

/* Grow the editing buffer up to the configured interactive-input limit. */
static int _grow(struct EditState *l, size_t needed) {
  size_t newlen;
  char *newbuf;

  if (needed <= l.buflen) return 0;

  if (needed > l.buflen_max) return -1;

  /* Grow exponentially, but stop at the configured maximum before the
   * doubling would overflow or go past it. */
  newlen = l.buflen ? l.buflen : 16;
  while (newlen < needed) {
    if (newlen > l.buflen_max/2) {
      newlen = l.buflen_max;
      break;
    }
    newlen *= 2;
  }
  if (newlen < needed || newlen == SIZE_MAX) return -1;

  /* Allocate one extra byte for the nul terminator. */
  newbuf = Scope.realloc(l.buf, newlen + 1);
  l.buf = newbuf;
  l.buflen = newlen;
  return 0;
}

/* Insert bytes into l.buf without repainting the prompt. The paste path uses
 * this to first store the real pasted bytes, then mark their range as folded,
 * and only then refresh so raw pasted newlines are never printed directly. */
static int _insert_raw(struct EditState *l, const char *c, size_t clen) {
  size_t insert_pos = l.pos;

  if (clen > SIZE_MAX-l.len || _grow(l,l.len+clen) == -1)
    return -1;

  if (l.len == l.pos) memcpy(l.buf+l.pos,c,clen);
  else {
    memmove(l.buf+l.pos+clen,l.buf+l.pos,l.len-l.pos);
    memcpy(l.buf+l.pos,c,clen);
  }
  l.pos += clen;
  l.len += clen;
  l.buf[l.len] = '\0';
  _adjust_folds_after_insert(l,insert_pos,clen);
  return 0;
}

static void _insert(struct EditState *l, const char *c, size_t clen) {
  if (_insert_raw(l, c, clen) == -1)
    raise %(size-limit (operation "ReplInput.read") (limit 1048576));
  _refresh_line(l);
}

/* Move cursor on the left. Moves by one UTF-8 character, not byte. */
static void _move_left(struct EditState *l) {
  if (l.pos > 0) {
    l.pos -= _previous_edit_len(l, l.pos);
    _refresh_line(l);
  }
}

/* Move cursor on the right. Moves by one UTF-8 character, not byte. */
static void _move_right(struct EditState *l) {
  if (l.pos != l.len) {
    l.pos += _next_edit_len(l, l.pos);
    _refresh_line(l);
  }
}

/* Move cursor to the start of the line. */
static void _move_home(struct EditState *l) {
  if (l.pos != 0) {
    l.pos = 0;
    _refresh_line(l);
  }
}

/* Move cursor to the end of the line. */
static void _move_end(struct EditState *l) {
  if (l.pos != l.len) {
    l.pos = l.len;
    _refresh_line(l);
  }
}

/* Substitute the currently edited line with the next or previous history
 * entry as specified by 'dir'. */
#define LINENOISE_HISTORY_NEXT 0
#define LINENOISE_HISTORY_PREV 1
static void _recall(struct EditState *l, int dir) {
  if (l.history_len > 1) {
    const char *src;
    size_t len;
    struct EditFold f;

    /* Update the current history entry before to
     * overwrite it with the next one. */
    int current = l.history_len - 1 - l.history_index;
    Scope.free(l.history[current]);
    l.history[current] = Scope.memdup(l.buf, l.len + 1);
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
    if (_grow(l, len) == -1)
      raise %(size-limit (operation "ReplInput.read") (limit 1048576));
    memcpy(l.buf,src,len);
    l.buf[len] = '\0';
    l.len = l.pos = len;
    _fold_clear(l);

    /* History stores the real text, but not the original paste ranges.
     * If the recalled entry needs folding, create one display fold now
     * so text typed after recall remains outside the folded range. */
    if (_history_fold(l,&f))
      _fold_add(l,f.start,f.end);
    _refresh_line(l);
  }
}

/* Delete the character at the right of the cursor without altering the cursor
 * position. Basically this is what happens with the "Delete" keyboard key.
 * Now handles multi-byte UTF-8 characters. */
static void _delete(struct EditState *l) {
  if (l.len > 0 && l.pos < l.len) {
    size_t clen = _next_edit_len(l, l.pos);
    _adjust_folds_after_delete(l,l.pos,clen);
    memmove(l.buf+l.pos, l.buf+l.pos+clen, l.len-l.pos-clen);
    l.len -= clen;
    l.buf[l.len] = '\0';
    _refresh_line(l);
  }
}

/* Backspace implementation. Deletes the UTF-8 character before the cursor. */
static void _backspace(struct EditState *l) {
  if (l.pos > 0 && l.len > 0) {
    size_t clen = _previous_edit_len(l, l.pos);
    _adjust_folds_after_delete(l,l.pos-clen,clen);
    memmove(l.buf+l.pos-clen, l.buf+l.pos, l.len-l.pos);
    l.pos -= clen;
    l.len -= clen;
    l.buf[l.len] = '\0';
    _refresh_line(l);
  }
}

/* Delete the previous word, maintaining the cursor at the start of the
 * current word. Handles UTF-8 by moving character-by-character. */
static void _delete_previous_word(struct EditState *l) {
  size_t old_pos = l.pos;
  size_t diff;

  /* Skip spaces before the word (move backwards by UTF-8 chars). */
  while (l.pos > 0 && l.buf[l.pos-1] == ' ')
    l.pos -= _previous_edit_len(l, l.pos);
  /* Skip non-space characters (move backwards by UTF-8 chars). */
  while (l.pos > 0 && l.buf[l.pos-1] != ' ')
    l.pos -= _previous_edit_len(l, l.pos);
  diff = old_pos - l.pos;
  _adjust_folds_after_delete(l,l.pos,diff);
  memmove(l.buf+l.pos, l.buf+old_pos, l.len-old_pos+1);
  l.len -= diff;
  _refresh_line(l);
}

static char *_copy_text(const char *text) =>
  Scope.memdup(text, strlen(text) + 1);

static void _edit_prepare(
  struct EditState *l, ReplInput input, String prompt,
  ReplInputComplete complete, void *completion_context) {
  *l = (struct EditState) {0};
  l.input = input;
  input.ifd = STDIN_FILENO;
  input.ofd = STDOUT_FILENO;
  l.buf = Scope.malloc(LINENOISE_INITIAL_BUFLEN);
  l.buflen = LINENOISE_INITIAL_BUFLEN - 1;
  l.buflen_max = LINENOISE_MAX_LINE;
  l.prompt = prompt;
  l.plen = prompt.len();
  l.complete = complete;
  l.completion_context = completion_context;
  l.oldrpos = 1;
  l.buf[0] = '\0';

  l.history_len = input.history_len + 1;
  l.history = Scope.calloc(l.history_len, sizeof(char *));
  for (int i = 0; i < input.history_len; i++)
    l.history[i] = _copy_text(input.history[i]);
  l.history[l.history_len - 1] = _copy_text("");
}

static void _edit_close(struct EditState *l) {
  for (int i = 0; i < l.history_len; i++) Scope.free(l.history[i]);
  Scope.free(l.history);
  Scope.free(l.buf);
}

/* Make sure the temporary paste buffer can hold len+need bytes. Return -1 on
 * allocation failure or if the requested size is over PASTE_MAX_BYTES. */
static int _reserve_paste(char **buf, size_t *cap, size_t len, size_t need) {
  size_t want;
  char *nb;

  /* Nothing to do if the current paste buffer already has room for the
   * bytes collected so far plus the new bytes we want to append. */
  if (*cap >= len + need) return 0;

  /* Start small, then double like the line buffer. The cap avoids turning a
   * huge paste into an unbounded allocation attempt. */
  want = *cap ? *cap : 64;
  while (want < len + need) {
    size_t doubled = want*2;
    if (doubled <= want || doubled > PASTE_MAX_BYTES) {
      want = PASTE_MAX_BYTES;
      break;
    }
    want = doubled;
  }
  if (want < len + need) return -1;

  /* Scope.realloc(NULL, want) handles the first allocation too. */
  nb = Scope.realloc(*buf, want);
  *buf = nb;
  *cap = want;
  return 0;
}

/* Append bytes to the temporary paste buffer, growing both it and l.buf as
 * needed. Return -1 if the paste is too large or allocation fails. */
static int _append_paste(
  struct EditState *l, char **buf, size_t *cap, size_t *len,
  const char *s, size_t slen, size_t maxlen) {
  size_t needed;

  if (*len > maxlen || slen > maxlen-*len) return -1;
  if (*len > SIZE_MAX-slen) return -1;
  needed = *len+slen;
  if (l.len > SIZE_MAX-needed) return -1;
  if (_grow(l,l.len+needed) == -1) return -1;
  if (_reserve_paste(buf,cap,*len,slen) == -1) return -1;
  memcpy(*buf+*len,s,slen);
  *len = needed;
  return 0;
}

static int _read_byte(struct EditState *l, char *out) {
  while (1) {
    ssize_t count = read(l.input.ifd, out, 1);
    if (count == 1) return 1;
    if (count == 0) return 0;
    if (errno != EINTR) _io_fail(<read>);
  }
}

/* Read a bracketed paste until ESC[201~ and insert the real bytes. If folding
 * is needed, remember the inserted range so only rendering is shortened. */
static void _paste(struct EditState *l) {
  static const char END[] = "\x1b[201~";
  const size_t ENDLEN = sizeof(END)-1;
  char *buf = NULL;
  defer Scope.free(buf);
  size_t cap = 0, len = 0, match = 0;
  size_t maxlen = l.buflen_max ? l.buflen_max : l.buflen;
  int overflowed = 0;

  maxlen = maxlen > l.len ? maxlen - l.len : 0;
  if (maxlen > PASTE_MAX_BYTES) maxlen = PASTE_MAX_BYTES;
  /* Consume an excess folded paste before reporting the size limit. */
  if (l.fold_count == LINENOISE_MAX_FOLDS) maxlen = 0;

  while (1) {
    char c;
    if (!_read_byte(l, &c)) break;

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
        _append_paste(l,&buf,&cap,&len,END,match,maxlen) == -1)
        overflowed = 1;
      match = 0;
      if (c == END[0]) {
        match = 1;
        continue;
      }
    }

    if (!overflowed &&
      _append_paste(l,&buf,&cap,&len,&c,1,maxlen) == -1)
      overflowed = 1;
  }

  if (overflowed)
    raise %(size-limit (operation "ReplInput.read")
                       (limit 1048576));
  if (buf == NULL) return;

  {
    /* Normalize pasted CR and CRLF to LF, so the edit buffer uses one
     * internal newline representation. */
    size_t r = 0, w = 0;
    while (r < len) {
      if (buf[r] == '\r') {
        buf[w++] = '\n';
        r += (r+1 < len && buf[r+1] == '\n') ? 2 : 1;
      } else buf[w++] = buf[r++];
    }
    len = w;
  }

  if (_should_fold(buf,len)) {
    size_t start = l.pos;
    if (_insert_raw(l,buf,len) == -1)
      raise %(size-limit (operation "ReplInput.read")
                         (limit 1048576));
    _fold_add(l,start,start+len);
    _refresh_line(l);
  } else _insert(l,buf,len);
}

static void _replace_completion(
  struct EditState *l, size_t start, size_t end, String replacement) {
  size_t added = replacement.len(), removed = end - start;
  size_t length = l.len - removed + added;
  if (_grow(l, length) == -1)
    raise %(size-limit (operation "ReplInput.read") (limit 1048576));
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
  struct EditState *l, List candidates, Symbol kind, String heading) {
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

static void _show_completions(struct EditState *l, List candidates) {
  _refresh_with_flags(l, REFRESH_CLEAN);
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

static void _complete(struct EditState *l) {
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
    _replace_completion(
      l, completion.start, completion.end, replacement);
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

static Symbol _edit_feed(struct EditState *l) {
  char c, seq[3];
  if (!_read_byte(l, &c)) return <eof>;

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
      if (_overlaps_fold(l,prevstart,prevlen+currlen)) {
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
  case ESC:    /* escape sequence */
    /* Read the next two bytes representing the escape sequence.
     * Use two calls to handle slow terminals returning the two
     * chars at different times. */
    if (!_read_byte(l, seq) || !_read_byte(l, seq + 1)) break;

    /* ESC [ sequences. */
    if (seq[0] == '[') {
      if (seq[1] >= '0' && seq[1] <= '9') {
        char param[8];
        size_t plen = 1;
        char final = 0;

        param[0] = seq[1];
        while (plen < sizeof(param)) {
          char p;
          if (!_read_byte(l, &p)) break;
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
      while (length < utf8len && _read_byte(l, utf8 + length)) length++;
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
    _adjust_folds_after_delete(l,l.pos,l.len-l.pos);
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
  case CTRL_W: /* ctrl+w, delete previous word */
    _delete_previous_word(l);
    break;
  }
  return <editing>;
}

static ReplInputResult _read_interactive(
  ReplInput input, String prompt, ReplInputComplete complete,
  void *completion_context) {
  struct EditState edit;
  _edit_prepare(&edit, input, prompt, complete, completion_context);
  defer _edit_close(&edit);

  _enable_raw(input);
  defer _restore(input);
  _write_bytes(input.ofd, "\x1b[?2004h", 8);
  edit.cols = _terminal_columns(input.ifd, input.ofd);
  _write_bytes(input.ofd, prompt, prompt.len());

  Symbol status;
  while ((status = _edit_feed(&edit)) == <editing>) {}
  String text = status == <line> ? String.new(edit.buf) : NULL;
  _restore(input);
  _write_bytes(input.ofd, "\n", 1);
  return (ReplInputResult) { .status = status, .text = text };
}

/** Creates an interactive terminal owner with empty in-memory history. */
ReplInput ReplInput.new(void) {
  ReplInput input = Scope.calloc(1, sizeof(struct ReplInput));
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
  try { return _read_interactive(
    r, prompt, complete, completion_context); }
  catch %(alloc-fail *details): {
    _restore(r);
    Error.raise(<alloc-fail>, details);
  }
  catch %(size-limit *details): {
    _restore(r);
    Error.raise(<size-limit>, details);
  }
  catch %(io-fail *details): {
    _restore(r);
    Error.raise(<io-fail>, details);
  }
  return (ReplInputResult) { .status = <eof> };
}

/** Remembers one nonempty entry, suppressing an adjacent duplicate and
    evicting the oldest entry beyond 100. */
void ReplInput.remember(ReplInput r, String text) {
  if (!r || !r.open || !text || !text.len()) return;
  if (r.history_len && !strcmp(r.history[r.history_len - 1], text)) return;

  char *copy = Scope.memdup_in(&r.storage, text, text.len() + 1);
  if (r.history_len == REPL_HISTORY_MAX) {
    Scope.free(r.history[0]);
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
