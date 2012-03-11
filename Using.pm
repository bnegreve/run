#!/usr/bin/perl -w
package Using; #Using expression parser

# Package to parse 'using expressions' in order to combine different
# parameters and compute different tuples of parameter values. 
#
# 'using expression' are made of parameters and operators, each
# parameter has a name and a value space.
#
#### PARAMETERS NAME AND VALUE SPACES ####
#
# Each parameter has a name and a set of value it can take
# For example: 
# THREAD_NUM, value space [1,2,4], 
# DATASET, value space [d1, d2]
#
#### OPERATORS ####
#
# The operators are 'x' and '='
# 'x' is the carthesian product of the value spaces of to parameters
# '=' is the first value of the first value space with the first value of the second value space
# (hence, the two value space must have the same size)
#
#### EXEMPLE ####
#
# The value space corresponding to the using expression "THREAD_NUMxDATASET"
# is: 
# ( 1 ), ( d1 ), 
# ( 1 ), ( d2 ), 
# ( 2 ), ( d1 ), 
# ( 2 ), ( d2 ), 
# ( 4 ), ( d1 ), 
# ( 4 ), ( d2 ), 
#
# The value space corresponding to the using expression "DATASET=DATASET_VALUE"
# is: 
# ( d1 ), ( 10 ), 
# ( d2 ), ( 20 ), 
#
# Another example with the additional parameter 
# DATASET_VALUE with a value space [10,20]
# Th value space corresponding to the using expression "THREAD_NUMx(DATASET=DATASET_VALUE)"
# is: 
# ( 1 ), ( d1 ), ( 10 ), 
# ( 1 ), ( d2 ), ( 20 ), 
# ( 2 ), ( d1 ), ( 10 ), 
# ( 2 ), ( d2 ), ( 20 ), 
# ( 4 ), ( d1 ), ( 10 ), 
# ( 4 ), ( d2 ), ( 20 ), 
#
#
# has an associated attribute which is a two dimentional array
# where each internal array is a possible tuple of parameter values
# ( (a1, ... , z1), (a2, ..., z2), (a3, ... , z3) ) 
# 
# eg. ( (a1), (a2) ) x ( (b1), (b2) ) -> ( (a1, b1), ... , (a2, b2) )


## usage example 
# init_parser(); 
# add_parameter_value_space('DATASET', [d1,d2]); 
# add_parameter_value_space('DATASET_VALUE', [10,20]); 
# add_parameter_value_space('THREAD_NUM', [1,2,4]); 
# term_print(parse("THREAD_NUMx(DATASET=DATASET_VALUE)")); 

## globals ##
use Parse::RecDescent;
$::RD_HINT = 1; 


# Initializes the parser module, must be called before any other call
sub init_parser{
my $grammar = q {
  start : expression {$return = $item[1];}|error
  expression: and_expr '=' expression
               {$return = [Using::one_of_each($item[1], $item[3])];}
            | and_expr
 
   and_expr:   brack_expr 'x' and_expr 
               {$return =[Using::cart_product($item[1], $item[3])];}
           | brack_expr
 
  brack_expr: '(' expression ')'
               {$return = $item[2];}
            | term

  term: /[A-Z][A-Z_0-9]*/ 
               {$return  = [Using::term_create_attr($item[1], $Using::params{$item[1]})];}

  error:/.*/ {print "Error\n";}
};

$using_expression_parser = new Parse::RecDescent($grammar);
undef $/;
}

# Adds a parameter value space
# e.g. add_parameter_value_space("NUMTHREAD", [1,2,4,8]");
sub add_parameter_value_space{
     die if @_ != 2; 
     my ($p_name, $value_space_ref) =  @_; 
     $params{$p_name} = $value_space_ref; 
}

# Parse a using expression 
sub parse{
    die if @_ != 1; 
    my ($expr) = @_; 
    return @{$using_expression_parser->start($expr)} or print "bad input.\n"; 
}


# Transforms an array of values into the attribute format. In other words it
# turns a 1D array of values in a 2D array of values with one element per internal array
sub term_create_attr{
    die if @_ != 2; 
    my ($term_name, $value_space)= @_;
    my @output; 
    push @output, [$term_name];

    foreach $v(@{$value_space}){
	push @output, [$v];
    }
    return @output; 
}

sub term_print{

    foreach my $name (@{shift @_}){
	print "$name, ";
    }
    print "\n"; 

    foreach $v1 (@_){
	foreach $v2 (@$v1){
	    print "( $v2 ), "; 
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
    my @output;
    my ($t1, $t2) = @_;
    

   print "#CART PRODUCT ARRAY 1\n"; 
   term_print(@{$t1}); 

   print "#CART PRODUCT ARRAY 2\n";
   term_print(@{$t2}); 


    my @t1_names = @{shift @$t1};
    my @t2_names = @{shift @$t2};
    push @output, [@t1_names, @t2_names];
    
    foreach $v1 (@{$t1}){
	foreach $v2 (@{$t2}){
	    my @tmp  = (@$v1, @$v2);
	    push @output, \@tmp; 
	}
    }
    
#    print "#CART PRODUCT ARRAY OUTPUT\n"; 
#    term_print(@output); 

   return @output; 
}



sub one_of_each{
    my @output; 
    my ($t1, $t2) = @_; 


    my @t1_names = @{shift @$t1};
    my @t2_names = @{shift @$t2};
    push @output, [@t1_names, @t2_names];

    
   # print "#OOE PRODUCT ARRAY 1\n"; 
   # term_print(@{$t1}); 

   # print "#OOE PRODUCT ARRAY 2\n";
   # term_print(@{$t2}); 

    ($#$t1 == $#$t2) or die "\'=\' opertion between parameters with different number of values\n";

    for $i (0..$#$t1){
	push @output,  @{$t1}[$i]; 
	push @{$output[-1]}, @{@$t2[$i]}; 
    }

   # print "#OOE OUTPUT1\n"; 
   # term_print(@output); 
    
    
   return @output; 
}



