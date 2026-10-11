typedef struct Reading {
  int value;
} Reading;

protocol Readable(T) {
  int T.read(T);
}
