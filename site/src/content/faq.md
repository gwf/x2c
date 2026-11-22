## What is x2c, and who is it for?

x2c is C with ideas borrowed from Lisp: dynamic values, useful collections,
and macros that work with the structure of a program. I built it for the
way I like to think and code. If you like C's directness but wish it did
more of the tedious work, you might like it too.

## What kinds of programs is it suited for?

Command-line tools, native applications, language tools, and experiments
that benefit from C libraries without quite so much C bookkeeping. The
compiler and runtime are themselves written in x2c. The
[examples](../../examples/) are the best place to judge whether it suits
something you want to build.

## Which platforms and tooling are supported?

macOS 15 or later and Linux with glibc 2.38 or later, on Apple Silicon/ARM64
and x86-64. Windows support is through WSL2. There is a VS Code extension
and a language server for editors with an LSP client. Native debugging
uses ordinary C tools, with source mapping back to x2c. See
[installation](../../docs/guide/installation.html) and
[editor support](../../docs/reference/cli.html#editors) for the details.

## What does x2c add to C?

Collections, dynamic values, pattern matching, scoped allocation,
exceptions, threads, classes, and compile-time macros written in x2c.
You can use those features where they help and write ordinary C elsewhere.
The [language walkthrough](../../examples/language/) shows how the pieces
fit together.

## How does Lisp influence x2c?

Lisp shaped how x2c represents values and programs, and the idea that a
language should be something you can extend. Lists, symbols, and structured
macros are part of that inheritance. You don't need to write Lisp to use
x2c: compile-time code is x2c too. There is also an embeddable Lisp
interpreter for programs that want one.

## Why use x2c instead of C++, Rust, Zig, or Python?

I wouldn't choose a language from a list of features alone. I wanted C's
directness, Lisp's flexibility, and code I enjoyed reading. x2c is my
attempt at that combination. Try a small program and see whether it fits
how you think. Ecosystem, safety requirements, and long-term support may
matter more to your project than my preferences.

## Can I use existing C code, headers, and libraries?

Yes. x2c generates C and uses ordinary C headers and libraries. Existing C
sources can also be compiled alongside x2c sources. That doesn't mean
every C codebase will compile unchanged as x2c; preprocessing and
compiler-specific extensions can need attention. The
[C library packages](../../#packages) provide examples of practical
integration.

## How does x2c compile programs, and what tools does it require?

x2c translates your program to C, then invokes a C compiler to produce a
native executable. An installed release needs `cc`: Clang 15 or later,
or GCC. Building x2c from source also needs `ar`, GNU Make, Git, and Bash.
You don't need an existing x2c compiler; the repository includes generated
C for the bootstrap.

## How do static types and dynamic values work together?

Ordinary C types stay statically typed. `Var` can hold values of different
types, and collections can hold those values together. x2c handles boxing,
unboxing, and conversions at the boundaries. You can keep an inner loop
statically typed and use dynamic values where they make the surrounding
program simpler. The [values guide](../../docs/guide/values.html) explains
the rules.

## How does memory management work, and what safety guarantees does x2c provide?

There is no garbage collector. Scopes reclaim mutable allocations, while
interned strings and lists live in pools, usually for the life of the
process. Shorter-lived pools are available. C pointers and C's obligations
remain: x2c does not promise memory safety. Scoped cleanup and lifetime
diagnostics help with some of the work. See the
[memory guide](../../docs/guide/memory.html).

## What can x2c's macros do?

Macros work with parsed program structure, so they can do more than
substitute text. They can introduce syntax and generate or transform
expressions and declarations. Compile-time functions are written in x2c,
using the same language you're extending. Much of x2c's own surface is
built this way. The [macro guide](../../docs/guide/macros.html) starts with
small examples.

## How does x2c perform compared with C and other languages?

The generated C gets the benefit of the native compiler's optimizer.
Dynamic values, allocation, and higher-level operations still have costs.
There isn't one useful speed ratio for a language. The
[shootout](../../examples/shootout/) includes programs and measurements
you can inspect; your own workload is the comparison that matters.

## How mature is x2c, and how much compatibility should I expect between releases?

It has a long history, a self-hosting compiler, and a substantial runtime,
but it is still experimental and actively changing. Language details and
APIs can change between releases. If you're building something you depend
on, pin a version and test before upgrading. Twenty years of tinkering
isn't the same thing as twenty years of production use.

## What is the quickest way to try x2c and learn the language?

Start with the runnable [examples](../../examples/essentials/), then
[install the compiler](../../#install) and change a small program. The
[language walkthrough](../../examples/language/) gives you a broader tour;
the [book](../../docs/) fills in the details. You don't need to learn the
macro system before writing something useful.

## What role did AI play in building x2c?

I wrote the original compiler and library over many years. In the summer
of 2026, coding agents became useful enough to help finish documentation,
expand tests, and work through the backlog. Since then, they've written
and rewritten substantial parts of the project. Calling this a
human-written codebase would now be misleading. The [Backstory](../)
has the longer version.

## What license does x2c use?

The [Apache License 2.0](https://github.com/gwf/x2c/blob/main/LICENSE).
Third-party libraries have their own licenses; those are documented with
their packages.

## Are bug reports, ideas, and contributions welcome?

Yes. A small reproducer makes a bug report much easier to use. For a
substantial change, open an issue before spending a lot of time on it.
Documentation fixes are welcome too. The
[contribution guide](https://github.com/gwf/x2c/blob/main/CONTRIBUTING.md)
explains the process. I can't promise that every suggestion or pull
request will fit the project.

## Who maintains x2c, and what support or future development should users expect?

I'm Gary Flake, and I maintain x2c. This is a personal project, with no
support team or promised schedule. I intend to keep working on it, but
I can't commit to response times, fixes, or particular features. Use the
[issue tracker](https://github.com/gwf/x2c/issues) for bugs and ideas, and
make your plans with those limits in mind.
