/* One worker writes counts; main reads only after Thread.run joins both.
   The parent owns the Map and Channel throughout. Strings are canonical.
   Channel capacity bounds queued messages, not the canonical-value pool. */
int main(void) {
  auto {
    Channel lines = auto Channel.new(<string>, 2);
    Map counts = {};
    Thread.run([
      %!() => {
        defer lines.close();
        foreach (String line in %("tea and cake" "more cake")) lines.send(line);
      },
      %!() => {
        foreach (String line in lines)
          foreach (String word in line.words()) counts[word] += 1;
      }
    ]);
    printf("threads: cake %s, tea %s\n", counts["cake"], counts["tea"]);
  }
  return 0;
}
