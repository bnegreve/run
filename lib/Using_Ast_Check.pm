package Using_Ast_Check; 
use strict;
use Switch; 
use Exporter 'import';
our @EXPORT = qw(declare_parameter check_ast params_to_string $erros); 

# Context check ast produced by Using.pm

our %params = (); 
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
    check_ast_node($_[0]); 
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

sub tuples_to_string{
    die if @_ != 1; 
    my $tuples = $_[0];
    my $string = ""; 
    $string.= "tuples: { ";
    foreach my $t (@$tuples){
	$string.= "[ ";
	foreach my $tt (@$t){
	    $string.= parameter_value_ref_to_string(@$tt); 
	}
	$string.= "] ";
    }
    $string.= "}, ";
    return $string;
}


# parameter value refs are arrays <parameter name, index in the value space>
sub parameter_value_ref_to_string{
    die if @_ != 2; 
    return "<$_[0]:$_[1]> "; 
}

# check parameter node. 
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

    $node->{value} = {tuples => []};
    my $left_tuples = $left->{value}->{tuples};
    my $right_tuples = $right->{value}->{tuples};

    foreach my $v1 (@$left_tuples){
    	foreach my $v2 (@$right_tuples){
	    push $node->{value}->{tuples}, [@$v1, @$v2];
    	}
    }
    
}

# Update tuples field in non terminal.  eq combines maps each value
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
	fatal_error "The '=' operator can only be applied to value spaces of\
 the same size. Left operand size: $s1, right operand size: $s2".; 
    }

    $node->{value} = {tuples => []};
    for my $i (0..$#{$left_tuples}){
	push $node->{value}->{tuples},
	[@{$left_tuples->[$i]}, @{$right_tuples->[$i]}];
    }

}

sub guess_format_specification{
    die "You must provide format specification for each parameter f: one value per file, c: one value per column, l: one value per line. For example P1fxP2lxP3c"; 
    #TODO Guessing the best format should be easy based on parameter value spaces:
# if the number of parameter is one, assign a line format spec.
# if it is two, assign a col to the parameter with the smallest domain.
# if domains are equal first declared is col
# ...

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

# sub attr_print_term_names{
#     die if @_ != 1;
#     my ($attr_ref) = @_;

#     foreach my $name (@{$attr_ref->{names}}){
#     	print "$name,\t"; 
#     }
#     print "\n";

#     foreach my $decor (@{$attr_ref->{decors}}){
#     	print "$decor,\t"; 
#     }
#     print "\n"; 
# }

# sub attr_set_decor_array{
#     die if @_ != 2;
#     my ($attr_ref, $decor_array_ref) = @_;
#     $attr_ref->{decors} = $decor_array_ref; 
# }

# sub attr_set_decors_from_value{
#     die if @_ != 2;
#     my ($attr_ref, $decor) = @_;
#     for my $i (0 .. $#{$attr_ref->{decors}}){
# 	@{$attr_ref->{decors}}[$i] = $decor;
#     }
# }


# sub term_print{
# #    die if @_ == 0;
#     my %attr = @_;
#     attr_print_term_names(\%attr);

#     foreach $v1 (@{$attr{values}}){
# 	foreach $v2 (@$v1){
# 	    print "$v2,\t"; 
# 	}
# 	print "\n"; 
#     }
# }

# # sub array_print{
# #     my $array = $_[0];
# #     print ("ARRAY SIZE $#$array \n");
# #     foreach $v (@$array){
# # 	print ("$v "); 
# #     }
# #     print ("\n"); 
# # }



# sub cart_product{
#     my %attr;
#     my ($t1_ref, $t2_ref) = @_;


#     # print "#CART PRODUCT ARRAY 1\n"; 
#     # term_print(%$t1_ref); 

#     # print "#CART PRODUCT ARRAY 2\n";
#     # term_print(%$t2_ref); 

#     # deals with term names & decors
#     $attr{names} = [@{$t1_ref->{names}}, @{$t2_ref->{names}}];
#     $attr{decors} = [@{$t1_ref->{decors}}, @{$t2_ref->{decors}}];

#     # deals with values
#     foreach $v1 (@{$t1_ref->{values}}){
#     	foreach $v2 (@{$t2_ref->{values}}){
#     	    push @{$attr{values}}, [@$v1, @$v2];
#     	}
#     }


#     # print "#CART PRODUCT OUTPUT\n";
#     # term_print(%attr); 

#    return %attr; 
# }



# sub one_of_each{
#     my %attr;
#     my ($t1_ref, $t2_ref) = @_; 

#    # print "#OOE PRODUCT ARRAY 1\n"; 
#    # term_print(@{$t1}); 

#    # print "#OOE PRODUCT ARRAY 2\n";
#    # term_print(@{$t2}); 

#     ($#{$t1_ref->{values}} == $#{$t2_ref->{values}}) or die "\'=\' opertion between parameters with different number of values\n";

#     # deals with term names & decors
#     $attr{names} = [@{$t1_ref->{names}}, @{$t2_ref->{names}}];
#     $attr{decors} = [@{$t1_ref->{decors}}, @{$t2_ref->{decors}}];

#     # deals with values
#     $t1_values_ref = $t1_ref->{values}; 
#     $t2_values_ref = $t2_ref->{values}; 
#     for $i (0..$#{$t1_values_ref}){
# 	push @{$attr{values}}, [@{@{$t1_values_ref}[$i]}, @{@$t2_values_ref[$i]}];
#     }

#    # print "#OOE OUTPUT1\n"; 
#    # term_print(@output); 


#    return %attr; 
# }


END{
    if($errors != 0){
	print STDERR "Cannot run experiments because of $errors fatal error(s) while checking the using expression.\n"; 
    }
}

1; 
