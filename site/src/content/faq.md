## What is x2c, and who is it for?

x2c is a superset of C with a strong Lisp influence: dynamic values,
collections, and macros that work with program structure. I built it for
programmers who like C's control and access to native libraries, but want
less bookkeeping and more room to extend the language.

## What kinds of programs is it suited for?

x2c is especially well suited to prototyping. You can put an idea together
quickly, then refine it into production code a piece at a time. Start with
the built-in types and methods and replace them with more specialized code
wherever performance or control matters. The prototype can grow into the
finished program without a rewrite in another language.

x2c is more versatile than its C ancestry might suggest. x2c is
comfortable with command-line tools, scripts, graphical applications,
multithreaded services, and embedded languages, and it can target WebAssembly
too. I like being able to move among those kinds of programs without
changing languages or carrying a large toolchain.

The [examples](../../examples/) are the best place to judge whether it suits
something you want to build.

## Which platforms and tooling are supported?

macOS 15 or later and Linux with glibc 2.38 or later, on Apple Silicon/ARM64
and x86-64. Windows support is through WSL2. There is a
[VS Code extension](https://marketplace.visualstudio.com/items?itemName=x2c-lang.x2c-syntax)
and a language server for editors with an LSP client. Native debugging
uses ordinary C tools, with source mapping back to x2c. See
[installation](../../docs/guide/installation.html) and
[editor support](../../docs/reference/cli.html#editors) for the details.

## What does x2c add to C?

x2c adds strings, collections, dynamic values, pattern matching, lambdas,
and closures. `foreach` works across collections and other types that
support iteration. Scoped allocation, automatic cleanup, exceptions, and
threads take care of more of the machinery around your code.

It also adds classes, modules with clean namespaces, and package management
for working with native libraries. Compile-time macros and meta-functions
let you generate and transform code using x2c itself.

You can use these features where they help and keep ordinary C elsewhere.
The [language walkthrough](../../examples/language/) shows how the pieces
fit together.

## How does Lisp influence x2c?

Lisp's deepest influence is that x2c is its own metalanguage: you can
metaprogram x2c in x2c. Code is data you can inspect, match, and transform
using the language itself.

You don't have to metaprogram to use x2c. I've used that extensibility
mainly to make ordinary programming simpler: a small set of language
additions lets the compiler handle conversions and boilerplate that you
would otherwise write yourself. You benefit from that machinery even if
you never write a macro.

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
remain. While x2c does not promise memory safety, its scoped memory model
makes it straightforward to write fast, memory-safe code by following one
simple rule: an object's lifetime must stay within its enclosing scope.
See the
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
the [book](../../docs/) fills in the details. You don't need macros,
meta-functions, or any of the fancy stuff to get started. x2c is happy to
flirt or casually date before you get engaged or married. Use as little or
as much of the language as you like.

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

I am Gary William Flake, and I wrote x2c. This is a personal project, with no
support team or promised schedule. I intend to keep working on it, but
I can't commit to response times, fixes, or particular features. Use the
[issue tracker](https://github.com/gwf/x2c/issues) for bugs and ideas, and
make your plans with those limits in mind.

## Your name sounds familiar. Do I know you from somewhere?

Possibly. I wrote *The Computational Beauty of Nature*, founded Yahoo!
Research Labs and Microsoft Live Labs, later founded Clipboard, and have
been involved with a bunch of other startups. You may have also seen my
TED talk. None of that explains how I ended up writing a programming
language, but here we are.
