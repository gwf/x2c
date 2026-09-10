/*  module-names.x -- Print the state names of the native layers.

    verify-python.py compares each line with the keys of the matching
    Python module's state_dict(), which is where these names come from:
    x2c prints what libtorch enumerates.
*/

import "torch" with Tensor, Module;

static void _print(String kind, Module m) {
  printf("%s", kind);
  foreach (List pair, m.named_parameters()) printf(" %s", pair[0].str());
  foreach (List pair, m.named_buffers()) printf(" %s", pair[0].str());
  printf("\n");
}

int main(void) {
  Scope.retain();
  defer Scope.release();
  _print("Conv2d", Module.conv2d(1, 8, 3));
  _print("Conv1d", Module.conv1d(2, 4, 3));
  _print("BatchNorm2d", Module.batch_norm2d(3));
  _print("BatchNorm1d", Module.batch_norm1d(3));
  _print("LayerNorm", Module.layer_norm(%(4)));
  _print("LSTM", Module.lstm(3, 4, 1, 1));
  _print("GRU", Module.gru(3, 4, 1, 1));
  _print("Embedding", Module.embedding(5, 3));
  _print("Linear", Module.linear(3, 2));

  /* A sequential root names its children by position, as Python does. */
  Module sequence = Module.sequential();
  sequence.push(Module.linear(3, 4));
  sequence.push(Module.relu());
  sequence.push(Module.linear(4, 2));
  _print("Sequential", sequence);
  return 0;
}
