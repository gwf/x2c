/* A native meta prototype that takes a handle and returns one might return
   or keep its argument, so its ownership cannot be inferred. */

typedef struct Widget *Widget;

meta Widget widget_wrap(Widget inner);

int main(void) { return 0; }
