# Copyright (C) 2010-2013, Benjamin Negrevergne.
package Using_Ast_Check; 
use 5.012; 
use strict;
use Switch; 
use Exporter 'import';
our @EXPORT = qw(declare_parameter check_ast params_to_string ast_get_tuples value_ref_get_pname value_ref_get_value value_ref_get_param_id all_parameter_names_in_std_order parameter_get_format_spec tuple_to_string); 

# Context check ast produced by Using.pm

# Maps parameter *names* with their value space
our %params = ();

# Maps parameter ids to names. 
# NOTE: Since the same parameter can occur multiple times in the using
# expression, multiple parameter ids can map to the same name.
our %param_names = (); 

# Maps parameter ids to format specifictions (i.e. f(ile), c(olumn) or l(ine))
our %param_format_spec = ();

# Maps parameters ids to parameter precedence relation 
our %param_precedence_relation = (); 

# Maps parameter ids to index in a cannonical order (lex order over parameter names.) 
our %param_std_order = ();

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

sub warning{
    die if @_ != 1; 
    print STDERR 'Warning: '.$_[0]."\n"; 
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

# Check and decorate abstract syntax tree. 
sub check_ast{
    die if @_ != 1;
    my ($ast_node) = @_; 
    check_ast_node($ast_node, undef);
    %param_names = %{ $ast_node->{value}->{parameter_list} };
    %param_format_spec = %{ $ast_node->{value}->{format_spec} };
    %param_precedence_relation = %{ $ast_node->{value}->{parameter_relation} };
    assign_format_spec(); 
    compute_std_parameter_order(); 
    
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


# Returns a cannonical representation of a tuple
sub tuple_to_cannonical_string{
    die if @_ != 1;
    my $tuple = $_[0];
    my $string = "";
    $string.= "[ ";
    foreach my $vr (@{$tuple}){
	$string.= '<'.value_ref_get_pname($vr).'='.value_ref_get_value($vr).'> '; 
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
    return $param_names{$vr->[0]};
}

# Returns the value associated with a value ref. 
sub value_ref_get_value{
    die if @_ != 1;
    my $vr = $_[0];
    my $pname = value_ref_get_pname($vr); 
    return $params{$pname}->[$vr->[1]]; 
}

# Returns parameter id from value ref. 
sub value_ref_get_param_id{
    die if @_ != 1;
    my $vr = $_[0]; 
    return $vr->[0]; 
}

# Returns parameter id from value ref. 
sub value_ref_get_value_id{
    die if @_ != 1;
    my $vr = $_[0]; 
    return $vr->[1]; 
}

# Return 1 if vr1 precedes vr2 according to specified order (">" or "<"), 0 if they're equal or -1 of vr2 precedes vr1. 
sub value_ref_compare_rel{
    die if @_ != 3;
    my ($vr1, $vr2, $rel) = @_;
    if($rel eq ">"){
	return 1 if value_ref_get_value_id($vr1) > value_ref_get_value_id($vr2);
	return -1 if value_ref_get_value_id($vr2) > value_ref_get_value_id($vr1);
	return 0; 
    }
    elsif($rel eq "<"){
	return value_ref_compare_rel($vr2, $vr1, ">")
    }
    return 0;
}

# Return 1 if vr1 precedes vr2 according to the order specified in the using expression, otherwise 0 if they're equal or -1 of vr2 precedes vr1. 
sub value_ref_compare{
        die if @_ != 2;
	my ($vr1, $vr2) = @_;
	die if value_ref_get_param_id($vr1) != value_ref_get_param_id($vr2); 
	return value_ref_compare_rel($vr1, $vr2, 
				     parameter_get_precedence_relation(value_ref_get_param_id($vr1))); 
}

# return 1 if tuple t1 precedes t2 according to the orders specified in the using expressions. 
sub tuple_precedes_tuple{
    die if @_ != 2; 
    my ($t1, $t2) = @_; 

    die "Trying to compare incompatible tuples" if scalar @$t1 != scalar @$t2;

    my @tuples_relations = ();
    
    for my $i (0..$#$t1){

	my $vr1 = $t1->[$i];
	my $vr2 = $t2->[$i]; 

	my $pname1 = value_ref_get_pname($vr1);
	my $pname2 = value_ref_get_pname($vr2);

	die "Trying to compare incopatible tuples" if not $pname1 eq $pname2 ; 

	$tuples_relations[$i] = value_ref_compare($vr1, $vr2);
    }

    my $precedes_flag = 0; 

    foreach my $rel_indicator (@tuples_relations){
	if($rel_indicator == -1){
	    return 0;
	}

	if($rel_indicator == 1){
	    $precedes_flag=1; 
	}
    }
    
    return $precedes_flag; 
}

# Return all preceding tuples according to the orders specified in the using expression 
sub get_all_preceding_tuples{
    die if @_ != 2; 
    my ($tuple, $all_tuples) = @_; 
    my @preceding_tuples = (); 

    foreach my $t (@$all_tuples){
	if(tuple_precedes_tuple($t, $tuple)){
	    push @preceding_tuples, $t; 
	}
    }
    return @preceding_tuples; 
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
	my $pid = value_ref_get_param_id($vr);
	$ordered_tuple[$param_std_order{$pid}] = $vr; 
    }
    return \@ordered_tuple; 
}

# get all parameter names in std order ... yep!
sub all_parameter_names_in_std_order{
    return sort {$param_std_order{$a} <=> $param_std_order{$b}} keys %param_std_order; 
}

# Check and decorate abstract syntax tree,  function.  
# check bottom up. 
sub check_ast_node{
    die if @_ != 2; 
    my ($node, $parent_node) = @_;
    
    inherit_node_attributes($node, $parent_node); 

    if(defined $node->{left}){
	check_ast_node($node->{left}, $node);
	check_ast_node($node->{right}, $node);
    }

    synthesize_node_attributes($node);
}

sub inherit_node_attributes{
    die if @_ != 2; 
    my ($node, $parent) = @_; 

    inherit_decor_string($node, $parent) if defined $parent; 

    # switch ($node->{type}){
    # 	case /parameter/ { inherit_parameter_node_attributes($node); };
    # 	case /.*_operator/ { inherit_binary_operator_node_attributes($node); }; 
    # }
}

sub inherit_decor_string{
    die if @_ != 2; 
    my ($node, $parent) = @_; 
    
    my $value = $node->{value};
    my $parent_value = $parent->{value}; 

    # inherit decor string from parent (i.e. concatenate)
    $value->{decor_string} .= $parent_value->{decor_string}; 
}

sub synthesize_node_attributes{
    die if @_ != 1; 
    my $node = $_[0]; 

    # Check the node type
    switch ($node->{type}){
	case /parameter/ { synthesize_parameter_node_attributes($node); };
	case /.*_operator/ { synthesize_binary_operator_node_attributes($node)}; 
    }

}

sub synthesize_parameter_node_attributes{
    die if @_ != 1; 
    my ($node) = @_; 

    my $value = $node->{value};

    # Synthesize tuple list 
    if (defined $params{$value->{name}}){
	my $i = 0;
	my @tmp = map { [[$value->{id}, $i++]] } @{$params{$value->{name}}};
	$value->{tuples} = \@tmp; 
    }
    else{
	fatal_error 'Parameter \''.$value->{name}.'\' undeclared.';
    }

    # Synthesize parameter list stub 
    $value->{parameter_list} = { $value->{id} => $value->{name} }; 

    # Synthesize format spec hash
    my $format_spec = format_spec_from_decor_string($value->{decor_string}); 
    $value->{format_spec} = {$value->{id} => $format_spec}; 

    # Synthesize parameter relation hash
    my $parameter_relation = parameter_relation_from_decor_string($value->{decor_string}); 
    $value->{parameter_relation} = {$value->{id} => $parameter_relation}; 


}

# Extract the most specific format spec from the decor string (by construction, the right most character in [fcl]
sub format_spec_from_decor_string{
    die if @_ != 1; 
    my $decor_string = $_[0];

    if($decor_string =~ /([fcl])/){
	return $1;
    }
    return "U"; 
}

# Extract the most specific parameter relation from the decor string (by construction, the right most character in [<>]
sub parameter_relation_from_decor_string{
    die if @_ != 1; 
    my $decor_string = $_[0];

    if($decor_string =~ /([<>])/){
	return $1;
    }
    return "U"; 
}

# synthesize attributes for binary operators nodes such as eq and prod 
sub synthesize_binary_operator_node_attributes{
    die if @_ != 1;
    my $node = $_[0];
    
    die if (not (defined($node->{left}) and defined($node->{right}))); 
    my $left = $node->{left};
    my $right = $node->{right};

    # Synthesize parameter list
    $node->{value}->{parameter_list} = merge_hash_ref($left->{value}->{parameter_list}, $right->{value}->{parameter_list}); 
    
    # Synthesize format spec 
    $node->{value}->{format_spec} = merge_hash_ref($left->{value}->{format_spec}, $right->{value}->{format_spec}); 

    # Synthesize parameter relations
    $node->{value}->{parameter_relation} = merge_hash_ref($left->{value}->{parameter_relation}, $right->{value}->{parameter_relation}); 
    
    # Synthesize tuples (operator specific)
    switch ($node->{type}){
	case /eq_operator/ {synthesize_eq_operator_node_attributes($node, $left, $right)};
	case /prod_operator/ {synthesize_prod_operator_node_attributes($node, $left, $right)}; 
    }
}

sub merge_hash_ref{
    die if @_ != 2; 
    my ($hash_ref1, $hash_ref2) = @_; 
    return { %{$hash_ref1}, %{$hash_ref2} }; 
}

# Update tuples field in non terminal. 
# prod combines the tuples from the child subtrees. 
# (catherisian product) 
# i.e. [<A:0>] [<A:1>] combined with [<B:0>] [<B:1>]
# becomes [<A:0><B:0>] [<A:0><B:1>] [<A:1><B:0>]  [<A:1><B:1>]
sub synthesize_prod_operator_node_attributes{
    die if @_ != 3;
    my ($node, $left, $right) = @_;


    # Synthesize tuple list 
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
sub synthesize_eq_operator_node_attributes{
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

# Build the list of all the parameters and assign decorations 
sub build_parameter_list{
    die if @_ != 2; 
    my ($ast_node, $parent_spec) = @_;
    my $value = $ast_node->{value};

    if($value->{decor_string} eq ""){
	$value->{decor_string} = $parent_spec; 
    }
    
    if (defined $ast_node->{left}){
	# internal node of the ast
	build_parameter_list($ast_node->{left}, $value->{decor_string});
	build_parameter_list($ast_node->{right}, $value->{decor_string});

	$value->{decor_string} = ""
	    .$ast_node->{left}->{value}->{decor_string}
	.$ast_node->{right}->{value}->{decor_string};
    } else{
	# we are on a terminal node
	$param_names{$ast_node->{value}->{id}} = $ast_node->{value}->{name}; 
	$param_names{$ast_node->{p_attr}->{id}} = $ast_node->{value}->{name}; 
    }
}

# Compute lexicographical order for parameters and store parameter index
# (w.r.t. lex order on parameter names) in $param_std_order{name}; 
sub compute_std_parameter_order{
    die if @_ != 0;
    my @sorted = sort keys %param_format_spec;
    my $i = 0; 
    foreach my $param_id (@sorted){
	$param_std_order{$param_id} = $i++; 
    }
}


# Assign format spec to parameter names using the format specification
# string at the root of the ast.
sub assign_format_spec{
    die if @_ != 0; 

    my @param_ids = sort {$a <=> $b} keys %param_names; 

    my $last_char = 'U'; 
    for (my $i = $#param_ids; $i >= 0; $i--){
	my $pid = $param_ids[$i]; 

	my $format_char = $param_format_spec{$pid}; 

	if($format_char eq 'U'){  
	    # If undefined, assign format specification in a round robin fashion
	    if($last_char eq 'U'){ $format_char = 'l'; }
	    else{
		switch ($last_char){
		    case /l/ {$format_char = 'c';}
		    case /c/ {$format_char = 'f';}
		    case /f/ {$format_char = 'l';}
		}
	    }
	    warning('No format specification for parameter '
		    .$param_names{$param_ids[$i]}
		    .' ; automatically assigned to \''.$format_char.'\'.' ); 
	    $param_format_spec{$param_ids[$i]} = $format_char;
	}
	$last_char = $format_char; 
    }
}


sub parameter_get_format_spec{
    die if @_ != 1; 
    my ($param_id) = @_;
    die unless defined $param_format_spec{$param_id}; 
    return $param_format_spec{$param_id};
}

sub parameter_get_precedence_relation{
    die if @_ != 1; 
    my ($param_id) = @_;
    die unless defined $param_precedence_relation{$param_id}; 
    return $param_precedence_relation{$param_id};
}

sub get_num_parameters{
    die if @_ != 0;
    return scalar keys %params; 
}

END{
     if($errors != 0){
	 print STDERR "Cannot go further because of $errors error(s) found while checking using expression.\n"; 
     }

}
1; 
