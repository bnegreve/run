# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl runtime.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;


use Test::Trap;
use Test::More tests => 4;
use Using;
use Using_Ast_Check; 

BEGIN { use_ok('Runtime') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.




declare_parameter("P1", qw(1 abc x17));
my $ast = parse("P1"); 
check_ast($ast);
my @tuples = @{ast_get_tuples($ast)};
is(Runtime::build_a_command_line("blah P1 blah", shift @tuples),
   "blah 1 blah",
   "test 1 parameter tuple 1"); 

is(Runtime::build_a_command_line("blah P1 blah", shift @tuples),
   "blah abc blah",
   "test 1 parameter tuple 2"); 

is(Runtime::build_a_command_line("blah P1 blah", shift @tuples),
   "blah x17 blah",
   "test 1 parameter tuple 3"); 
