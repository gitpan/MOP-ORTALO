# You must set the following variables to the name of some available
# machines that you have access to (and that have also NFS or similar)
# if you intend to run the tests.

my $MACHINE1 = $ENV{'REMOTE_HOST'} || "violon";

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..2\n"; }
END {print "not ok 1\n" unless $loaded;}
use MOP::Remote;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

######################### Start some white magic also

# First in fact, we test machines availability via rsh
my $err1 = system("rsh $MACHINE1 ls > /dev/null");
if ($err1 != 0) {
    print STDERR "*** Unable to rsh to $MACHINE1 - testing on localhost ***\n";
    $MACHINE1 = "localhost";
}

######################### End of white magic

###########################################
# Test program for the Meta Object system #
###########################################
#Included in the ESOPE project of LAAS-CNRS
# (c) Rodolphe Ortalo & LAAS-CNRS

#$Id: several.t,v 1.2 1999/02/09 14:14:16 ortalo Exp $

use lib 't/';
use Person;
use MOP::Remote;


sub ok ($$) {
    my($number, $result) = @_ ;
    
    print "ok $number\n"     if $result ;
    print "not ok $number\n" if !$result ;
}

my $loc = shift || $MACHINE1;
my $n = shift; $n = 100 if (!$n);

my $server = MOP::Remote::create_server(Person,$loc, 4321);

my $other_server = MOP::Remote::create_server(Person,$loc, 5432);
my $another_server = MOP::Remote::create_server(Person,$loc);

my $truc = Person->new($server);
print "State of truc:$truc\n";
$truc->name("The Truc");
print "Name of $truc: ".$truc->name()."\n";

$truc->age(12);
print "Age of $truc: ".$truc->age()."\n";
$truc->name("The Real Serious Truc");
$truc->inc_age();
$truc->inc_age(6);
for (my $i=0; $i<$n; $i++) {
	$truc->inc_age();
}

my @objs;
for (my $i=0; $i<($n/10); $i++) {
	if ($i % 5) {
	    $objs[$i] = Person->new($another_server);
	} elsif ($i %  3) {
	    $objs[$i] = Person->new("LOCAL");
	} elsif ($i % 2) {
	    $objs[$i] = Person->new($other_server);
	} else {
	    $objs[$i] = Person->new($server);
	}
	$objs[$i]->name("Another try $i");
	$objs[$i]->age(25);
	$objs[$i]->inc_age(25);
}
for (my $i=0; $i<($n/10); $i++) {
	$objs[$i]->inc_age(25);
	print  "$i th: name:".$objs[$i]->name()." age:".$objs[$i]->age()."\n";
#	$objs[$i]->DESTROY();
}


my $machin = Person->new($other_server);
$machin->name("The Machin");
$machin->age(26);
print "Name&age of $machin: ".$machin->name()." ".$machin->age()."\n";
for (my $i=0; $i<$n; $i++) {
	$machin->inc_age();
}
print "Name&age of $machin: ".$machin->name()." ".$machin->age()."\n";
print "Name of $truc: ".$truc->name()."\n";
for (my $i=0; $i<$n; $i++) {
	$truc->name("The Remote Serious (Locally cool)");
	$machin->name("The Remote Serious Machin");
}
print "Name of $truc: ".$truc->name()."\n";
print "Name&age of $machin: ".$machin->name()." ".$machin->age()."\n";

my $v2 = $machin->age();
my $s2 = $machin->name();

#$machin->DESTROY();

for (my $i=0; $i<$n; $i++) {
	$truc->inc_age(2);
}
print "Age of $truc: ".$truc->age()."\n";

my $v1 = $truc->age();
my $s1 = $truc->name();

#$truc->DESTROY();

MOP::Remote::exit_server($server);
MOP::Remote::exit_server($other_server);
MOP::Remote::exit_server($another_server);

ok(2, ( ($v1 == 319)
       && ($s1 eq "The Remote Serious (Locally cool)")
       && ($v2 == 126)
       && ($s2 eq "The Remote Serious Machin")
       ));
