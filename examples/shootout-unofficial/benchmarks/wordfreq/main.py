#!/usr/bin/env python3

from collections import Counter
import sys


random_state = 42


def next_int(maximum):
    global random_state
    random_state = (random_state * 3877 + 29573) % 139968
    return random_state * maximum // 139968


def make_text(word_count):
    words = []
    for _ in range(word_count):
        length = next_int(4) + next_int(3) + 3
        word = (chr(ord("a") + next_int(26)) for _ in range(length))
        words.append("".join(word))
    return " ".join(words)


def count_words(text):
    counts = Counter(text.split())
    weighted = sum(len(word) * count for word, count in counts.items())
    return len(counts) + weighted


word_count, repetitions = map(int, sys.argv[1:])
text = make_text(word_count)
checksum = 0
for _ in range(repetitions):
    checksum = (checksum * 33 + count_words(text)) & 0xFFFFFFFFFFFFFFFF
print(checksum)
