# Third-party notices

The C-subset calibration algorithms, output formats, and paired C
implementations are derived from the [Computer Language Benchmarks
Game][game]. Their x2c programs are adaptations of the corresponding C
programs.

The Benchmarks Game repository and these program sources are distributed
under the [BSD 3-Clause License][game-license]. Copyright and contributor
notices are retained in each `benchmarks/*/{c,x2c}/main.*` file.

Program-specific attribution:

- `nbody`: copyright Brent Fulgham and Isaac Gouy; C program contributed by
  Christoph Bauer.
- `spectralnorm`: based on the program contributed by Sebastien Loisel.
- `fannkuchredux`: converted to C by Joseph Piche from the Java version by
  Oleg Mazurov and Isaac Gouy.

The expected-output files encode the results required by the corresponding
Benchmarks Game specifications:

- [n-body specification][nbody]
- [spectral norm specification][spectralnorm]
- [fannkuch-redux specification][fannkuchredux]

[LangArena][langarena] is the workload-family reference and prospective
integration target. The independently implemented x2c suite uses its
binary-trees, Brainfuck, `CLBG::Mandelbrot`, and `Etc::Sieve` workload
families, plus its matrix multiplication, Game of Life, quicksort, graph BFS,
calculator AST, and CSV parsing families. The word-frequency pair follows
LangArena's `Etc::Words` deterministic generator parameters and canonical
50,000-word/360-iteration configuration; its implementations and checksum are
original to this repository. LangArena is distributed under the MIT License.

All original harness code and documentation in this subtree are covered by
its [BSD 3-Clause license](LICENSE).

## Benchmarks Game license notice

Copyright (c) 2004-2008 Brent Fulgham, 2005-2015 Isaac Gouy. All rights
reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

- Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.
- Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.
- Neither the name of "The Computer Language Benchmarks Game" nor the name of
  "The Computer Language Shootout Benchmarks" nor the names of its
  contributors may be used to endorse or promote products derived from this
  software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

[game]: https://salsa.debian.org/benchmarksgame-team/benchmarksgame
[game-license]: https://salsa.debian.org/benchmarksgame-team/benchmarksgame/-/blob/master/LICENSE.md
[nbody]: https://benchmarksgame-team.pages.debian.net/benchmarksgame/description/nbody.html
[spectralnorm]: https://benchmarksgame-team.pages.debian.net/benchmarksgame/description/spectralnorm.html
[fannkuchredux]: https://benchmarksgame-team.pages.debian.net/benchmarksgame/description/fannkuchredux.html
[langarena]: https://github.com/kostya/LangArena
