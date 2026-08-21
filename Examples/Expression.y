%{
/* Host declarations and semantic actions are intentionally ignored. */
%}
%token NUMBER
%left '+'
%start expression
%%
expression
    : expression '+' term { $$ = $1 + $3; }
    | term
    ;
term
    : NUMBER
    | '(' expression ')'
    ;
%%
