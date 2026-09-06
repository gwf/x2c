typedef struct Color { int r; } Color;
typedef Color Color;
int main(void) { Color c = {5}; return c.r; }
