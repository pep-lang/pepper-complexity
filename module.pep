## The cognitive and cyclomatic complexity of Pepper functions, scored on
## the syntax tree the Pepper compiler's own parser builds. The
## `pep-complexity` command-line tool (`main.pep`) is built on it.
##
## Bring it in with `import complexity`.
##
## - `score_source`: scores every function in one source file
## - `FunctionScore`: one function's name, line and scores
##
## @example
##     import complexity;
##
##     main(): int {
##         var scores = complexity.score_source("f(x: int): int {\n    return x > 0 ? 1 : 0;\n}\n");
##         print(scores.value()[0].cognitive);   # 1
##         return 0;
##     }

# This file only gathers the module's public API from its other files.

import "score";

export FunctionScore;
export score_source;
