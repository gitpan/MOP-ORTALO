# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..4\n"; }
END {print "not ok 1\n" unless $loaded;}
use MOP::MOP;
use MOP::MetaModule;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

### First, some preparation

my $DEBUG = 0;

sub ok ($$) {
    my($number, $result) = @_ ;
    
    print "ok $number\n"     if $result ;
    print "not ok $number\n" if !$result ;
}

### We use the black magic now...

package MyBaseModule;

use MOP::MOP qw(new method1 method3);

sub new () {
    return bless {
	COUNT1 => 0,
	COUNT2 => 0,
	COUNT3 => 0,
    };
}
sub method1 {
    my ($o,$a,$b) = @_;
    $o->{COUNT1}++;
    print "In method1 of $o: $a, $b\n" if $DEBUG;
    return 'method1 value';
}
sub method2 {
    my ($o,$a) = @_;
    $o->{COUNT2}++;
    print "In method2 of $o: $a\n" if $DEBUG;
    return 'method2 value';
}
sub method3 {
    my ($o) = @_;
    $o->{COUNT3}++;
    print "In method3 of $o\n" if $DEBUG;
    return 'method3 value';
}

package OtherBaseModule;

use MOP::MOP qw(foo bar bizz);

sub new {
    return bless {};
}
sub foo {
    my ($o,$mybase) = @_;
    $o->bar('baba');
    $mybase->method3();
    $mybase->method2('baba');
    $mybase->method3();
    return $mybase->method1($o->bizz());
}
sub bar {
    my ($o, $b) = @_;
    return;
}
sub bizz {
    my ($o) = @_;
    $o->bar('hic');
    return ('un','deux');
}

# Counting meta-module

package MyMetaModule;

use MOP::MetaModule;
@ISA = qw(MOP::MetaModule);

sub meta_method_call {
    my $that = shift;
    my $reflect = $_[0];
    my $base_object = $_[1];
    my $ret;
    if (ref($that)) {
	$that->{NUMBER}++;
	print "META: Calling the object method '$reflect' (".$that->{NUMBER}." call)...\n" if $DEBUG;
	$ret = $that->meta_handle_method_call(@_);
    } else {
    	for ($reflect) {
		/new/o	and do {
			print "META: Creating new base object '$reflect'..." if $REFLECT;
			$base_object = $that->meta_handle_method_call(@_);
			$meta_object = $that->new();
			MOP::MOP::register_meta($meta_object,$base_object);
			$meta_object->{NUMBER} = 0;
			$ret = $base_object;
			last;
			};
		$that->{ERROR} = "Unhandled class method $reflect at meta-level, calling anyway";
		print "Unhandled class method $reflect at meta-level, calling anyway" if $DEBUG;
		$ret = $that->meta_handle_method_call(@_);
    	}
    }
    print "Done\n" if $DEBUG;
    return $ret;
}

# Indenting level meta-module

package BuildCallTree;

use MOP::MetaModule;
@ISA = qw(MOP::MetaModule);

my $level = 0;
$call_tree = "";

sub meta_method_call {
    my $that = shift;
    my $reflect = shift;
    my $base_that = shift;

    my $basetype = ref($base_that) || $base_that;
    my @args = ();
    foreach $a (@_) {
	push @args, (ref($a) || $a);
    }
    my $m = $reflect;
    $m =~ s/_Refl//o;
    for(my $i = 0; $i < $level; $i++) {
	$call_tree .= "\t";
    }
    $call_tree .= "$basetype->$m(".join(',',@args).")\n";
    $level++;

    my @ret = $that->meta_handle_method_call($reflect, $base_that, @_);
    if ($reflect =~ /new/o) {
      MOP::MOP::register_meta($that->new(),$ret[0]);
    }

    $level--;
    return wantarray ? @ret : $ret[0];
}

package main;

use MOP::MOP;

### Second test: Empty (default) meta-module

print "Empty meta-level test:\n" if $DEBUG;
my $o = MyBaseModule->new();
$o->method1('one','two');
$o->method2('three');
$o->method2('three');
$o->method3();
$o->method1($o->method2('four'),$o->method3());
$o->method3();
$o->method3();

my $mo = MOP::MOP::find_meta($o);
ok(2, (($o->{COUNT1} == 2)
       && ($o->{COUNT2} == 3)
       && ($o->{COUNT3} == 4)
       && (not(defined($mo)))) );

### Third test: A counting meta-module

MOP::MOP::register_meta('MyMetaModule','MyBaseModule');

print "\nCounting meta-level test:\n" if $DEBUG;
my $o2 = MyBaseModule->new();
my $o3 = MyBaseModule->new();
$o2->method1('one','two');
$o2->method2('three');
$o2->method3();
$o3->method3();
$o2->method2('three');
$o2->method3();
$o3->method2('three');
$o2->method3();
$o2->method1($o2->method2('four'),$o2->method3());
$o3->method3();

my $mo2 = MOP::MOP::find_meta($o2);
my $mo3 = MOP::MOP::find_meta($o3);
ok(3, (($o2->{COUNT1} == 2)
       && ($o2->{COUNT2} == 3)
       && ($o2->{COUNT3} == 4)
       && (defined($mo2))
       && ($mo2->{NUMBER} == 6) && (not($mo2->{ERROR}))
       && ($o3->{COUNT1} == 0)
       && ($o3->{COUNT2} == 1)
       && ($o3->{COUNT3} == 2)
       && (defined($mo3))
       && ($mo3->{NUMBER} == 2) && (not($mo3->{ERROR}))));

### Fourth test: A tracing meta-module

MOP::MOP::register_meta('BuildCallTree','OtherBaseModule');
MOP::MOP::register_meta('BuildCallTree','MyBaseModule');

my $o4 = MyBaseModule->new();
my $o5 = MyBaseModule->new();
$o4->method3();
my $other = OtherBaseModule->new();
$other->foo($o4);
$o4->method1('hic','hop');
$other->bizz();
$other->foo($o5);
$other->foo($o4);

my $true_res = <<'EOM' ;
MyBaseModule->new()
MyBaseModule->new()
MyBaseModule->method3()
OtherBaseModule->new()
OtherBaseModule->foo(MyBaseModule)
        OtherBaseModule->bar(baba)
        MyBaseModule->method3()
        MyBaseModule->method3()
        OtherBaseModule->bizz()
                OtherBaseModule->bar(hic)
        MyBaseModule->method1(un,deux)
MyBaseModule->method1(hic,hop)
OtherBaseModule->bizz()
        OtherBaseModule->bar(hic)
OtherBaseModule->foo(MyBaseModule)
        OtherBaseModule->bar(baba)
        MyBaseModule->method3()
        MyBaseModule->method3()
        OtherBaseModule->bizz()
                OtherBaseModule->bar(hic)
        MyBaseModule->method1(un,deux)
OtherBaseModule->foo(MyBaseModule)
        OtherBaseModule->bar(baba)
        MyBaseModule->method3()
        MyBaseModule->method3()
        OtherBaseModule->bizz()
                OtherBaseModule->bar(hic)
        MyBaseModule->method1(un,deux)
EOM

my $real_res = $BuildCallTree::call_tree;
# Why these chop()s ?
ok(4, chop($true_res) eq chop($real_res));
print "Call Tree:\n" if $DEBUG;
print $BuildCallTree::call_tree if $DEBUG;
