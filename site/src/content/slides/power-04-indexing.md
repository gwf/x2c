---
slug: indexing
aliases: [counting]
section: power
home: true
order: 2
tab: indexing
title: Index marks the spot.
---

```x2c
~#include <assert.h>
// Store documents once; words refer to them by ID.
class Index { Array documents; Map words; } *;

void Index.init(Index index) {
  index.documents = []; index.words = {};
}

// Add each word once per document, regardless of case or repetition.
void Index.insert(Index index, String name, String text) {
  int id = index.documents.len();
  index.documents.push(name);
  foreach (String word in text.lower().words().iter().unique())
    index.words.setdefault(word, []).array().push(id);
}

// An unknown word has no matches; lookup does not change the index.
Array Index.find(Index index, String word)
  => index.words.getdefault(word.lower(), []);

~int main(void) {
~  Index index = Index.new();
~  index.insert("garden", "red roses red tulips");
~  index.insert("kitchen", "red apples green pears");
~  assert(index.find("RED") == [0, 1]);
~  assert(index.find("roses") == [0]);
~  int words = index.words.len();
~  assert(index.find("blue").len() == 0 && index.words.len() == words);
~  Array matches = index.find("roses");
~  puts(%"roses: $(index.documents[matches[0]])");
~  return 0;
~}
```

Collect document words into an index, then combine the indexed results. Maps, Arrays, and iterator operations make the useful structure visible in the program.
