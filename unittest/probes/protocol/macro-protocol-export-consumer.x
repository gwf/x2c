/* Consumer of imported macro-generated protocol adoptions. */

#include "macro-protocol-export-provider.x"

int main(void) {
  ExportOne a = Block.new(sizeof(int));
  ExportTwo b = Block.new(sizeof(int));
  a.append(&(int) { 3 }, 1);
  b.append(&(int) { 5 }, 1);
  return a.setindex(0, 7) + b.setindex(0, 11);
}
