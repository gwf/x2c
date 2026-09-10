/*  tic-tac-toe.x -- You play X; an editable Lisp program plays O. */

static char board[] = "123456789";
static int lines[8][3] = {
  {0, 1, 2}, {3, 4, 5}, {6, 7, 8},
  {0, 3, 6}, {1, 4, 7}, {2, 5, 8},
  {0, 4, 8}, {2, 4, 6},
};

static int _won(char player) {
  for (int i = 0; i < 8; i++)
    if (board[lines[i][0]] == player && board[lines[i][1]] == player &&
        board[lines[i][2]] == player) return 1;
  return 0;
}

static int _empty(int square) {
  return square >= 1 && square <= 9 && board[square - 1] != 'X' &&
    board[square - 1] != 'O';
}

$lisp.binding(game, "empty?")
static Var _open(int square) {
  if (_empty(square)) return <true>;
  return %();
}

$lisp.binding(game, "wins?")
static Var _wins(int square, String player) {
  if (!_empty(square)) return %();
  char saved = board[square - 1];
  board[square - 1] = player == %"X" ? 'X' : 'O';
  int won = _won(board[square - 1]);
  board[square - 1] = saved;
  if (won) return <true>;
  return %();
}

static void _show_board(void) {
  for (int row = 0; row < 3; row++) {
    int i = row * 3;
    printf(" %c | %c | %c\n", board[i], board[i + 1], board[i + 2]);
    if (row < 2) puts("---+---+---");
  }
}

int main(int argc, char **argv) {
  if (argc != 2) {
    Stderr.puts("usage: tic-tac-toe STRATEGY.xlisp\n");
    return 2;
  }
  Lisp lisp = Lisp.new();
  defer lisp.destroy();
  $lisp.install(lisp, game);
  File strategy = File.open(argv[1], "r");
  defer strategy.close();
  Lisp.eval_file(lisp, strategy);
  puts("You are X. Lisp is O. Enter an empty square, 1-9.");
  _show_board();

  for (int turn = 0; turn < 9; turn++) {
    char player = turn % 2 ? 'O' : 'X';
    int square = 0;
    if (player == 'X') {
      while (!_empty(square)) {
        Stdout.puts("Your move: ");
        Stdout.flush();
        String input = Stdin.readline();
        if (!input) { puts("\nGoodbye."); return 0; }
        input = input.strip(NULL);
        square = input.len() == 1 ? input[0] - '0' : 0;
        if (!_empty(square)) puts("Choose an empty square from 1 to 9.");
      }
    }
    else {
      square = lisp.eval(%(choose-move));
      if (!_empty(square)) {
        Stderr.puts("Lisp chose an occupied or invalid square.\n");
        return 1;
      }
      printf("Lisp plays %d.\n", square);
    }
    board[square - 1] = player;
    _show_board();
    if (_won(player)) {
      puts(player == 'X' ? "You win." : "Lisp wins.");
      return 0;
    }
  }
  puts("Draw.");
  return 0;
}
