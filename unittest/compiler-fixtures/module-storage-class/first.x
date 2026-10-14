module typedef struct tally_node { int weight; } tally_node;
module int tally_total = 1;
module void tally_add(tally_node node) { tally_total += node.weight; }
