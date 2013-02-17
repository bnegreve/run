#!/usr/bin/perl -w
package Using; #Using expression parser

use Exporter 'import';
@EXPORT = qw(init_parser declare_parameter parse %using_ast ast_to_string parse); 


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
# The exact grammar can be found further in the init_parser function. 
#

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

# Initializes the parser module, must be called before any other call
sub init_parser{
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

# Exported function.  Declares a new parameter and its domain size.
# Undeclared parameters occuring in the using expression will raise
# errors.
sub declare_parameter{
#warning actually stores last index
     die if @_ != 2; 
     my ($p_name, $num_values) =  @_; 
     $params{$p_name} = $num_values-1; 
}

# Parse a using expression 
sub parse{
    die if @_ != 1; 
    my ($expr) = @_; 
    my $ast = $using_expression_parser->start($expr);
    # or print "bad input.\n";
    return $ast; 
}


# Build an attribute structure from a terminal parameter (called a
# term, I should change this name).  In other words it create a 2D
# array of parameter values indices with one indice per internal array.
sub term_create_attr{
    die if @_ != 2; 
    my ($term_name, $num_values)= @_;
    
    my %attr; 
    $attr{names} = [$term_name];
    
    my @values; 

    # foreach $v(@{$value_space}){
    # 	push @values, [$v];
    # }

    foreach my $i (0..$num_values){
	push @values, [$i];
    }
    

    $attr{values} = \@values; 
    return %attr; 
}

sub attr_print_term_names{
    die if @_ != 1;
    my ($attr_ref) = @_;
    
    foreach my $name (@{$attr_ref->{names}}){
    	print "$name,\t"; 
    }
    print "\n";
    
    foreach my $decor (@{$attr_ref->{decors}}){
    	print "$decor,\t"; 
    }
    print "\n"; 
}


sub attr_set_decor_array{
    die if @_ != 2;
    my ($attr_ref, $decor_array_ref) = @_;
    $attr_ref->{decors} = $decor_array_ref; 
}

sub attr_set_decors_from_value{
    die if @_ != 2;
    my ($attr_ref, $decor) = @_;
    for my $i (0 .. $#{$attr_ref->{decors}}){
	@{$attr_ref->{decors}}[$i] = $decor;
    }
}


sub term_print{
#    die if @_ == 0;
    my %attr = @_;
    attr_print_term_names(\%attr);

    foreach $v1 (@{$attr{values}}){
	foreach $v2 (@$v1){
	    print "$v2,\t"; 
	}
	print "\n"; 
    }
}

# sub array_print{
#     my $array = $_[0];
#     print ("ARRAY SIZE $#$array \n");
#     foreach $v (@$array){
# 	print ("$v "); 
#     }
#     print ("\n"); 
# }



sub cart_product{
    my %attr;
    my ($t1_ref, $t2_ref) = @_;
    

    # print "#CART PRODUCT ARRAY 1\n"; 
    # term_print(%$t1_ref); 

    # print "#CART PRODUCT ARRAY 2\n";
    # term_print(%$t2_ref); 

    # deals with term names & decors
    $attr{names} = [@{$t1_ref->{names}}, @{$t2_ref->{names}}];
    $attr{decors} = [@{$t1_ref->{decors}}, @{$t2_ref->{decors}}];
    
    # deals with values
    foreach $v1 (@{$t1_ref->{values}}){
    	foreach $v2 (@{$t2_ref->{values}}){
    	    push @{$attr{values}}, [@$v1, @$v2];
    	}
    }


    # print "#CART PRODUCT OUTPUT\n";
    # term_print(%attr); 

   return %attr; 
}



sub one_of_each{
    my %attr;
    my ($t1_ref, $t2_ref) = @_; 
    
   # print "#OOE PRODUCT ARRAY 1\n"; 
   # term_print(@{$t1}); 

   # print "#OOE PRODUCT ARRAY 2\n";
   # term_print(@{$t2}); 

    ($#{$t1_ref->{values}} == $#{$t2_ref->{values}}) or die "\'=\' opertion between parameters with different number of values\n";

    # deals with term names & decors
    $attr{names} = [@{$t1_ref->{names}}, @{$t2_ref->{names}}];
    $attr{decors} = [@{$t1_ref->{decors}}, @{$t2_ref->{decors}}];
    
    # deals with values
    $t1_values_ref = $t1_ref->{values}; 
    $t2_values_ref = $t2_ref->{values}; 
    for $i (0..$#{$t1_values_ref}){
	push @{$attr{values}}, [@{@{$t1_values_ref}[$i]}, @{@$t2_values_ref[$i]}];
    }

   # print "#OOE OUTPUT1\n"; 
   # term_print(@output); 
    
    
   return %attr; 
}



1;
