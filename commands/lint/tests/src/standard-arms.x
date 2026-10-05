/* Dispatch arms at and above the three-line threshold. */
int switch_arms(int choice) {
  switch (choice) {
    case 0:
      choice++;
      return choice;
    case 1:
      choice++;
      choice++;
      return choice;
    default: return 0;
  }
}

int match_arms(Var choice) {
  match (choice) {
    case %(zero): {
      return 0;
    }
    case %(one): {
      choice = 2;
      return choice;
    }
    default: return 0;
  }
}
