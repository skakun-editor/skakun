# Skakun

A robust and hackable hex and text editor for your terminal.

This project is still very much in its infancy and its success is, as of yet, undetermined.

## Design goals

1. Optimized for huge files
2. Works in any standard/modern environment (SSH, virtual console, terminal emulators)
3. Not just a text editor - edits binary files too
4. Let the user modify every behavior (Lite-or-Emacs-style)
5. Leave behind standalone pieces of software of universal utility (actually usable Treesitter grammars, Lua interpreter with multithreading)
6. Human-readable and informative codebase, no LLMs allowed
7. Make the most out of the terminal
8. More forward-looking than backwards-compatible
9. And all the other features you expect: autosave, easily discoverable UI actions, GVfs support, multiple selections, spell checking, Treesitter-based syntax highlighting, Unicode support

## Design choices

Establishing the first goal meant ruling out most popular buffer data structures, such as gap buffers and ropes, and going for one of those obscure data structures whose names text editor creators often like to throw around like buzzwords. Such big talk is, in my opinion, rather indicative of a person's incomplete understanding of algorithms and data structures. The truest description of what I used is: a [fully persistent](https://en.wikipedia.org/wiki/Persistent_data_structure) [self-balancing binary search tree](https://en.wikipedia.org/wiki/Self-balancing_binary_search_tree) with implicit keys, whose nodes store views into text fragments like a [piece table](https://en.wikipedia.org/wiki/Piece_table). Which BST? Doesn't matter, I just picked the simplest one I knew.

Swapping out one main data structure, of course, isn't enough to support huge files. All the other peripheral ones, such as the buffer location cache, also have to be upgraded. And the algorithms too have to be carefully crafted and sometimes made to run asynchronously in the background, as is with syntax highlighting and spell checking (here's where the "fully persistent" part comes into play). And for that the language (Lua) too has to be upgraded to support preemptive multithreading. You also cannot load the whole multi-gigabyte file into RAM when opening it and instead, you have to ask the operating system to create an on-demand read-only view of the file in your program's memory (i.e. ["memory-mapped file"](https://en.wikipedia.org/wiki/Memory-mapped_file)).

The second goal didn't require any smart solutions, just laborious and meticulous engineering. To elaborate further, the following terminals have first-class support: FreeBSD console, GNOME Terminal, kitty, Konsole, Linux console, st, Windows Terminal, Xfce Terminal, xterm. That is, Skakun's terminal library has been tested to work on them.

Pursuing the fourth goal more or less forces you to use a dynamic programming language - a language without an additional compilation step, allowing rapid iteration, and permitting retroactive replacement of individual methods of a class, i.e. "monkey patching". Well, some dynamic languages don't support monkey patching and some are so complex that they make it feel really hacky or difficult. Out of all the languages out there, Lua happened to support monkey patching and be so simple that you can have a mental model of precisely everything that goes on in your code. That simplicity really convinced me to use it as the scripting language for Skakun. The only thing it didn't have was multithreading, which I had to implement myself.

Of course, writing the whole application in Lua would fall short of the first goal. This naturally led to a "dual-language architecture", in which you combine a slow and high-level language like Lua and a fast and low-level language like Zig to write the glue code (the "80%" of the codebase) and the heavy-lifting algorithms (the "20%") respectively.

## Setup

### Building from source

1. Make sure you have [Zig 0.15.2](https://ziglang.org/download/#release-0.15.2), Enchant, GIO, GIRepository and ncurses's libtinfo (`libenchant-2-dev libgio2.0-dev libgirepository-2.0-dev libtinfo-dev` on Debian) installed on your system.
2. Compile using `zig build -Doptimize=ReleaseSafe`.
3. Install using `rsync -av zig-out/ /usr/local/`. This simply copies files merging subdirectories.
