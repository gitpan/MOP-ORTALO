# You must set the following variables to the name of some available
# machines that you have access to (and that have also NFS or similar)
# if you intend to run the tests.

my $MACHINE1 = $ENV{'REMOTE_HOST'} || "dukas";

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..3\n"; }
END {print "not ok 1\n" unless $loaded;}
use MOP::Remote;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

######################### Start some white magic also

# First in fact, we test machines availability via rsh
my $err1 = system("rsh $MACHINE1 ls");
if ($err1 == 0) {
    print "ok 2\n";
} else {
    print STDERR "*** Unable to rsh to $MACHINE1 - some tests not available ***\n";
    print "not ok 2\n";
}

######################### End of white magic

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

use lib 't/';
use Cwd;
use Truc;

if ($err1 == 0) {
    my $server = MOP::Remote::create_server('Truc', $MACHINE1, 1234);
    
    my $t1 = Truc->new($server);
    
    $t1->add(4);
    my $v1 = $t1->value();
    $t1->add(3);
    $t1->add(1);
    $t1->add(18);
    my $v2 = $t1->value();
    
  MOP::Remote::exit_server($server);
    
    if (($v1 != 4) || ($v2 != 26)) {
	print "not ok 3\n";
    } else {
	print "ok 3\n";
    }
} else {
    print STDERR " test 3 not available\n";
    print "not ok3\n";
}

