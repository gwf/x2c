---
title: I fucking love to code.
kicker: Twenty years of C, Lisp, and a language I couldn't leave alone.
---

That's the most honest explanation I can give for x2c.

I've been writing some version of this language for about twenty years.
This is at least the third incarnation, possibly the fourth, depending on
how you count. A small group of friends has been hearing about it for most
of that time. Everyone else has been spared until now.

It was what I worked on during vacations, when I was bored, and whenever
I could steal enough time to get lost in an idea. It had no customers, no
release date, and no particular reason to exist beyond the fact that I
loved making it. For a remarkably long time, it was about ninety percent
finished.

## A language to think in

For years, I wrote the demanding parts of my programs in C, then built a
Lisp interpreter to experiment with them. C gave me performance and control.
Lisp gave me the flexibility to explore ideas quickly.
x2c grew out of wanting both in one language.

Writing the x2c compiler in the x2c language meant living with my own
design decisions.
The best new features made the compiler's source shorter and clearer.
Some experiments failed spectacularly; others became things I wouldn't
want to program without. The language took shape through using it.

That is what kept me interested. I was learning about computation by
building something I wanted to use.

## The last ten percent

In the summer of 2026, coding agents finally became useful on x2c. Earlier
ones had struggled with a language they hadn't encountered on the public
web. Over a month or two, they helped me finish documentation, expand the
tests, and work through the details I had put off for years.

A compiler that builds itself gave us a demanding check on their work:
each rebuilt compiler had to build the next and reproduce the same output.
That doesn't catch every bug, but it tests whether changes hold together
throughout the compiler. Deciding whether the code was clear and worth
keeping still took my judgment.

I used to be able to say I had written every line. I can't say that anymore.
The design is mine; the agents deserve substantial credit for helping me
finish it. Without them, it would probably still be almost ready.

## Where an idea can take you

x2c has taught me more about computation than anything else I've ever worked on.
That's the reason for sharing it. Use it, read its source, change something
that bothers you. See what you can learn from it, or what you can make it do.

I hope you find it useful. But I'd be just as happy if you found yourself
staying up a little too late.
