/* A generated constructor participates in the dependency path. */
class OrderBox struct { int value; } *;
void OrderBox.init(OrderBox box) { box.value = 1; }
int main(void) {
  OrderBox box = OrderBox.new();
  return box.value;
}
