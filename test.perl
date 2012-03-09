#!/usr/bin/perl -w
use Parse::RecDescent;
$::RD_HINT = 1; 

@a = ('a1', 'a2');
@b = ('b1', 'b2'); 
@c = ('c1', 'c2'); 
@b2 = ('b21', 'b22'); 
@bb = (\@b, \@b2); 
%params = ('A', \@a, 'B', \@b, 'C', \@c);

my @tmp; 

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

sub print_array{
    my $array = $_[0];
    print ("ARRAY SIZE $#$array \n");
    foreach $v (@$array){
	print ("$v "); 
    }
    print ("\n"); 
}


sub parse_one_of_each{
        my @terms = @_; 

    print("PARSE CART INPUT \n"); 
    foreach $v(@terms){
    	print "$v "; 
    }
    print("\n");
    
    my @output = term_create_attr(@{$main::params{$terms[0]}});
    
    for($i = 1; $i <= $#terms; $i++){
	my @tmp = term_create_attr(@{$main::params{$terms[$i]}});
	@output = one_of_each(\@output, \@tmp);
    }

    term_print(@output); 
    return @output; 

}

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
    
   print "#CART PRODUCT ARRAY 1\n"; 
   term_print(@{$t1}); 

   print "#CART PRODUCT ARRAY 2\n";
   term_print(@{$t2}); 

    my $i = 0; 
    foreach $v1 (@{$t1}){
	my $v2 = @{$t2}[$i++];
	my @tmp  = (@$v1, @$v2);
	push @output, \@tmp; 
    }

   return @output; 
}


sub parse_cart_product{
    my @terms = @_; 

    # print("PARSE CART INPUT \n"); 
    # foreach $v(@terms){
    # 	print "$v "; 
    # }
    # print("\n");
    
    my @output = term_create_attr(@{$main::params{$terms[0]}});
    
    for($i = 1; $i <= $#terms; $i++){
	my @tmp = term_create_attr(@{$main::params{$terms[$i]}});
	@output = cart_product(\@output, \@tmp);
    }
    
    term_print(@output); 

    return @output; 
}

my $grammar = q {
  
  start    :

  term(s /=/)
              {
                 main::parse_one_of_each(@{$item[1]}); 
              }
|  term(s /x/) 
              {
                 main::parse_cart_product(@{$item[1]}); 
              }
           
  term:  /[A-Z]/

};


#$item[0] = main::term_parse_cart_product($item[1], \@{$item[2]});}
#$item[0] = $main::params{$item[1]};
my $parser = new Parse::RecDescent($grammar);

undef $/;


#my $text = <STDIN>;

$parser->start("A=C") or print "bad input.\n"; 

#@term = term_create_attr(@{$params{'A'}}); 
#term_print(@term); 

