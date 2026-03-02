# MiniPIG 🐷

![Platform](https://img.shields.io/badge/platform-DOS%20(16--bit)-orange.svg)
![Language](https://img.shields.io/badge/Turbo-Pascal-blue.svg)
![Tool](https://img.shields.io/badge/Compiler-Construction-green.svg)
![AI Assisted](https://img.shields.io/badge/AI-Assisted-purple.svg)

**Strict LL(1) Recursive Descent Parser Generator for Turbo Pascal**

MiniPIG is a robust, single‑file parser generator specifically designed for the Turbo Pascal 7.0 environment. It reads a grammar file defined in an ISO EBNF‑style notation and compiles it into a standalone, high‑performance Pascal unit (`.PAS`).

MiniPIG generates **Predictive Parsers**. Instead of relying on slow trial‑and‑error backtracking, it analyzes your grammar to compute `FIRST` and `FOLLOW` sets. It uses these sets to generate precise `case` statements, resulting in O(n) parsing performance and clear error reporting.

---

## Table of Contents

1. [Key Features](#-key-features)
2. [Getting Started](#-getting-started)
3. [Grammar Syntax Reference](#-grammar-syntax-reference)
   - [Configuration Directives](#1-configuration-directives)
   - [Production Rules](#2-production-rules)
   - [Expressions & Operators](#3-expressions--operators)
4. [Semantic Actions and Predicates](#-semantic-actions-and-predicates)
5. [Lexer Integration Guide](#-lexer-integration-guide)
6. [Token Values and Memory Efficiency](#-token-values-and-memory-efficiency)
7. [Strict LL(1) Requirements & Error Handling](#-strict-ll1-requirements--error-handling)
8. [Comprehensive Example](#-comprehensive-example)
9. [Internal Structure of the Generated Parser](#-internal-structure-of-the-generated-parser)
10. [Debugging and Profiling](#-debugging-and-profiling)
11. [Advanced Examples](#-advanced-examples)
12. [Optimizing Grammars](#-optimizing-grammars)
13. [Integration with Development Environment](#-integration-with-development-environment)
14. [Compatibility and Limitations](#-compatibility-and-limitations)
15. [Glossary of Terms](#-glossary-of-terms)
16. [FAQ](#-faq)
17. [Generated Interface Reference](#-generated-interface-reference)
18. [License](#license)

---

## 🚀 Key Features

*   **Strict LL(1) Architecture:** Generates fast, deterministic code without the overhead of backtracking state management.
*   **Safety Checks:** Automatically detects and reports:
    *   **Left Recursion** (which causes stack overflows in recursive descent).
    *   **LL(1) Conflicts** (Ambiguities where the parser cannot decide which path to take).
    *   **Nullable Loops** (Infinite loops matching empty strings).
*   **ISO EBNF Syntax:** Supports standard notation: `[ Optional ]`, `{ Repetition }`, `( Grouping )`.
*   **Semantic Actions:** Allows embedding of arbitrary Turbo Pascal code directly into the grammar rules via `<? ... ?>`.
*   **Semantic Predicates:** Supports boolean guards `?( ... )` for context‑sensitive parsing logic.
*   **External Lexer Support:** Decoupled design allows you to use any tokenizer/lexer you prefer.
*   **Value‑Bearing Tokens:** Distinguish between tokens that carry a semantic value (e.g., identifiers, numbers) and those that do not (e.g., keywords, operators) using `$token` vs. `$token_with_value`. This improves memory efficiency by allocating storage only where needed.
*   **Human‑Readable Output:** The generated Pascal code is clean and commented, making it easy to understand and debug.

---

## 📦 Getting Started

### 1. Installation

MiniPIG is distributed as a single Pascal source file. To install it, simply compile it using the Turbo Pascal command‑line compiler:

```bash
tpc minipig.pas
```

This will produce the `minipig.exe` executable.

### 2. Basic Workflow
1.  **Define your grammar** in a text file (e.g., `grammar.txt`).
2.  **Run MiniPIG** against your grammar:
    ```bash
    minipig grammar.txt
    ```
3.  **Use the output:** MiniPIG creates `grammar.pas`. Add this unit to your program’s `uses` clause.

---

## 📖 Grammar Syntax Reference

A MiniPIG grammar consists of **Configuration Directives** and **Production Rules**.

### 1. Configuration Directives
Directives control how the Pascal code is generated and how the parser interacts with your lexer. All directives start with a **`$`** sign.

| Directive | Argument | Description |
| :--- | :--- | :--- |
| **`$uses`** | `UnitName` | Adds a unit to the generated `uses` clause. Use this to include your Lexer unit. |
| **`$unit_start`** | `Code` | Injects raw code at the very top of the generated file (useful for compiler switches like `{$F+}`). |
| **`$init`** | `Code` | Injects code into the `InitParser` procedure. |
| **`$token`** | `Name` | Declares a terminal symbol (token) name that does **not** carry a semantic value (e.g., keywords, operators). |
| **`$token_with_value`** | `Name` | Declares a terminal symbol (token) name that **does** carry a semantic value (e.g., identifiers, numbers). These tokens will automatically have storage allocated for their string value. |
| **`$token_type`** | `Type` | The Pascal enumerated type used for your tokens (e.g., `TTokenKind`). |
| **`$token_next`** | `Proc` | The procedure to call to fetch the next token (e.g., `NextToken`). |
| **`$token_kind`** | `Var` | The variable holding the current token’s ID/Kind. |
| **`$token_value`**| `Var` | The variable holding the current token’s string representation. |
| **`$token_line`** | `Var` | The variable holding the current line number (for error reporting). |
| **`$token_eof`** | `Value` | The specific Enum value representing “End of File”. |

> **Important:** The distinction between `$token` and `$token_with_value` is crucial for memory management. In the generated `MiniPigEnsure` procedure, only tokens declared with `$token_with_value` will cause a `PString` field to be allocated and filled with `$token_value`. This avoids wasting memory on tokens that never need a value.
>
> **Warning:** If you declare a token with `$token_with_value` but your lexer does **not** properly set the variable specified by `$token_value` for that token, the generated parser will still allocate a `PString` and try to read an uninitialized value, leading to runtime errors. Ensure your lexer fills `$token_value` correctly for all value‑bearing tokens.

### 2. Production Rules

A rule defines a Non‑Terminal symbol. The syntax is:

```text
RuleName ::= Expression ;
```

### 3. Expressions & Operators

*   **Terminal (`$token` or `$token_with_value`):** Matches a specific token declared via a directive.
    *   *Example:* `tokInteger`, `tokIf`
*   **Non‑Terminal:** Matches another rule defined in the grammar.
    *   *Example:* `Expression`
*   **Sequence (Space):** Matches items in order.
    *   *Example:* `tokIf Condition tokThen` (Matches `tokIf` *then* `Condition` *then* `tokThen`).
*   **Alternative (`|`):** Matches one of several options. The generator uses lookahead tokens to decide which path to take.
    *   *Example:* `tokPlus | tokMinus`
*   **Grouping `( ... )`:** Groups elements together to control precedence or apply operators to a sequence.
    *   *Example:* `Factor ( tokMult Factor | tokDiv Factor )`
*   **Optional `[ ... ]`:** The enclosed expression may appear zero or one time.
    *   *Example:* `tokReturn [ Expression ]`
*   **Repetition `{ ... }`:** The enclosed expression may appear zero or more times (Kleene Star).
    *   *Example:* `Statement { tokSemiColon Statement }`

---

## ⚛️ Semantic Actions and Predicates

MiniPIG allows you to insert Turbo Pascal code directly into the parsing logic.

### Semantic Actions `<? ... ?>`

Code inside `<? ... ?>` is executed immediately when the parser successfully reaches that position in the rule.

**Example:**
```text
(* Parse a number and print it *)
Factor ::= tokNumber <? Writeln('Found number: ', MiniPigGetVal); ?> ;
```

**Helper Functions available in actions:**
*   **`MiniPigGetVal: String`**: Returns the string value of the *current* token (the one just matched or currently being looked at). Works only for tokens declared with `$token_with_value`.
*   **`MiniPigMatch(Token)`**: Can be used for manual checking, though rarely needed in normal actions.

### Semantic Predicates `?( ... )`

A predicate is a **Boolean expression** inside `?( ... )`. It acts as a semantic guard.
*   If the expression is `TRUE`, parsing continues.
*   If `FALSE`, the parser considers this a mismatch and triggers a failure for that specific alternative.

**Example:**
```text
(* Only match identifiers longer than 10 chars *)
LongIdent ::= tokIdent ?( Length(MiniPigGetVal) > 10 ) ;
```

> **Note:** Predicates are the only construct in MiniPIG that utilizes a small local rollback mechanism (`SaveStack`), allowing you to peek at a token and reject it semantically without consuming it permanently if the check fails.

---

## 🔌 Lexer Integration Guide

MiniPIG does not include a built‑in lexer. You must provide a Pascal unit that handles tokenization. This allows MiniPIG to work with complex languages or simple file formats equally well.

### 1. Requirements for your Lexer Unit

Your lexer unit (let’s call it `Lexer.pas`) must export:
1.  An **Enumerated Type** defining all possible tokens.
2.  A **Global Variable** holding the *current* token type.
3.  A **Global Variable** holding the *current* string value (optional, but required for value‑bearing tokens).
4.  A **Procedure** that advances to the next token.

### 2. Example Lexer Interface
```pascal
unit Lexer;

interface

type
  TTokenKind = (
    tokEOF,
    tokError,
    tokIdent,
    tokNumber,
    tokAssign,  { := }
    tokSemiColon
  );

var
  CurrToken:    TTokenKind; { The ID of the token currently under the cursor }
  CurrTokenVal: String;     { The text of the token, e.g., '123' or 'MyVar' }
  CurrLine:     Integer;    { Line number for error messages }

{ Reads the next token from input and updates the variables above }
procedure NextToken;

implementation
{ ... implementation ... }
end.
```

### 3. Connecting Grammar to Lexer

In your `grammar.txt`, you map the generator to this unit:

```text
$uses        Lexer
$token_type  TTokenKind
$token_kind  CurrToken
$token_value CurrTokenVal
$token_line  CurrLine
$token_next  NextToken
$token_eof   tokEOF

(* Declare tokens – note which ones carry values *)
$token_with_value tokIdent
$token_with_value tokNumber
$token tokAssign
$token tokSemiColon
```

---

## 💰 Token Values and Memory Efficiency

In many grammars, only a subset of tokens (like identifiers, numbers, and string literals) actually need to store a value. Keywords, operators, and punctuation are recognized solely by their type. MiniPIG’s `$token_with_value` directive lets you explicitly mark tokens that require value storage.

**How it works:**
- For tokens declared with `$token`, the generated `MiniPigEnsure` procedure sets `NewNode^.Val := nil`.
- For tokens declared with `$token_with_value`, it allocates a `PString` and copies `$token_value` into it.

**Benefits:**
- **Memory savings:** Only allocate strings for tokens that actually carry data.
- **Performance:** Fewer allocations and less pointer manipulation.
- **Clarity:** The grammar itself documents which tokens have associated values.

**Example:**
```text
$token_with_value tokIdent
$token_with_value tokNumber
$token tokPlus
$token tokMinus
$token tokSemi
```

In a language with many keywords, you avoid allocating a `PString` for `tokIf`, `tokWhile`, etc., which would never be used. This is especially important in memory‑constrained DOS environments.

**⚠️ Important:** If you mark a token as `$token_with_value`, your lexer **must** correctly set the variable referenced by `$token_value` every time that token is recognized. Failing to do so will result in the parser reading uninitialized memory, leading to unpredictable behavior or crashes.

---

## ⚠️ Strict LL(1) Requirements & Error Handling

Because MiniPIG generates a predictive parser, your grammar must satisfy specific mathematical properties. MiniPIG analyzes your grammar and creates the following errors if the rules are violated:

### 1. Left Recursion
Recursive descent parsers cannot handle Direct or Indirect Left Recursion. It causes an infinite stack overflow.

*   **Error:** `Left recursion detected in rule: Name`
*   **Bad Code:** `Expr ::= Expr tokPlus Term;`
*   **Solution:** Rewrite using Repetition `{}`.
    *   **Fixed:** `Expr ::= Term { tokPlus Term };`

### 2. LL(1) Conflicts (Ambiguity)
The parser must be able to decide which alternative to take by looking at **only the next token**. If two alternatives in a rule can start with the same token, this is a conflict.

*   **Error:** `LL(1) Conflict detected. Intersection in SELECT sets.`
*   **Scenario:**
    ```text
    Stmt ::= tokIf Expr tokThen Stmt
           | tokIf Expr tokThen Stmt tokElse Stmt ;
    ```
    Here, the parser sees `tokIf` and doesn’t know which path to take.
*   **Solution:** Use Left Factoring or Optionals.
    *   **Fixed:** `Stmt ::= tokIf Expr tokThen Stmt [ tokElse Stmt ] ;`

### 3. Nullable Loops
A repetition block `{ ... }` must consume at least one token per iteration. If the body of the loop can match an empty string, the parser would enter an infinite loop.

*   **Error:** `Nullable loop detected in rule...`
*   **Bad Code:** `Rule ::= { [ tokA ] };` (Because `[tokA]` can be empty, `{}` loops forever).
*   **Solution:** Ensure the loop body always consumes something. `Rule ::= { tokA };`

---

## 💡 Comprehensive Example

Here is a complete example for a simple Mathematical Expression parser.

### 1. The Grammar (`calc.txt`)

```text
$unit_start {$F+}
$uses       Lexer
$token_type TTokenKind
$token_next NextToken
$token_kind CurrToken
$token_value CurrTokenVal
$token_line CurrLine
$token_eof  tokEOF

(* Declare Tokens matches those in Lexer.pas *)
$token_with_value tokNumber   (* numbers carry a value *)
$token tokPlus
$token tokMinus
$token tokMult
$token tokDiv
$token tokLParen
$token tokRParen
$token tokEOF

(* --- Rules --- *)

(* Entry Point *)
Expression ::= Term { 
      tokPlus  Term <? WriteLn('OP: Add'); ?> 
    | tokMinus Term <? WriteLn('OP: Sub'); ?> 
};

Term ::= Factor { 
      tokMult Factor <? WriteLn('OP: Mul'); ?> 
    | tokDiv  Factor <? WriteLn('OP: Div'); ?> 
};

Factor ::= 
      tokNumber <? WriteLn('PUSH ', MiniPigGetVal); ?> 
    | tokLParen Expression tokRParen 
    ;
```

### 2. Generating the Parser

Run:

```bash
minipig calc.txt
```
This generates `calc.pas`.

### 3. Using it in Pascal

```pascal
program Calculator;

uses Lexer, Calc; { Calc is the generated unit }

begin
  { Initialize your lexer input }
  Assign(Input, 'data.txt'); Reset(Input);
  
  { PRIME THE PUMP: You MUST read the first token before starting the parser }
  NextToken; 

  { Initialize Parser State }
  InitParser;

  { Call the entry rule }
  if parse_Expression then
    Writeln('Parsing Successful!')
  else
    Writeln('Syntax Error on line ', CurrLine);

  { Cleanup }
  DoneParser;
end.
```

---

## 🔧 Internal Structure of the Generated Parser

Understanding the generated code helps in debugging and optimizing.

### The `TTokenNode` Record
```pascal
TTokenNode = record
  Kind: TTokenKind;   { enumerated token type }
  Val: PString;       { nil for tokens without value, otherwise points to a string }
  Line: Integer;      { source line number }
  Next: PTokenNode;   { pointer to next token in the linked list }
end;
```

### The Token Stream
The parser maintains a singly linked list of tokens. `MiniPigHead` is a dummy head node, `MiniPigTail` points to the last node, and `MiniPigCursor` points to the **last consumed token** (initially `MiniPigHead`). The lookahead token is `MiniPigCursor^.Next`.

### The `MiniPigEnsure` Procedure
This procedure is called whenever the parser needs to guarantee that a lookahead token exists. If the lookahead slot is empty (`MiniPigCursor^.Next = nil`), it invokes the lexer (`$token_next`) and creates a new `TTokenNode`. It uses the `$token_kind`, `$token_value`, and `$token_line` variables to fill the node. Critically, it checks the kind of the token against the set of value‑bearing tokens (those declared with `$token_with_value`) and only allocates a `PString` if the token is in that set.

```pascal
if CurrToken in [tokIdent, tokNumber] then  { dynamically generated list }
  New(NewNode^.Val); NewNode^.Val^ := CurrTokenVal;
```

### The `MiniPigMatch` Function

Compares the lookahead token’s kind with the expected token. If equal, it advances the cursor (`MiniPigCursor := MiniPigCursor^.Next`) and returns `True`; otherwise returns `False`.

### The `MiniPigGetVal` Function

Returns the `Val` field of the **current** token (the one just consumed). This is used in semantic actions to retrieve the token’s textual value.

### Rule Functions

Each rule becomes a `function parse_RuleName: Boolean;`. It contains a `case` statement on `MiniPigGetKind` that dispatches based on the `FIRST` sets of the alternatives. Inside each case branch, the corresponding sequence is generated, with embedded actions and predicate checks. Predicates use the `SaveStack` array to remember the cursor position before evaluating the condition, allowing rollback if the predicate fails.

---

## 🐞 Debugging and Profiling

### Using `MiniPigCursor`

You can inspect the current parsing position by examining `MiniPigCursor`. After a successful match, `MiniPigCursor` points to the token just consumed. This is useful in custom error recovery or debugging routines.

### Adding Debug Output

Inject `Writeln` statements in semantic actions to trace the parser’s progress:

```text
Statement ::= 
    tokIf Expression tokThen Statement
      <? WriteLn('Parsed IF at line ', MiniPigCursor^.Line); ?>
  | tokWhile Expression tokDo Statement
      <? WriteLn('Parsed WHILE'); ?>
;
```

### Common Runtime Errors

- **Reading `MiniPigGetVal` on a token without value:** If you call `MiniPigGetVal` on a token declared with `$token`, the `Val` field is `nil`, causing a runtime error. Ensure your actions only access values on appropriate tokens.
- **Infinite loop in repetition:** This is usually caused by a grammar error (nullable loop) which MiniPIG should have caught, but if you bypass the checks, the parser may get stuck. Check that every iteration consumes at least one token.
- **Mismatched `$token_value`:** If the lexer does not set the value variable for a token marked `$token_with_value`, the parser will allocate an uninitialized string, leading to garbage values or crashes.

### Profiling
To measure performance, you can add timers around calls to `parse_RuleName`. The generated parser is deterministic, so performance is predictable and linear in input size.

---

## 🧪 Advanced Examples

### A Tiny Programming Language

Consider a language with variable declarations, assignments, and while loops.

**Lexer Interface** (simplified):
```pascal
type TTokenKind = (tokEOF, tokIdent, tokNumber, tokIf, tokWhile, 
                   tokAssign, tokSemi, tokLParen, tokRParen, tokPlus, tokMinus);
var CurrToken: TTokenKind; CurrTokenVal: String; CurrLine: Integer;
procedure NextToken; external;
```

**Grammar (`tiny.txt`):
```text
$uses Lexer
$token_type TTokenKind
$token_kind CurrToken
$token_value CurrTokenVal
$token_line CurrLine
$token_next NextToken
$token_eof tokEOF

$token_with_value tokIdent
$token_with_value tokNumber
$token tokIf
$token tokWhile
$token tokAssign
$token tokSemi
$token tokLParen
$token tokRParen
$token tokPlus
$token tokMinus
$token tokEOF

Program ::= { Statement } ;

Statement ::= 
    Ident tokAssign Expression tokSemi
      <? StoreVariable(Ident, ExpressionValue); ?>
  | tokIf Expression tokThen Statement
  | tokWhile Expression tokDo Statement
  | tokLParen Statement tokRParen
;

Expression ::= Term { (tokPlus | tokMinus) Term } ;
Term       ::= Factor { (tokMult | tokDiv) Factor } ;
Factor     ::= 
    tokNumber
  | tokIdent
  | tokLParen Expression tokRParen
;
```

### Context‑Sensitive Parsing with Predicates

Suppose you want to enforce that an identifier used in an expression must be declared before use. You can combine a symbol table with a predicate:

```text
Expression ::= 
    tokIdent ?( IsDeclared(MiniPigGetVal) ) 
      <? UseVariable(MiniPigGetVal); ?>
  | tokNumber
;
```

Here `IsDeclared` is a Pascal function you provide; the parser will backtrack if the identifier isn’t declared.

---

## ⚡ Optimizing Grammars

### Minimize Rule Count

Each rule becomes a Pascal function. For very large grammars, many functions may exceed the DOS memory model limits. Combine related constructs using groups where possible.

### Prefer `{ ... }` Over Recursion

Left recursion is forbidden; use repetition `{ ... }` to express lists. This also generates simpler and faster code.

### Factor Common Prefixes

If two alternatives start with the same token, left‑factor them to avoid LL(1) conflicts. Use optional elements `[ ... ]` instead of duplication.

**Before (conflict):**
```text
IfStmt ::= tokIf Condition tokThen Stmt
         | tokIf Condition tokThen Stmt tokElse Stmt ;
```
**After (factored):**
```text
IfStmt ::= tokIf Condition tokThen Stmt [ tokElse Stmt ] ;
```

### Group Action Placement

Place semantic actions as early as possible to avoid carrying unnecessary state. Actions inside loops are executed each iteration, so keep them lightweight.

### Use `$token_with_value` Sparingly

Only mark tokens that genuinely need a value. This reduces memory allocations and string copies, speeding up the lexer/parser interaction.

---

## 🏗 Integration with Development Environment

### Batch Build Script

Create a `.bat` file that runs MiniPIG and then compiles your project:

```batch
@echo off
minipig grammar.txt
tpc /m myprogram.pas
```

### Makefile (for Turbo Pascal with MAKE)
```make
grammar.pas: grammar.txt
    minipig grammar.txt

myprogram.exe: grammar.pas myprogram.pas
    tpc /m myprogram.pas
```

### Including in Project File

Add the generated `.pas` to your TP project file (`.TPP`). Ensure it is listed **after** the lexer unit but **before** the main program, because the parser uses the lexer types.

---

## 💻 Compatibility and Limitations

- **Turbo Pascal 7.0** (Real Mode) is the primary target.
- **Memory:** The grammar and generated parser must fit within the 64KB data segment. MiniPIG enforces `GRAMMAR_MAX_SIZE = 65000` and `MAX_TOKENS = 255`. If your grammar is too large, consider splitting it or simplifying.
- **DOS Real Mode:** Generated code uses near pointers and relies on the default memory model. If you use far pointers in your lexer, ensure compatibility.
- **Other Pascal Compilers:** The generated code may work with Free Pascal in TP mode, but this is not officially tested. Some adjustments may be needed for 32‑bit or 64‑bit environments.

---

## 📚 Glossary of Terms

| Term | Definition |
| :--- | :--- |
| **LL(1)** | A class of grammars that can be parsed with a single lookahead token, left‑to‑right, with leftmost derivation. |
| **FIRST set** | Set of terminal symbols that can begin a string derived from a given non‑terminal or sequence. |
| **FOLLOW set** | Set of terminals that can appear immediately after a given non‑terminal in some sentential form. |
| **SELECT set** | For a production `A ::= α`, the set of terminals that predict this production. For nullable `α`, it includes `FOLLOW(A)`. |
| **Nullable** | A non‑terminal (or sequence) that can derive the empty string. |
| **Left Recursion** | A rule that directly or indirectly calls itself as the leftmost symbol. Not allowed in LL(1). |
| **Semantic Action** | Pascal code embedded in the grammar (`<? ... ?>`) executed when the parser reaches that point. |
| **Predicate** | A boolean guard (`?( ... )`) that must be true for the current alternative to be viable. |

---

## ❓ FAQ

**Q: Why does MiniPIG report “Left recursion detected”?**  
A: Your grammar contains a rule like `A ::= A ...`. Rewrite it using repetition: `A ::= B { ... }`.

**Q: How do I pass data between semantic actions?**  
A: Use global variables in your lexer or main program. The generated parser can reference any identifier visible in the unit’s scope (via `uses` or declared above).

**Q: Can I use external functions in predicates?**  
A: Yes, any Pascal function that returns a Boolean can be called, as long as it is in scope (e.g., declared in a `uses` unit or in the `$unit_start` block).

**Q: My lexer sets `$token_value`, but the parser crashes when I call `MiniPigGetVal`. Why?**  
A: Check that the token is declared with `$token_with_value`. If it’s declared with `$token`, no `Val` field is allocated and `MiniPigGetVal` will access a nil pointer.

**Q: How can I implement error recovery?**  
A: MiniPIG does not provide automatic error recovery. However, you can add your own recovery logic by wrapping rule calls with `try..except` or by checking parser state and manually advancing the cursor using `MiniPigCursor`.

**Q: What is the `SaveStack` array used for?**  
A: Predicates `?( ... )` use `SaveStack` to remember the cursor position before evaluating the condition. If the predicate fails, the parser restores the cursor and tries another alternative.

**Q: Can I use `$token_with_value` for keywords?**  
A: Technically yes, but it’s wasteful. Keywords are usually recognized by their kind and don’t need a string value. Only use it for tokens where the actual text matters (identifiers, numbers, strings).

**Q: Does MiniPIG support Unicode?**  
A: No, Turbo Pascal’s native `String` type is ANSI. The parser and lexer work with 8‑bit characters only.

---

## 🛠 Generated Interface Reference

The unit generated by MiniPIG exposes the following:

*   **`procedure InitParser;`**
    Allocates memory for internal structures. Must be called before parsing.
*   **`procedure DoneParser;`**
    Frees memory.
*   **`function parse_RuleName: Boolean;`**
    For every rule in your grammar, a function is generated. It returns `True` if the rule matched successfully, `False` otherwise.
*   **`function MiniPigMatch(Token: TokenType): Boolean;`**
    Checks if the current token matches the argument. If yes, it consumes it and returns True.
*   **`function MiniPigGetVal: String;`**
    Returns the string value of the current token (only meaningful for tokens declared with `$token_with_value`).

Additionally, the unit exports the token stream variables `MiniPigHead`, `MiniPigTail`, and `MiniPigCursor` for advanced debugging.

---

## License

MiniPIG is released under the **GNU General Public License v3 (GPLv3)**.
(c) 2026 DosWorld.
