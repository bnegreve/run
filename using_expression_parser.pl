#!/usr/bin/perl -w
use Parse::RecDescent;
$::RD_HINT = 1; 

@a = ('a1', 'a2');
@b = ('b1', 'b2'); 
@c = ('c1', 'c2'); 
@b2 = ('b21', 'b22'); 
@bb = (\@b, \@b2); 
%params = ('A', \@a, 'B', \@b, 'C', \@c);

sub term_create_attr{
# Each term has an associated attribute which is a two dimentional array
# where each internal array is a possible set of parameter    
# ( (a1, ... , z1), (a2, ..., z2), (a3, ... , z3) ) 
# 
# eg. ( (a1), (a2) ) x ( (b1), (b2) ) -> ( (a1, b1), ... , (a2, b2) )

# argument is a ref to an array in which each element is a parameter possible value; 
# return a 2-dim array.
    my @output = ();
    my $i = 0; 
#    foreach $v(@{$_[0]}){
    foreach $v(@_){
	push @output, ();
	push @{$output[$i]}, $v; 
	$i++; 
    }
    return @output; 
}


sub term_print{
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
    ($t1, $t2) = @_; 
#    print "#CART PRODUCT ARRAY 1\n"; 
#    term_print(@{$t1}); 

#    print "#CART PRODUCT ARRAY 2\n";
#    term_print(@{$t2}); 
    
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
    ($t1, $t2) = @_; 
    
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


my @output; 


my $grammar = q {

  start : expression {$return = $item[1];}|error
  expression: and_expr '=' expression
               {$return = [main::one_of_each($item[1], $item[3])];}
            | and_expr
 
   and_expr:   brack_expr 'x' and_expr 
               {$return =[main::cart_product($item[1], $item[3])];}
           | brack_expr
 
  brack_expr: '(' expression ')'
               {$return = $item[2];}
            | term

  term: /[A-Z]+/ 
               {$return  = [main::term_create_attr(@{$main::params{$item[1]}})];}

  error:/.*/ {print "Error\n";}




};

my $using_expression_parser = new Parse::RecDescent($grammar);

undef $/;

#my $text = <STDIN>;

my $return =  $using_expression_parser->start("Ax(B=C)") or print "bad input.\n"; 

term_print(@$return); 


