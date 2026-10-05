void report_error(int code, String message);

macro Stmt $report.fixture.failure() {
  report_error(1, "expected a count");
}

void report_variable(String message) {
  report_error(1, message);
}
