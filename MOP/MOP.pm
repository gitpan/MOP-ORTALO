###########################################
#    A Meta-Objects Protocol for Perl5    #
###########################################
# (c) Rodolphe Ortalo, 1997-1998
#Included in the ESOPE project of LAAS-CNRS

#$Id: MOP.pm,v 1.3 1999/02/10 15:16:41 ortalo Exp $

package MOP::MOP;

use strict;
use vars qw($VERSION);

$VERSION = '1.00';

use Filter::Util::Call;

#######################################
#    FILTER TRANSFORMATION FUNCTION   #
# Warning: black magic occuring here! #
#######################################

# At import time, the importer SOURCE CODE is
# MODIFIED to enable redirection of the reflective
# methods.
sub import
{
    my $type = shift;
    if (@_) {
	# We have some methods to make reflective
	my $pattern = join('|', @_);
	filter_add(
		   sub {
		       my ($status);
		       my $match = s/sub\s+($pattern)/sub $1_Refl/
			   if ($status = filter_read()) > 0;
		       if ($match) {
			   my $sub = $1;
			   # Adds the stub now
			   $_ = "sub $sub {"
			       ." unshift \@_,'".$sub."_Refl';"
			       ." MOP::MOP::REFLECT(\@_); }\n"
			       .$_;
		       }
		       $status;
		   } );
    } else {
	# We have not been given anything: the user probably
	# simply wants to access to MOP functions.
	# So we don't install any filter.
    }
}

##########################
# LOCAL CONSTANT SYMBOLS #
##########################
my $DEBUG = 0;

###################
# LOCAL VARIABLES #
###################
# Base-Object -> Meta-Object registration procedures
my %Meta_Thingy = ();

##############################
#    FURNISHED FUNCTIONS     #
##############################
sub register_meta ($$) {
   my $meta = shift;
   my $base = shift;
   print STDERR "Associating Meta:$meta to Base:$base\n" if $DEBUG;
   $Meta_Thingy{$base} = $meta;
   return;
}
sub find_meta ($) {
   my $base = shift;
   print STDERR "Looking for Meta of Base:$base\n" if $DEBUG;
   return $Meta_Thingy{$base};
}

sub REFLECT {
    my $b_reflect = $_[0]; # 'b' for 'base'
    my $b_that = $_[1];
    my $m_that = $Meta_Thingy{$b_that}; # 'm' for 'meta'
    if ($m_that) {
	print STDERR "Meta-thingy of $b_that ($b_reflect) is $m_that\n"
		if $DEBUG;
        $m_that->meta_method_call(@_);
    } else {
	no strict 'refs'; # We need to call a sub by its name
        print STDERR "REFLECTed $b_that ($b_reflect) has no meta-thingy
		- normal call\n" if $DEBUG;
        shift; # Get rid of method name
	shift; # and of thing ref.
	$b_that->$b_reflect(@_);
    }
}

####################################
1; # Final true ending (Perl module)

__END__
# Below is the documentation of the module.

=head1 NAME

MOP::MOP - Perl extension providing a meta-object protocol for Perl modules.

=head1 SYNOPSIS

    # A random package declaration
    package MyBaseModule;

    # Activate the meta-object protocol for a few methods
    use MOP::MOP qw(new method1 method3);
    # Our meta-module is 'MyMetaModule'
    MOP::MOP::register_meta('MyMetaModule','MyBaseModule');

    # Some functions
    sub new () {
	return bless {};
    }
    sub method1 ($$) { ... }
    sub method2 ($) { ... }
    sub method3 () { ... }

=head1 DESCRIPTION

This module provides a simple and, in my opinion, powerful meta-object protocol (MOP)
for Perl5 modules.
In short, such MOP allows to I<trap the method calls> made on an object
(represented by a reference) before they reach the original module implementing
them. These method calls are redirected to another module, called the meta-module,
before their execution. The original (legitimate) destination of the method call is in
the (base) module. Of course, one day or another, the meta-module should perform the actual
normal method call at the base level, but it can do some nice things before or after
doing that. And this is the whole purpose of its existence.

MOP::MOP implements the base level part of the protocol. This module is tightly
linked with module MOP::MetaModule which implements the
other upper part of the behavior, i.e. the generic behavior of a meta-module.

In the above example, MyBaseModule is the base module, and MyMetaModule is
the meta-module (not shown here). In this example, the 3 methods new(), method1()
and method3() are modified due to the MOP.
These methods become I<reflective> methods. When a user of MyBaseModule calls
one of these methods, they are not called directly, but the
method meta_method_call() of MyMetaModule is called instead. This method is passed
the original arguments of the method call, prepended by the (base level) method name and
(base level) object reference or package name used.

Hence, if a programmer does:

    use MyBaseModule;
    my $obj = MyBaseModule->new($newarg);
    $obj->method1($foo, $bar);
    $obj->method2($bur);
    $obj->method3();

In fact, the actual operations taking place correspond to the following steps.

=over 4

=item 1.

C<$obj = MyMetaModule-E<gt>meta_method_call(new_Refl, 'MyBaseModule', $newarg)>

This occurs in place of the first call, as MyMetaModule is registered as the
meta-module of MyBaseModule.

=back

Then, supposing that at the end of this strange new() a meta-object 
referenced by $metaobj is registered for the freshly created $obj, the processing
will continue as in the following.

=over 4

=item 2.

$metaobj-E<gt>meta_method_call(I<method1_Refl>, $obj, $foo, $bar)

This is the call of a reflective method on $obj and such calls are
processed by the meta-object, not by perl itself directly (even though
Perl behavior remains valid somewhere else).

=item 3.

$obj-E<gt>method2($bur)

This is a normal method call. As method2() is I<not> reflective, the
work is done by perl itself.

=item 4.

$metaobj-E<gt>meta_method_call(I<method2_Refl>, $obj)

Again, a reflective method call to finish.

=back

I<Note>: Here, even if they are actually used, the I<blabla_Refl> names are only for
illustration. They represent the
name of the base level method. The meta-object needs them if it ever wants
the real work to be done. But note that the structure of these names may not follow
this scheme indefinitely (and these thingies may become code references in the future).
See  meta_handle_method_call() in MOP::MetaModule.

A MOP is mainly useful for modules that provide a rather strict
object-oriented interface. It allows to extend transparently the functionality
provided by such a class module in order to provide additional
properties not directly related to the module functions. This may sound rather
obscure, but it can really be useful.
For example, this is the case in the real world when you want to add transparent
distribution to your programs, when you want to enhance such distributed execution
with a CRC integrity check in messages, when you want to manage multiple replicas
of a server, etc.

=head2 Functions

=over 4

=item C<MOP::MOP::register_meta($metaobj,$obj)>

Registers the object $metaobj as the meta-object of the (base) object
$obj. This allows the MOP to find which meta-object is associated to
a given object (the meta-level often needs a state, stored in the meta-object).
You can also directly associate a meta-module to a module. This is even necessary
to bootstrap the protocol somewhere.

=item C<MOP::MOP::find_meta($obj)>

Finds the meta-object associated to $obj. It is usually not needed to
call this function directly as the MOP itself provides the base level
object to the meta-object among the arguments to meta_method_call().

=back

=head2 Is it possible to do something useful with this?

The test programs included with the distribution of this module demonstrate
such usage (and I hope that the number of really useful meta-modules will increase
as time goes and files migrate from F<t/> to their own subdirectory). Most simple
examples deal with not very useful meta-modules, such as counting the number
of method calls, tracing some method calls, etc.

More serious examples
include a full-featured client/server system that should allow to execute any Perl
object remotely without modifying the source code of the original module. The MOP
traps the creation and local method calls on the object (which remains an empty proxy
on the client side). The meta-module takes care of redirecting all calls and calling
the real object on the server.
See module MOP::Remote.
Note that you need the Data::Dumper module to run that test. Currently, it is blindly
based on the availability of the Unix B<rsh> command. But I've been seriously using
this mechanism for distributed processing for more than one year up to now.

A future demo program that will be added soon will show how to add
some (simple) encryption to that remote execution system. The idea is simply to
encrypt transparently the data exchanged by the client/server meta-objects, using
another meta-object. Thus introducing to the world a I<meta> meta-module.

=head2 Notes

The MOP::MOP module is implemented as a source filter and is dependent on
the Filter::Util::Call module.

This module transparently I<modifies the source code of your module>. It really
renames the method subroutines and replaces them by stubs. Be warned
that we are somehow redefining the world...

Would it be possible to keep the module source code somewhere in memory
and track the C<use>s of libraries thanks to this mechanism? It could be nice
to enable Perl to send all this to another host...

=head1 BUGS

Functions stubs (e.g.: C<sub truc;>) probably do not work.

This documentation is much bigger than the module code itself.
Do not hesitate to read the source code!

=head1 AUTHOR

Rodolphe Ortalo, ortalo@laas.fr

=head2 Acknowledgements

This work has been performed with the support of LAAS-CNRS.

=head1 SEE ALSO

perl(1), MOP::MetaModule(3), MOP::Remote(3), Filter::Util::Call(3).

=cut
