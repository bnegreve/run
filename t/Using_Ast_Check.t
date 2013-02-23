# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl runtime.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;


use Test::More tests => 4;
use Using; 

BEGIN { use_ok('Using_Ast_Check') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.


my $ast = parse("(P1=P2)cxP3f"); 
check_ast($ast);
is($Using_Ast_Check::errors, 3, "3 fail undeclared\n"); 
declare_parameter("P1", qw(1 2 3));
check_ast($ast);
is($Using_Ast_Check::errors, 2, "2 fail undeclared\n"); 
declare_parameter("P2", qw(1 2 3));
declare_parameter("P3", qw(3));
check_ast($ast);
is($Using_Ast_Check::errors, 0, "0 fail undeclared\n");



