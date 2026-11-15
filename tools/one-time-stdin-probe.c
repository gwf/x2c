#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <fcntl.h>
int main(int argc, char **argv) {
  char *line = NULL; size_t size = 0;
  if (getline(&line, &size, stdin) < 0) return 1;
  printf("first: %s", line); fflush(NULL);
  fprintf(stderr,"before fork offset=%ld\n",(long)lseek(0,0,SEEK_CUR));
  pid_t pid = fork();
  if (!pid) {
    if (argc > 1) {
      if (close(STDIN_FILENO)) _exit(2);
    }
    if (!freopen("/dev/null", "r", stdin)) _exit(3);
    if (fileno(stdin) != STDIN_FILENO || fgetc(stdin) != EOF) _exit(4);
    _exit(0);
  }
  int status; waitpid(pid,&status,0);
  if (!WIFEXITED(status) || WEXITSTATUS(status)) return 5;
  fprintf(stderr,"after child offset=%ld\n",(long)lseek(0,0,SEEK_CUR));
  for (int count=0; count<10 && getline(&line,&size,stdin)>=0; count++) printf("next: %s",line);
  free(line); return 0;
}
