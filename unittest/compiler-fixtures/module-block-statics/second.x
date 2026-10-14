static int local = 2;
module int doubled(void) => shared_count * 2;
module int second_local(void) => local;
