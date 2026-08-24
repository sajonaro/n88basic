/* n88basic.mly -- N88-BASIC(86)'s syntax, declaratively, with citations.
 *
 * THIS IS A SPEC ARTIFACT, NOT THE PARSER. basic/parser.ml is the parser and
 * is untouched by this file; nothing consumes the parser menhir generates
 * from it. The reason it is nevertheless a real .mly rather than pseudo-BNF
 * is that menhir can then CHECK it: `menhir --explain --strict` builds the
 * LR automaton and turns every shift/reduce and reduce/reduce conflict into
 * an error. A grammar that is only a document can be quietly ambiguous; one
 * menhir accepts has been checked. See spec/grammar/README.md for how it is
 * validated and what it is for.
 *
 * Menhir is therefore a BUILD-TIME dependency of this artifact alone. It is
 * not a runtime dependency of the interpreter, the CLI or the VSCode
 * extension, and adding it here does not compromise the extension's
 * zero-runtime-dependency property.
 *
 * CITATIONS. Every rule names the printed folio it was read from, in the
 * form of spec/sources.md's page map. Folios were confirmed with
 * tools/folio.py rather than computed, because the printed-to-PDF offset
 * drifts (+13 in the front matter, +11 through the body, +9 in the
 * appendices). A rule with no cited syntax box is marked UNCITED and is as
 * ungrounded as a clause with no page.
 *
 * WHAT IS DELIBERATELY NOT HERE. Three parts of the language are decided by
 * the scanner, not by an LR grammar, and forcing them in here would produce
 * something that looks right and is wrong:
 *
 *   - DATA's operands are raw text, scanned to the end of the statement
 *     rather than tokenised as expressions (printed p.58-59). A DATA datum
 *     may contain commas and spaces that are not separators.
 *   - "?" is read as PRINT by the scanner, and LIST expands it back
 *     (printed p.125). It is not a distinct syntactic form.
 *   - Identifiers are scanned by maximal munch against the reserved-word
 *     table, which is why "GO TOTAL" is GO followed by the variable TOTAL
 *     and not a two-word GO TO (printed p.78). Reserved-word membership is
 *     a lexical fact and cannot be expressed as a production.
 *
 * These are documented in spec/grammar/README.md as lexer concerns.
 */

%token <float> NUMBER          /* numeric literal, any of the three types (printed p.12-14) */
%token <string> STRING         /* "..." string literal                    (printed p.15)    */
%token <string> IDENT          /* variable or array name, with optional sigil (printed p.14) */
%token <string> FNIDENT        /* FNxxx -- a user function name           (printed p.59)    */
%token <int> LINENO            /* a line number, at the head of a line or as a jump target  */

/* Punctuation (printed p.19-20 for the operators, per-statement pages otherwise). */
%token LPAREN RPAREN COMMA SEMI COLON EQUALS
%token PLUS MINUS STAR SLASH CARET BACKSLASH
%token LT GT LE GE NE
%token EOL EOF

/* Reserved words. Each is cited at the rule that uses it; the table itself is
 * basic/token.ml's, and spec/keywords.json carries a page for every one. */
%token LET PRINT LPRINT USING WRITE INPUT LINEINPUT READ DATA RESTORE
%token IF THEN ELSE FOR TO STEP NEXT WHILE WEND
%token GOTO GOSUB RETURN ON ERROR RESUME STOP END
%token DIM ERASE SWAP CLEAR OPTION BASE DEF FN
%token DEFINT DEFSNG DEFDBL DEFSTR REM
%token SCREEN WIDTH CLS LOCATE COLOR CONSOLE KEY OFF
%token PSET PRESET LINE CIRCLE PAINT POINT
%token TAB SPC RANDOMIZE MID
%token AND OR NOT XOR IMP EQV MOD

/* ------------------------------------------------------------------ *
 * Operator precedence, printed p.25 (PDF p.38), section 10.6
 * "演算の優先順位" -- the manual's own numbered table, lowest first here
 * because menhir gives later declarations higher precedence.
 *
 * The manual's numbering, 1 binding tightest:
 *   1 parenthesised expressions   9 relational (<, >, = etc.)
 *   2 functions                  10 NOT
 *   3 ^  (exponent)              11 AND
 *   4 -  (unary minus)           12 OR
 *   5 *, / (real division)       13 XOR
 *   6 \  (integer division)      14 IMP
 *   7 MOD                        15 EQV
 *   8 +, -
 *
 * Levels 1 and 2 are structural here rather than precedence declarations.
 *
 * Three of these once contradicted basic/parser.ml, which is what writing
 * this file against the manual rather than against the parser was for:
 * ^ binding tighter than unary minus (so -2^2 is -4), NOT binding looser
 * than the relational operators (so NOT A = B is NOT (A = B)), and AND, OR
 * and NOT being bitwise rather than boolean. All three are fixed, and each
 * has a clause under OP.* with a conformance case.
 */

/* The dangling ELSE, printed p.80. Lower than ELSE itself, so an IF with no
 * ELSE yet in hand prefers to shift one and bind it to the nearest IF. */
%nonassoc NO_ELSE
%nonassoc ELSE

%left EQV                              /* 15 */
%left IMP                              /* 14 */
%left XOR                              /* 13 */
%left OR                               /* 12 */
%left AND                              /* 11 */
%right NOT                             /* 10 -- prefix, below relational */
/*  9. NONASSOC, so "1 = 1 = 1" is not a sentence of this grammar.
 *
 *  This is OUR READING, not a stated rule -- flagged as such because the
 *  manual gives no associativity for any level in section 10.6's table. It
 *  rests on two things it does say. Printed p.21 section 10.2 opens
 *  "関係演算子は2つの数値を比較するときに用います" -- relational operators are used
 *  when comparing TWO numeric values -- and every example in its table is
 *  binary (X=Y, X<>Y, X<Y, X>Y, X<=Y, X>=Y), none chained. Printed p.21
 *  section 10.3 then says the LOGICAL operators are what "複数の関係演算式を結合
 *  して" -- join multiple relational expressions -- into compound conditions,
 *  and printed p.23's worked examples do exactly that: IF X<0 OR 99<X,
 *  IF 0<X AND X<100. The manual's way to combine comparisons is a logical
 *  operator between them, never a chain.
 *
 *  So the manual does not prohibit a chain; it never contemplates one. Left
 *  associativity would be the Microsoft-lineage convention, but conventions
 *  are not evidence here, and nonassoc is what "compares two values" reads
 *  as. It also agrees with basic/parser.ml, whose parse_compare matches at
 *  most one comparison -- so this is one place the grammar and the parser
 *  do NOT disagree, and the interpreter's parse error is a decision of ours
 *  rather than a divergence. */
%nonassoc EQUALS LT GT LE GE NE
%left PLUS MINUS                       /*  8 */
%left MOD                              /*  7 */
%left BACKSLASH                        /*  6 */
%left STAR SLASH                       /*  5 */
%nonassoc UMINUS                       /*  4 -- unary minus, BELOW ^ */
%left CARET                            /*  3 -- left-associative: printed p.20
                                              gives (X^Y)^2 as BASIC X^Y^2 */

%start <unit> program

%%

/* A program is a sequence of numbered lines (printed p.7). */
program:
  | list(line) EOF { }

line:
  | LINENO statements EOL { }
  | LINENO EOL { }

/* Statements on one line are separated by ":" (printed p.7). A 255-byte
 * limit on the physical line is stated (printed p.58-59 for DATA, and
 * generally) and is a lexical bound, not a production. */
/* An IF takes the WHOLE remainder of the line as its branch: printed p.80
 * makes everything after THEN conditional, so "IF A THEN B : C" runs C only
 * when A holds. That means an IF can only be the LAST statement on a line,
 * and saying so structurally is what removes the ambiguity -- with a flat
 * separated_nonempty_list(COLON, statement) menhir cannot tell whether ": C"
 * continues the THEN branch or resumes the line, and it reported exactly
 * that shift/reduce conflict. Resolving it by precedence would have picked
 * the right parse for the wrong reason; this states the rule instead. */
statements:
  | simple_statement                   { }
  | simple_statement COLON statements  { }
  | if_statement                       { }

if_statement:
  /* printed p.80. Written as four explicit productions rather than with
   * option(else_branch) so that the dangling ELSE can be resolved by
   * precedence: "IF a THEN IF b THEN x ELSE y" must bind ELSE to the
   * INNER IF, which is what the manual's own nesting-after-ELSE wording
   * implies and what shifting gives. The else-less forms are marked
   * %prec NO_ELSE, which is declared just below ELSE, so menhir prefers
   * the shift. menhir found this as three shift/reduce conflicts. */
  | IF expr THEN then_branch                  %prec NO_ELSE { }
  | IF expr THEN then_branch ELSE then_branch { }
  | IF expr GOTO LINENO                       %prec NO_ELSE { } /* THEN-less form */
  | IF expr GOTO LINENO ELSE then_branch      { }

simple_statement:
  /* -- assignment and program structure -- */
  | LET lvalue EQUALS expr                    { } /* printed p.93  */
  | lvalue EQUALS expr                        { } /* printed p.93: LET is optional */
  | mid_statement                             { } /* printed p.103-104 */
  | REM                                       { } /* printed p.134-135; text is lexical */
  | END                                       { } /* printed p.70  */
  | STOP                                      { } /* printed p.147 */
  | DIM separated_nonempty_list(COMMA, array_decl)   { } /* printed p.62-63 */
  | ERASE separated_nonempty_list(COMMA, IDENT)      { } /* printed p.70  */
  | SWAP lvalue COMMA lvalue                  { } /* printed p.149 */
  | CLEAR                                     { } /* printed p.46 */
  | CLEAR arg_slots                           { } /* printed p.46 */
  | OPTION BASE NUMBER                        { } /* printed p.116: literal 0 or 1 only */
  | DEF FNIDENT loption(delimited(LPAREN, separated_nonempty_list(COMMA, IDENT), RPAREN)) EQUALS expr
                                              { } /* printed p.59: parameters optional */
  | def_type_kw separated_nonempty_list(COMMA, letter_range) { } /* printed p.60 */
  | RANDOMIZE option(expr)                    { } /* printed p.133 */

  /* -- output -- */
  | PRINT print_tail                          { } /* printed p.125 */
  | LPRINT print_tail                         { } /* printed p.100 */
  | PRINT USING expr SEMI print_items         { } /* printed p.128 */
  | LPRINT USING expr SEMI print_items        { } /* printed p.101 */
  | WRITE separated_nonempty_list(print_sep, expr) { } /* printed p.161: at least one */

  /* -- input -- */
  | INPUT input_tail                          { } /* printed p.82  */
  | LINEINPUT option(terminated(STRING, SEMI)) lvalue { } /* printed p.95: prompt takes ";" only */

  /* -- data -- */
  | DATA                                      { } /* printed p.58-59: operands are raw text (lexical) */
  | READ separated_nonempty_list(COMMA, lvalue) { } /* printed p.134 */
  | RESTORE option(LINENO)                    { } /* printed p.135-136 */
  /* -- control flow -- */
  | GOTO LINENO                               { } /* printed p.78  */
  | GOSUB LINENO                              { } /* printed p.78  */
  | RETURN option(LINENO)                     { } /* printed p.136 */
  | FOR IDENT EQUALS expr TO expr option(preceded(STEP, expr)) { } /* printed p.74 */
  | NEXT separated_list(COMMA, IDENT)         { } /* printed p.74: NEXT K, J */
  | WHILE expr                                { } /* printed p.158 */
  | WEND                                      { } /* printed p.158 */
  | ON expr GOTO separated_nonempty_list(COMMA, LINENO)  { } /* printed p.109-110 */
  | ON expr GOSUB separated_nonempty_list(COMMA, LINENO) { } /* printed p.109-110 */

  /* -- error handling -- */
  | ON ERROR GOTO LINENO                      { } /* printed p.109 */
  | RESUME resume_target                      { } /* printed p.136 */
  | ERROR expr                                { } /* printed p.71  */

  /* -- text screen -- */
  | SCREEN                                      { } /* printed p.140 */
  | SCREEN arg_slots                            { } /* printed p.140 */
  | WIDTH separated_nonempty_list(COMMA, expr)  { } /* printed p.158-159 */
  | CLS option(expr)                            { } /* printed p.47-48 */
  | LOCATE                                      { } /* printed p.99: X first */
  | LOCATE arg_slots                            { } /* printed p.99 */
  | COLOR                                       { } /* printed p.48-50 */
  | COLOR arg_slots                             { } /* printed p.48-50 */
  | CONSOLE                                     { } /* printed p.54  */
  | CONSOLE arg_slots                           { } /* printed p.54  */
  | KEY option(delimited(LPAREN, expr, RPAREN)) key_action { } /* printed p.87 */

  /* -- graphics -- */
  | PSET point option(preceded(COMMA, expr))    { } /* printed p.130 */
  | PRESET point option(preceded(COMMA, expr))  { } /* printed p.124 */
  | LINE line_endpoints line_options            { } /* printed p.94  */
  | CIRCLE point COMMA expr circle_options      { } /* printed p.45  */
  | PAINT point paint_options                   { } /* printed p.117 */

def_type_kw:
  | DEFINT { } | DEFSNG { } | DEFDBL { } | DEFSTR { }   /* printed p.60 */

letter_range:
  | IDENT { }                                   /* a single letter, or A-Z written as one token */
  | IDENT MINUS IDENT { }                       /* printed p.60: a letter range */

array_decl:
  | IDENT LPAREN separated_nonempty_list(COMMA, expr) RPAREN { } /* printed p.62-63 */

/* One or more argument slots, each of which may be empty and is then written
 * as a bare comma -- the shape SCREEN, LOCATE, COLOR, CONSOLE and CLEAR all
 * share ("SCREEN ,,0,1" sets the two pages alone).
 *
 * Deliberately NOT separated_list(COMMA, option(expr)). That derives the
 * empty string two ways -- a list of no slots at all, and a list of one
 * empty slot -- so a bare "SCREEN" has two parse trees. It is a real
 * ambiguity in the shape, not a menhir artefact, and menhir found it as a
 * reduce/reduce conflict. Here a slot list either is a single present
 * expression or contains at least one comma, so it can never be empty, and
 * the bare statement form is a separate production. */
arg_slots:
  | expr                        { }
  | option(expr) COMMA arg_tail { }

arg_tail:
  | option(expr)                { }
  | option(expr) COMMA arg_tail { }

/* MID$ as a statement overwrites in place (printed p.103-104). Distinct from
 * MID$ as a function, which appears in [primary]. */
mid_statement:
  | MID LPAREN IDENT COMMA expr option(preceded(COMMA, expr)) RPAREN EQUALS expr { }

key_action:
  | ON { } | OFF { } | STOP { }                 /* printed p.87: ON | OFF | STOP */

resume_target:
  | /* empty */ { }                             /* printed p.136: RESUME */
  | NUMBER      { }                             /* RESUME 0 */
  | NEXT        { }                             /* RESUME NEXT */
  | LINENO      { }                             /* RESUME <line> */

then_branch:
  | LINENO     { }                              /* printed p.80: bare line number acts as GOTO */
  | statements { }

/* PRINT's separators are "," and ";" and they differ (printed p.125); WRITE's
 * do not (printed p.161). Both are written here as one nonterminal because the
 * difference is semantic, not syntactic. */
print_sep:
  | COMMA { } | SEMI { }

print_tail:
  | /* empty */ { }                             /* printed p.125: PRINT alone ends the line */
  | print_items { }

print_items:
  | print_item                    { }
  | print_item print_sep          { }           /* trailing separator suppresses the newline */
  | print_item print_sep print_items { }

print_item:
  | expr                              { }
  | TAB LPAREN expr RPAREN            { }       /* printed p.149 */
  | SPC LPAREN expr RPAREN            { }       /* printed p.146 */

input_tail:
  | option(terminated(STRING, print_sep)) separated_nonempty_list(COMMA, lvalue) { }
                                                /* printed p.82: prompt takes "," or ";" */

/* A coordinate, absolute or relative to the last point referenced
 * (printed p.130 for PSET; the STEP form is stated for every graphics
 * statement that takes a coordinate). */
point:
  | LPAREN expr COMMA expr RPAREN      { }
  | STEP LPAREN expr COMMA expr RPAREN { }

line_endpoints:
  | option(point) MINUS point { }               /* printed p.94: the first point may be omitted */

line_options:
  | /* empty */                                        { }
  | COMMA option(expr)                                 { } /* palette number */
  | COMMA option(expr) COMMA box_kw                    { } /* ,B or ,BF */
  | COMMA option(expr) COMMA box_kw COMMA expr         { } /* style, or BF's fill / tile */

box_kw:
  | IDENT { }                                   /* "B" or "BF": scanned as an identifier */

circle_options:
  | /* empty */ { }
  | COMMA option(expr) circle_angles { }        /* printed p.45: palette, angles, aspect, F */

circle_angles:
  | /* empty */ { }
  | COMMA option(expr) { }
  | COMMA option(expr) COMMA option(expr) { }
  | COMMA option(expr) COMMA option(expr) COMMA option(expr) { }
  | COMMA option(expr) COMMA option(expr) COMMA option(expr) COMMA IDENT option(preceded(COMMA, expr)) { }
                                                /* trailing F, then palette 2 or a tile string */

paint_options:
  | /* empty */ { }                             /* printed p.117 */
  | COMMA option(expr) { }                      /* area colour, or a tile string */
  | COMMA option(expr) COMMA expr { }           /* and a border colour */

lvalue:
  | IDENT                                                        { }
  | IDENT LPAREN separated_nonempty_list(COMMA, expr) RPAREN     { }

/* ------------------------------------------------------------------ *
 * Expressions. Precedence and associativity are the declarations above,
 * all from printed p.25 section 10.6.
 * ------------------------------------------------------------------ */
expr:
  | primary                       { }
  | expr CARET expr               { }           /* 3  printed p.19, p.25 */
  | MINUS expr %prec UMINUS       { }           /* 4  printed p.19, p.25 */
  | expr STAR expr                { }           /* 5  */
  | expr SLASH expr               { }           /* 5  */
  | expr BACKSLASH expr           { }           /* 6  integer division: printed p.20, p.25 */
  | expr MOD expr                 { }           /* 7  printed p.20, p.25 */
  | expr PLUS expr                { }           /* 8  also string concatenation (printed p.24) */
  | expr MINUS expr               { }           /* 8  */
  /* 9, printed p.25. Written out rather than through a [relop] nonterminal:
   * menhir takes a production's precedence from its LAST TERMINAL, so
   * "expr relop expr" carries none at all and level 9 silently does
   * nothing. menhir caught that -- exactly the quiet wrongness a grammar
   * that were only a document would have kept. */
  | expr EQUALS expr              { }
  | expr LT expr                  { }
  | expr GT expr                  { }
  | expr LE expr                  { }
  | expr GE expr                  { }
  | expr NE expr                  { }
  | NOT expr                      { }           /* 10 printed p.22, p.25 */
  | expr AND expr                 { }           /* 11 */
  | expr OR expr                  { }           /* 12 */
  | expr XOR expr                 { }           /* 13 printed p.22 */
  | expr IMP expr                 { }           /* 14 printed p.22 */
  | expr EQV expr                 { }           /* 15 printed p.22 */

/* printed p.23-24. The manual also spells the three two-character operators
 * "=>", "=<" and "><"; those are lexical variants of GE, LE and NE and are
 * folded into those tokens by the scanner, not by a production. */

primary:
  | NUMBER                                                       { } /* 1,2 */
  | STRING                                                       { }
  | IDENT                                                        { }
  | IDENT LPAREN separated_nonempty_list(COMMA, expr) RPAREN     { } /* array element */
  | FNIDENT loption(delimited(LPAREN, separated_nonempty_list(COMMA, expr), RPAREN)) { }
                                                                     /* printed p.59 */
  | LPAREN expr RPAREN                                           { } /* 1 */
  | POINT LPAREN expr COMMA expr RPAREN                          { } /* printed p.123 */
  | MID LPAREN expr COMMA expr option(preceded(COMMA, expr)) RPAREN { } /* printed p.103-104 */
