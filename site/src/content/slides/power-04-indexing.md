---
slug: indexing
section: power
tab: indexing
---

```x2c
~#include <assert.h>
// Store documents once; words refer to them by ID.
typedef struct Index { Array documents; Map words; } *Index;

Index Index.new(void) {
  Index index = Scope.malloc(sizeof(struct Index));
  index.documents = %[]; index.words = %{};
  return index;
}

// Add each word once per document, regardless of case or repetition.
void Index.add(Index index, String name, String text) {
  int id = index.documents.len();
  index.documents.push(name);
  foreach (String word, text.lower().words().iter().unique())
    index.words.setdefault(word, %[]).array().push(id);
}

// An unknown word has no matches; lookup does not change the index.
Array Index.find(Index index, String word)
  => index.words.getdefault(word.lower(), %[]);

~int main(void) {
~Index index = Index.new();
~index.add("garden", "red roses red tulips");
~index.add("kitchen", "red apples green pears");
~assert(index.find("RED") == %[0, 1]);
~assert(index.find("roses") == %[0]);
~int words = index.words.len();
~assert(index.find("blue").len() == 0 && index.words.len() == words);
~Array matches = index.find("roses");
~puts(%"roses: ${index.documents[matches[0]]}");
~return 0;
~}
```

`Index` combines an `Array` of document names with a `Map` from words
to document IDs. `Iter.unique` prevents duplicate IDs within a document.
`Index.find` ignores case and returns IDs in insertion order; an unknown
word yields an empty Array without changing the index.
