# Copyright (C) 2010-2013, Benjamin Negrevergne.
package Using_Ast_Check; 
use 5.012; 
use strict;
use Switch; 
use Exporter 'import';
our @EXPORT = qw(declare_parameter check_ast params_to_string ast_get_tuples value_ref_get_pname value_ref_get_value  ast_get_dimension_indexes  all_parameter_names_in_std_order parameter_get_format_spec tuple_to_string); 

# Context check ast produced by Using.pm

# all the parameter names with their value space
our %params = ();

# binds parameter names with format specifications (f, c, l)
our %params_format_spec = ();

# binds parameter names with indexes that are assigned w.r.t. a unique
# order (lexicographical order over parameter names).
our %params_std_order = ();

our $errors = 0; 

# Prints the list of declared parameters and their value space. 
sub params_to_string{
    die if @_ != 0;
    my $outstring = ""; 
    for my $p (keys %params){
	$outstring .= "Parameter: $p,\tValue Space:\n[ ";
	for my $v (@{$params{$p}}){
	    $outstring .= "$v ";
	}
	$outstring .= "]\n";
    }
    return $outstring; 
}


sub fatal_error{
    die if @_ != 1; 
    print STDERR 'Error while parsing using expression: '.$_[0]."\n"; 
    $errors++;
    exit(1); 
}

# Declares a new parameter and its domain size.  Undeclared parameters
# occuring in the using expression will raise errors.
sub declare_parameter{
#warning actually stores last index
    die if @_ < 2; 
    my ($p_name, @value_space) =  @_; 
    if(not defined $params{$p_name}){
	$params{$p_name} = \@value_space; 
    } 
    else{
	fatal_error 'Parameter \''.$p_name.'\' already declared.';
    }
}

# Check abstract syntax tree. 
sub check_ast{
    die if @_ != 1;
    my ($ast_node) = @_; 
    check_ast_node($ast_node);
    my @all_parameters = build_format_specification($ast_node, "");
    assign_format_spec($ast_node->{value}->{decor_string}, \@all_parameters); 
    compute_std_parameter_order(); 
}

# Return an array containing the index (in the tuples) of all the
# parameters with a given dimension string.
sub ast_get_dimension_indexes{
    die if @_ != 2; 
    my ($ast, $dim_string) = @_; 

    my $format_spec = $ast->{value}->{decor_string};
    
    my @dims = ();
    for(my $i = 0; $i <= length $format_spec; $i++){
	if( (substr ($format_spec, $i, 1)) eq $dim_string){
	    push @dims, $i;
	}
    }
    return @dims; 
}

# Returns a string representation of a set of tuple.
sub tuples_to_string{
    die if @_ != 1; 
    my $tuples = $_[0];
    my $string = ""; 
    $string.= "tuples: { ";
    foreach my $t (@{$tuples}){
	$string .= tuple_to_string($t); 
    }
    $string.= "}, ";
    return $string;
}

# Returns a string representation of a tuple. 
sub tuple_to_string{
    die if @_ != 1;
    my $tuple = $_[0];
    my $string = "";
    $string.= "[ ";
    foreach my $tt (@{$tuple}){
	$string.= parameter_value_ref_to_string($tt); 
    }
    $string.= "] ";
    return $string; 
}


# parameter value refs are arrays <parameter name, index in the value space>
sub parameter_value_ref_to_string{
    die if @_ != 1; 
    my @vr = @{$_[0]}; 
    return "<$vr[0]:$vr[1]> "; 
}

# Returns parameter name of value reference. 
sub value_ref_get_pname{
    die if @_ != 1;
    my $vr = $_[0]; 
    return $vr->[0];
}

# Returns the value associated with a value ref. 
sub value_ref_get_value{
    die if @_ != 1;
    my $vr = $_[0]; 
    return $params{$vr->[0]}->[$vr->[1]]; 
}

# Check parameter node. 
sub check_parameter_node{
    die if @_ != 1;
    my $ast_node = $_[0];
    my $value = $ast_node->{value};

    if (defined $params{$value->{name}}){
	my $i = 0;
	my $size = @params{$value->{name}};
	my @tmp = map { [[$value->{name}, $i++]] } @{$params{$value->{name}}};
	$value->{tuples} = \@tmp; 
    }
    else{
	fatal_error 'Parameter \''.$value->{name}.'\' undeclared.';
    }
}

# check that the subtrees are valid for a product operation, build the
# tuples and put the result in the node value field. 
sub check_binary_operator_node{
    die if @_ != 1;
    my $ast_node = $_[0];
    
    die if (not (defined($ast_node->{left}) and defined($ast_node->{right}))); 
    my $left = $ast_node->{left};
    my $right = $ast_node->{right};

    switch ($ast_node->{type}){
	case /eq_operator/ {check_eq_operator_node($ast_node, $left, $right)};
	case /prod_operator/ {check_prod_operator_node($ast_node, $left, $right)}; 
    }
}

# Update tuples field in non terminal. 
# prod combines the tuples from the child subtrees. 
# (catherisian product) 
# i.e. [<A:0>] [<A:1>] combined with [<B:0>] [<B:1>]
# becomes [<A:0><B:0>] [<A:0><B:1>] [<A:1><B:0>]  [<A:1><B:1>]
sub check_prod_operator_node{
    die if @_ != 3;
    my ($node, $left, $right) = @_;

    $node->{value}->{tuples} = [];
    my $left_tuples = $left->{value}->{tuples};
    my $right_tuples = $right->{value}->{tuples};

    foreach my $v1 (@$left_tuples){
    	foreach my $v2 (@$right_tuples){
	    push @{$node->{value}->{tuples}}, [@$v1, @$v2];
    	}
    }
    
}

# Update tuples field in non terminal.  eq maps each value
# ref in the left subtree to a value ref in the right subtree with
# respect to the input order.  i.e. [<A:0>] [<A:1>] combined with
# [<B:0>] [<B:1>] becomes [<A:0><B:0>] [<A:1><B:1>].
sub check_eq_operator_node{
    die if @_ != 3;
    my ($node, $left, $right) = @_;
    my $left_tuples = $left->{value}->{tuples};
    my $right_tuples = $right->{value}->{tuples};

    my $s1 = @{$left->{value}->{tuples}};
    my $s2 = @{$right->{value}->{tuples}};
    if ($s1 != $s2){
	fatal_error "The '=' operator can only be applied to value spaces of
 the same size. Left operand size: $s1, right operand size: $s2.";
    }

    $node->{value}->{tuples} = [];
    for my $i (0..$#{$left_tuples}){
	push @{$node->{value}->{tuples}},
	[@{$left_tuples->[$i]}, @{$right_tuples->[$i]}];
    }
}

# Get the array of tuples associated with the root of the
# ast. (I.e. all the tuples.)
sub ast_get_tuples{
    die if @_ != 1;
    my ($ast) = @_;
    my @all_tuples = (); 
    foreach my $tuple (@{$ast->{value}->{tuples}}){
	push @all_tuples, tuple_in_std_order($tuple); 
    }
    return \@all_tuples; 
}

# Given a tuple, returns the same tuple sorted with respect to the std
# tuple ordering defined by
sub tuple_in_std_order{
    die if @_ != 1; 
    my ($tuple) = @_;
    # FIXME replace by inplace sort 
    my @ordered_tuple = (); 
    foreach my $vr (@{$tuple}){
	my $pname = value_ref_get_pname($vr);
	$ordered_tuple[$params_std_order{$pname}] = $vr; 
    }
    return \@ordered_tuple; 
}

# get all parameter names in std order ... yep!
sub all_parameter_names_in_std_order{
    return sort {$params_std_order{$a} <=> $params_std_order{$b}} keys %params_std_order; 
}


# Check abstract syntax tree, helper function.  
sub check_ast_node{
    die if @_ != 1; 
    my $ast_node = $_[0];

    if(defined $ast_node->{left}){
	check_ast_node($ast_node->{left});
	check_ast_node($ast_node->{right}); 
    }
    
    switch ($ast_node->{type}){
	case /parameter/ {check_parameter_node($ast_node)};
	case /.*_operator/ { check_binary_operator_node($ast_node)}
    }
}

# Recursive function that interates through the ast and builds the
# parameter format specification string.  This string string contains
# one char per parameter for each parameter how results will ultimatly
# be stored in the file. The ith char corresponds to the ith parameter
# w.r.t. the parameter order in the using expression. A 'f' char means
# one value per file for this parameter, a 'c' means one value per
# column in the file and a 'l' well, one value per line.
#
# This function is also in charge of assigning a format spec for a
# parameter when no format is provided or when multiple format
# specification are provided for the same parameter. 
# 
sub build_format_specification{
    die if @_ != 2; 
    my ($ast_node, $parent_spec) = @_;
    my $value = $ast_node->{value};

    if(defined $parent_spec
       and (defined $value->{decor_string})
       and ($value->{decor_string} eq "")){
	$value->{decor_string} = $parent_spec; 
    }
    
    if (defined $ast_node->{left}){
	my @left_child_parameters = 
	build_format_specification($ast_node->{left}, $value->{decor_string});
	my @right_child_parameters = 
	build_format_specification($ast_node->{right}, $value->{decor_string});

	$value->{decor_string} = ""
	    .$ast_node->{left}->{value}->{decor_string}
	.$ast_node->{right}->{value}->{decor_string};

	return (@left_child_parameters, @right_child_parameters); 
    } else{
	# we are on a terminal node
	my @child_parameters; 
	push @child_parameters, $ast_node->{value}->{name};
	return @child_parameters; 
    }


}

# Compute lexicographical order for parameters and store parameter index
# (w.r.t. lex order on parameter names) in $params_std_order{name}; 
sub compute_std_parameter_order{
    die if @_ != 0;
    my @sorted = sort keys %params;
    my $i = 0; 
    foreach my $p_name (@sorted){
	$params_std_order{$p_name} = $i++; 
    }
}

# Assign format spec to parameter names using the format specification
# string at the root of the ast.  Essentially 'parse' the string which
# describes the parameter format specification in the same order as
# parameters occurs in the using expression and reassign it to
# parameters names thanks to the %parameters_format_spec hash.
sub assign_format_spec{
    die if @_ != 2; 
    my ($format_spec_string, $all_parameters) = @_;
    for(my $i = 0; $i < length $format_spec_string; $i++){
	my $format_char = substr $format_spec_string, $i, 1;
	$params_format_spec{$all_parameters->[$i]} = $format_char; 
    }
}

sub parameter_get_format_spec{
    die if @_ != 1; 
    my ($pname) = @_;
    die unless defined $params_format_spec{$pname}; 
    return $params_format_spec{$pname};
}

sub get_num_parameters{
    die if @_ != 0;
    return scalar keys %params; 
}
sub guess_format_specification{
    die "You must provide format specification for each parameter f: one value per file, c: one value per column, l: one value per line. For example P1fxP2lxP3c"; 
    #TODO Guessing the best format should be easy based on parameter value spaces:
# if the number of parameter is one, assign a line format spec.
# if it is two, assign a col to the parameter with the smallest domain.
# if domains are equal first declared is col
# ...

}

END{
     if($errors != 0){
	 print STDERR "Cannot go further because of $errors error(s) found while checking using expression.\n"; 
     }

}
1; 
