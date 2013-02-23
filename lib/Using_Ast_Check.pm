package Using_Ast_Check; 
use Switch; 
use Exporter 'import';
@EXPORT = qw(declare_parameter check_ast params_to_string $erros); 

# Context check ast produced by Using.pm

BEGIN{
my %params = (); 
my $errors = 0; 
}

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



# Exported function.  Declares a new parameter and its domain size.
# Undeclared parameters occuring in the using expression will raise
# errors.
sub declare_parameter{
#warning actually stores last index
    die if @_ < 2; 
     my ($p_name, @value_space) =  @_; 
     $params{$p_name} = \@value_space; 
}

sub fatal_error{
    die if @_ != 1; 
    print STDERR 'Error, while parsing using expression: '.$_[0]."\n"; 
    $errors++; 
}

# Check abstract syntax tree. 
sub check_ast{
     die if @_ != 1;
     $errors = 0;
     check_ast_node($_[0]); 
}

# Check abstract syntax tree, helper function.  
sub check_ast_node{
    die if @_ != 1; 
    my %ast_node = %{$_[0]};
    
     if(defined $ast_node{left}){
	 check_ast_node($ast_node{left});
	 check_ast_node($ast_node{right}); 
     }

     switch ($ast_node{type}){
	 case /parameter/ {check_parameter_node(\%ast_node)}
     }
}

sub check_parameter_node{
    die if @_ != 1;
    my %ast_node = %{$_[0]};
    my %value = %{$ast_node{value}};

    if (defined $params{$value{name}}){
       # is declared, check it. 
	# #check decor string
	# my $decor_string = $value{decor_string}; 
	# if($decor_string =~ /[fcl]/){
	# 	$decor_string .= guess_format_specification(); 
	# }

    }
    else{
	fatal_error 'Parameter \''.$value{name}.'\' undeclared.';
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
