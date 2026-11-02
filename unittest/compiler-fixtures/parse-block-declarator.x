/*  parse-block-declarator.x -- x2c cannot spell a block pointer in the C
    it emits, so a `^` declarator is rejected where it is written.
*/
typedef void (^Block)(void);

int main(void) { return 0; }
