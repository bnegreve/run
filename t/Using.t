# Copyright (C) 2010-2013, Benjamin Negrevergne.
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl runtime.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;

use Test::More tests => 8;


BEGIN { use_ok('Using') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.


is(Using::ast_to_string(parse("P1")), 
   "- node type: parameter, node value: { decor_string: , name: P1, }\n", "e1"); 

my ($e2out, $e3out, $e4out, $e5out, $e6out); 
$e2out = <<END; 
- node type: eq_operator
  - node type: parameter, node value: { decor_string: , name: P1, }
  - node type: parameter, node value: { decor_string: , name: P2, }
END
is(Using::ast_to_string(parse("P1=P2")), $e2out, "e2"); 
    
$e3out = <<END3; 
- node type: prod_operator
  - node type: parameter, node value: { decor_string: , name: P1, }
  - node type: parameter, node value: { decor_string: , name: P2, }
END3
is(Using::ast_to_string(parse("P1xP2")), $e3out, "e3"); 


$e4out = <<END4;
- node type: prod_operator
  - node type: eq_operator
    - node type: parameter, node value: { decor_string: , name: P1, }
    - node type: parameter, node value: { decor_string: , name: P2, }
  - node type: parameter, node value: { decor_string: , name: P3, }
END4
is(Using::ast_to_string(parse("(P1=P2)xP3")), $e4out, "e4"); 

 $e5out = <<END5;
- node type: prod_operator
  - node type: eq_operator
    - node type: parameter, node value: { decor_string: l, name: P1, }
    - node type: parameter, node value: { decor_string: c, name: P2, }
  - node type: parameter, node value: { decor_string: f, name: P3, }
END5
is(Using::ast_to_string(parse("(P1l=P2c)xP3f")), $e5out, "e5");

$e6out = <<END6;
- node type: prod_operator
  - node type: eq_operator
    - node type: parameter, node value: { decor_string: c, name: P1, }
    - node type: parameter, node value: { decor_string: c, name: P2, }
  - node type: parameter, node value: { decor_string: f, name: P3, }
END6
is(Using::ast_to_string(parse("(P1=P2)cxP3f")), $e6out, "e6");    

is(1,1, "dummy"); 
