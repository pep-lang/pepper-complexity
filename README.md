# pepper-complexity

`pep-complexity` measures how hard each function of a
[Pepper](https://github.com/pep-lang/pepper) program is to understand, as
[complexipy](https://github.com/rohaquinlop/complexipy) does for Python and
[gocognit](https://github.com/uudashr/gocognit) for Go. For every function
it reports two scores from one walk of the body:

- **cognitive complexity**, after SonarSource's white paper
  ["Cognitive Complexity"](https://www.sonarsource.com/docs/CognitiveComplexity.pdf),
  as gocognit implements it. It is the main score: it sets the order of the
  output and what `--max` checks.
- **cyclomatic complexity** (McCabe): the number of paths through the
  function, one plus each decision.

It reads source with the Pepper compiler's own parser, so it accepts
what the compiler accepts. Its reference:
<https://pep-lang.github.io/pepper-complexity/>.

## Installing

```sh
pepper package install pep-lang/pepper-complexity
```

builds `pep-complexity` and puts it in the Pepper home's `bin`.

## Using it

```sh
pep-complexity runtime/ tools/          # every function, most complex first
pep-complexity --max 15 src/            # exit 1 when any is over 15, listing those
pep-complexity --top 10 --json src/     # the ten most complex, as JSON
pep-complexity --max 25 --baseline allowed.txt --exclude '**/*_test.pep' src/
```

Each path is a `.pep` file, or a directory, which stands for every `.pep`
file under it, skipping directories whose names start with `.` (`.git`, a
project's `.pep`). A file is named as the output names it: the path given,
with `/` on every system and no leading `./`.

| Option | What it does |
| --- | --- |
| `<paths>...` | The files, and directories to search for `.pep` files; at least one |
| `--max <N>` | Lists only the functions whose cognitive score is over `N` (0 or more), and exits with 1 if there is any |
| `--top <N>` | Lists only the first `N` functions, after `--max`; `N` is 1 or more. It does not change the exit status |
| `--baseline <FILE>` | With `--max`, allows the functions `FILE` lists, each up to its score there (see [Baselines](#baselines)) |
| `--write-baseline <FILE>` | With `--max`, writes every function over it to `FILE` as a baseline, and lists nothing |
| `--exclude <GLOB>` | Skips the files whose name matches `GLOB`, such as `**/*_test.pep` or `**/testdata/**`; repeatable. The glob language is the runtime's `io.glob_matches`: `*` stays within one folder, `**` spans any number |
| `--json` | Writes a JSON array instead of lines |
| `-h`, `--help` | Shows the help |
| `-V`, `--version` | Shows the version |

### Output

One line per function, sorted by cognitive score, highest first; equal
scores by cyclomatic score, then in file and line order:

```text
src/build.pep:1218 _build 347 180
src/main.pep:63 _main 311 250
```

Each line is the file and the line of the function's name, the name, the
cognitive score and the cyclomatic score. A method is `Type.name`, a
constructor `Type.construct`, a destructor `Type.destruct`, a property's
accessor `Type.property.get` or `Type.property.set`, and a method of an
`extend` block is named after the extended type, `int.doubled`. File names
use `/` on every system.

With `--json`, the same functions in the same order:

```json
[
  {
    "file": "src/build.pep",
    "line": 1218,
    "name": "_build",
    "cognitive": 347,
    "cyclomatic": 180
  }
]
```

A file that does not parse is reported on standard error, clang-style
(`src/bad.pep:2:13: error: expected ';'`), and the others are still scored.

### Exit status

- 0: every file was scored, and no function is over `--max` (that the
  baseline does not allow)
- 1: a file or the baseline could not be read or parsed, or a function is
  over `--max` (that the baseline does not allow)
- 2: a usage error, such as no paths

### Baselines

A baseline lets `--max` gate new code in a project that already has
functions over it: it lists those functions, and each may stay as it is
or improve, but not get worse. With `--baseline FILE`, `--max N` fails
only on a function over `N` that `FILE` does not list, or on one whose
score went over the one listed; it lists just those.

```text
# The functions allowed over pep-complexity --max 25, each with the
# cognitive score it may not go over: `path name score`. Written by
# --write-baseline; lower or remove a line as its function improves.
src/build.pep _build 347
src/main.pep _main 311
```

One function per line, `path name score`, sorted by path and then name, so
a change to it diffs as the functions it changes. A line starting with `#`
is a comment. A function is known by its file and name, not its line,
which shifts as the file changes; overloads share a line, which holds the
highest of their scores. The paths are the names the output gives, so run
it from the same folder with the same paths each time.

A listed function whose score went down, or that is no longer over `N`
(improved, renamed, excluded or deleted), is fine, and gets a note on
standard error, so the file can shrink:

```text
pep-complexity: note: src/main.pep: '_main' is down to 290 from 311: lower it in the baseline
pep-complexity: note: src/old.pep: 'gone' is no longer over 25: remove it from the baseline
```

`--write-baseline FILE` writes the baseline of the current run: every
function over `--max`, after `--exclude`. A line the file cannot read is an
error at that line (`allowed.txt:3:27: error: expected a score of 0 or
more`).

## What counts

A function is each free function, and each method, constructor, destructor
and property accessor of a struct, enum, trait or `extend` block, that has
a body. `extern` declarations, a trait's methods without a body, and `get;`
and `set;` are not scored. A closure is part of the function it is written
in.

Cognitive complexity adds an increment for each break in the linear flow;
a structure marked "+ nesting" below also adds how deeply it is nested.
Nesting goes one deeper inside the body of each of those structures and
inside each closure. Cyclomatic complexity starts at 1 and adds 1 for each
decision.

| Construct | Cognitive | Cyclomatic | Why |
| --- | --- | --- | --- |
| `if` | +1 + nesting | +1 | the white paper's `if` |
| `else if` | +1, no nesting | +1 | the white paper's "hybrid" increment: the reader already holds the `if` |
| `else` | +1 | 0 | another branch to follow, but no new decision |
| `cond ? a : b` | +1 + nesting | +1 | an `if` as an expression, as the white paper counts it |
| `match`, statement or expression | +1 + nesting, once for all its arms | +1 per arm but `else` | a `switch`: one structure however many cases; McCabe counts each case |
| a `match` arm's guard | 0, but its `&&` and `\|\|` count | 0, but its `&&` and `\|\|` count | part of the arm's condition |
| `for` | +1 + nesting | +1 | a loop |
| `while` | +1 + nesting | +1 | a loop |
| `with` | 0 | 0 | a scope, like Python's `with`, which the white paper does not count |
| `with ... else` | +1 + nesting, and +1 for the `else` | +1 | it chooses between two blocks, as `if ... else` does |
| `break`, `continue` | 0 | 0 | the white paper counts only jumps to a label |
| `break label`, `continue label` | +1 | 0 | the white paper's jump to a label |
| a run of `&&` or `\|\|` (or `and`, `or`) | +1 per run of one operator | +1 per operator | `a && b && c` is +1, `a && b \|\| c` +2; parentheses do not end a run, `!` does |
| `?`, propagating an error or an empty optional | 0 | +1 | an early return: another path, but the white paper does not count early exits |
| a call to the function itself | +1 per call | 0 | recursion, counted per call as gocognit does: by name, or as `this.name` in a method |
| a closure | 0, nesting +1 inside | 0 | the white paper's nested lambdas |

Pepper has no `try`/`catch` or `goto`; `?` is its error propagation, and
`return` counts nothing, as in the white paper.

## Limits

- The parser is the compiler's at the release `pep.toml` pins (see
  below), so syntax newer than that release is a parse error.
- Recursion is found by name: a call to an overload of the same name
  counts, and recursion through another function does not.

## How it uses the compiler's parser

The parser (`compiler.parse`) and the lexer it reads (`syntax`) are
folders of pep-lang/pepper's `tools/`, not a package of their own, and the
repository has no root `pep.toml`, so no workspace a dependency could name
a member of. `pep.toml` therefore depends on the whole repository at a
release tag, which a Git dependency allows without a `pep.toml`, and puts
its `tools/` folder, in [the folder the project's dependencies live
in](https://github.com/pep-lang/pepper/blob/main/docs/src/tools/projects.md#where-dependencies-live),
on the import path:

```toml
[build]
include = [".pep/deps/github.com/pep-lang/pepper/tools"]

[dependencies]
pepper = { github = "pep-lang/pepper", tag = "v0.12.0" }
```

Moving the tag to a newer release lets the tool read that release's
syntax. The cost is the fetch: the first build checks the whole repository
out (about 300 MB) into `.pep/deps`.

## Using it as a library

The root `module.pep` is the module `complexity`, which the tool is built
on: `complexity.score_source(source)` returns each function's
`FunctionScore` (name, line, cognitive and cyclomatic scores). A project
that depends on it may need the same `include` in its own `pep.toml`, as a
dependency's `[build]` table is for building that package itself.

## Tests

```sh
tests/run.sh path/to/pepper
```

builds `pep-complexity` and runs the `[Test]` functions in `tests/` with
`pepper test`: `score_test.pep` checks scores worked out by hand from the
white paper's rules, its own examples translated to Pepper among them, and
`tool_test.pep` runs the built tool on `tests/testdata/`.

## Releasing

CI (`.github/workflows/ci.yml`) runs the tests on Linux, macOS and
Windows for every push to `main` and every pull request, and on Linux with
the toolchain `pep.toml`'s `minimum_toolchain` names. It builds with
`PEPPER_LOCKED=1`, so commit `pep.lock` after changing a dependency. To
release, set `version` in `pep.toml` and the version `main.pep` reports,
merge, then push the matching tag (`git tag v0.1.0 && git push origin
v0.1.0`): CI tests the tag, publishes a GitHub release for it, and adds its
reference to the `gh-pages` branch, which GitHub Pages serves once it is
turned on for that branch (Settings, Pages).

## License

Apache-2.0; see [LICENSE](LICENSE).
