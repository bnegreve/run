package Using; #Using expression parser

use Exporter 'import';
@EXPORT = qw(ast_to_string parse); 


## globals ##
use Parse::RecDescent;
$::RD_HINT = 1; 

# This module parses using expression and build an abstract syntax
# tree (ast).  Each node in the ast is a hash with a type key that
# contains the node type and an optional value key to contain extra
# informations about the node. Non terminals also have left and right
# keys that contain subtrees (typically expression operators are non
# terminals where left is the left operand subtree and right is the right
# operand subtree).
#
# Usage example: 
# print ast_to_string(parse("(P1=P2)cxP3f")); 
# Will output a nice ast for the expression (P1=P2)cxP3f
#
# The exact grammar can be found in the BEGIN block bellow.
# 

my $using_expression_parser;

# Initializes the parser module, must be called before any other call
BEGIN{
    my $grammar = q {
  start : expression {$return = $item[1];}|error
  expression: and_expr '=' expression
               {$return = Using::ast_create_eq_operator_node($item[1], $item[3]);}
            | and_expr
 
   and_expr:   brack_expr 'x' and_expr 
               {$return = Using::ast_create_prod_operator_node($item[1], $item[3]);}
           | brack_expr
 
  brack_expr: '(' expression ')' decor
               {Using::ast_append_decor($item[2], $item[4]); $return = $item[2];}
            | term decor
               {Using::ast_append_decor($item[1], $item[2]); $return = $item[1];}

  decor: /[clf]?/

  term: /[A-Z][A-Z_0-9]*/ 
               {$return  = Using::ast_create_parameter_node($item[1]);}

  error:/.*/ {print "Error\n";}
};

    $using_expression_parser = new Parse::RecDescent($grammar);
    undef $/;
}

# Build a string representing the abstract syntax tree for the
# corresponding using expressions.  Mainly for debug/testing purposes.
sub ast_to_string{
    die if (@_ != 1);
    return ast_to_string_subtree("", $_[0], 0); 
}

# Worker (recursive) function for ast_to_string
sub ast_to_string_subtree{
    die if (@_ != 3);
    my $string = $_[0]; 
    my %ast = %{$_[1]};
    my $depth = $_[2]; 

    foreach my $i (1..$depth){
	$string.="  "; 
    }

    $string.="- node type: ".$ast{type};
    if ( defined($ast{value}) ){
	$string.= ", node value: { "; 
	foreach my $k (keys %{$ast{value}}){
	    $string.="$k: ".$ast{value}{$k}.", ";;
	}
	$string.="}";
    }
    $string.="\n"; 

    if ( defined($ast{left}) ){
	$string.=ast_to_string_subtree($string, $ast{left}, $depth+1);
    }
    if ( defined($ast{right}) ){
	$string.=ast_to_string_subtree($string, $ast{right}, $depth+1);
    }
    return $string; 
}

# Create and return a parameter node. The node is a hashmap with a
# type key set to "parameter" and a value key bound to a another
# hashmap.  The value hashmap initially contains a name key with the
# parameter name and an empty decor string.
sub ast_create_parameter_node{
    die if @_ != 1;
    my ($name) = @_;
    return {type => "parameter", value => {name => $name, decor_string => ""}}; 
}

# Create and return a node for the eq operator. The node is a hashmap
# with a type key set to "eq_operator", a left key that contains the
# left operand subtree and a right key that contains the right
# operand subtree.
sub ast_create_eq_operator_node{
    die if @_ != 2;
    my ($left, $right) = @_;
    return {type => "eq_operator", left => $left, right => $right}; 
}

# Create and return a node for the prod operator. The node is a hashmap
# with a type key set to "prod_operator", a left key that contains the
# left operand subtree and a right key that contains the right
# operand subtree.
sub ast_create_prod_operator_node{
    die if @_ != 2;
    my ($left, $right) = @_;
    return {type => "prod_operator", left => $left, right => $right}; 
}

# If node is a terminal append decor to decor string, if node isn't a
# terminal append decor to every node of the subtree with a value field.. 
sub ast_append_decor{
    die if @_ != 2;
    my %ast = %{$_[0]};
    my $decor = $_[1]; 

    if ( defined($ast{value}) ){
	$ast{value}{decor_string} .= $decor; 
    }

    if ( defined($ast{left}) ){
	ast_append_decor($ast{left}, $decor);
    }
    if ( defined($ast{right}) ){
	ast_append_decor($ast{right}, $decor);
    }
}

# Parse a using expression and return an abstract syntax tree for this
# expression.
sub parse{
    die if @_ != 1; 
    my ($expr) = @_; 
    my $ast = $using_expression_parser->start($expr);
    # or print "bad input.\n";
    return $ast; 
}
     



1;
