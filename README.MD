# MiniPIG 🐷
**Strict LL(1) Recursive Descent Parser Generator for Turbo Pascal**

MiniPIG is a robust, single-file parser generator specifically designed for the Turbo Pascal 7.0 environment. It reads a grammar file defined in an ISO EBNF-style notation and compiles it into a standalone, high-performance Pascal unit (`.PAS`).

MiniPIG generates **Predictive Parsers**. Instead of relying on slow trial-and-error backtracking, it analyzes your grammar to compute `FIRST` and `FOLLOW` sets. It uses these sets to generate precise `case` statements, resulting in O(n) parsing performance and clear error reporting.

## 🚀 Key Features

*   **Strict LL(1) Architecture:** Generates fast, deterministic code without the overhead of backtracking state management.
*   **Safety Checks:** Automatically detects and reports:
    *   **Left Recursion** (which causes stack overflows in recursive descent).
    *   **LL(1) Conflicts** (Ambiguities where the parser cannot decide which path to take).
    *   **Nullable Loops** (Infinite loops matching empty strings).
*   **ISO EBNF Syntax:** Supports standard notation: `[ Optional ]`, `{ Repetition }`, `( Grouping )`.
*   **Semantic Actions:** Allows embedding of arbitrary Turbo Pascal code directly into the grammar rules via `<? ... ?>`.
*   **Semantic Predicates:** Supports boolean guards `?( ... )` for context-sensitive parsing logic.
*   **External Lexer Support:** Decoupled design allows you to use any tokenizer/lexer you prefer.

---

## 📦 Getting Started

### 1. Installation
MiniPIG is distributed as a single Pascal source file. To install it, simply compile it using the Turbo Pascal command-line compiler:

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
3.  **Use the output:** MiniPIG creates `grammar.pas`. Add this unit to your program's `uses` clause.

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
| **`$token`** | `Name` | Declares a terminal symbol (token) name. **All tokens used in rules must be declared here.** |
| **`$token_type`** | `Type` | The Pascal enumerated type used for your tokens (e.g., `TTokenKind`). |
| **`$token_next`** | `Proc` | The procedure to call to fetch the next token (e.g., `NextToken`). |
| **`$token_kind`** | `Var` | The variable holding the current token's ID/Kind. |
| **`$token_value`**| `Var` | The variable holding the current token's string representation. |
| **`$token_line`** | `Var` | The variable holding the current line number (for error reporting). |
| **`$token_eof`** | `Value` | The specific Enum value representing "End of File". |

### 2. Production Rules
A rule defines a Non-Terminal symbol. The syntax is:

```text
RuleName ::= Expression ;
```

### 3. Expressions & Operators

*   **Terminal (`$token`):** Matches a specific token declared via `$token`.
    *   *Example:* `tokInteger`
*   **Non-Terminal:** Matches another rule defined in the grammar.
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
*   **`MiniPigGetVal: String`**: Returns the string value of the *current* token (the one just matched or currently being looked at).
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

MiniPIG does not include a built-in lexer. You must provide a Pascal unit that handles tokenization. This allows MiniPIG to work with complex languages or simple file formats equally well.

### 1. Requirements for your Lexer Unit
Your lexer unit (let's call it `Lexer.pas`) must export:
1.  An **Enumerated Type** defining all possible tokens.
2.  A **Global Variable** holding the *current* token type.
3.  A **Global Variable** holding the *current* string value (optional, but recommended).
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
```

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
    Here, the parser sees `tokIf` and doesn't know which path to take.
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
$token tokNumber
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
    Returns the string value of the current token.

---

## License
MiniPIG is released under the **GNU General Public License v3 (GPLv3)**.
(c) 2026 DosWorld.
