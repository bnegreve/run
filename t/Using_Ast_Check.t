# Copyright (C) 2010-2013, Benjamin Negrevergne.
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl runtime.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;


use Test::Trap;
use Test::More tests => 12;
use Using; 

BEGIN { use_ok('Using_Ast_Check') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.


my $ast = parse("(P1=P2)cxP3f"); 

trap{check_ast($ast)};
is($Using_Ast_Check::errors, 1, "2 fail undeclared\n");
$Using_Ast_Check::errors = 0; 

declare_parameter("P1", qw(1 2 3));
trap{check_ast($ast)};
is($Using_Ast_Check::errors, 1, "2 fail undeclared\n"); 
$Using_Ast_Check::errors = 0; 

declare_parameter("P2", qw(1 2 3));
declare_parameter("P3", qw(a b));
check_ast($ast);
is($Using_Ast_Check::errors, 0, "0 fail undeclared\n");
$Using_Ast_Check::errors = 0; 

trap{declare_parameter("P3", qw(a b))};
is($Using_Ast_Check::errors, 1, "3 fail already declared\n"); 
$Using_Ast_Check::errors = 0; 

$ast = parse("(P1=P2)cxP3f"); 
check_ast($ast);
my @tuples = @{Using_Ast_Check::ast_get_tuples($ast)}; 
#expect 6 tuples of 3 value ref
is($#tuples+1, 6, "num tuples is correct\n"); 
foreach my $t (@tuples){
    is($#{$t}+1, 3, "tuple size is correct\n"); 
}

