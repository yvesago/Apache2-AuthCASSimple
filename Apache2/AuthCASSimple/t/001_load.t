# -*- perl -*-

# t/001_load.t - check module loading and create testing directory

use Test::More tests => 1;

BEGIN { use_ok( 'Apache2::AuthCASSimple' ); }

#my $object = Apache2::AuthCASSimple->new ();
#isa_ok ($object, 'Apache2::AuthCASSimple');


