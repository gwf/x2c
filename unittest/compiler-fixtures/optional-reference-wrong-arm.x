static int use(int &value) => value;

static int pick(int &?value) => value ? 0 : use(value);

int main(void) => pick(NULL);
