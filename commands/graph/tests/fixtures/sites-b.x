static void shared_site(int value) {
  (void) value;
}

void second_shared_caller(void) {
  shared_site(2);
}
