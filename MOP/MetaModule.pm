###########################################
#    A Meta-Objects Protocol for Perl5    #
###########################################
# (c) Rodolphe Ortalo, 1997-1998
#Included in the ESOPE project of LAAS-CNRS

#$Id: MetaModule.pm,v 1.3 1999/02/10 15:16:41 ortalo Exp $

package MOP::MetaModule;

use strict;

##########################
# LOCAL CONSTANT SYMBOLS #
##########################
my $DEBUG = 0;

##################
#  META-METHODS  #
##################

# Default implementation of meta-methods for sub-classes

# We simply call the 'handle' meta-method
sub meta_method_call {
    my $that = shift; # This is me ('m' for meta... :-)
    # Same behavior if call for a base-class or base-object method
    print STDERR "meta_method_call called for $_[0]\n" if $DEBUG;
    $that->meta_handle_method_call(@_);
}

# And this method calls the base-level method (aka. base-method)
sub meta_handle_method_call {
    my $meta_that = shift;
    my $base_method = shift;
    my $base_that = shift;
    print STDERR "meta_handle_method_call: calling $base_that->$base_method\n"
	if $DEBUG;
    $base_that->$base_method(@_);
}

#############
#  METHODS  #
#############

# Creates a new (empty) meta-object from class or object
sub new {
    my $self = shift;
    my $type = ref($self) || $self;
    return bless {}, $type;
}

1; # Final true ending

__END__
# Below is the documentation of the module.

=head1 NAME

MOP::MetaModule - Perl base class for all meta-modules.

=head1 SYNOPSIS

Basic usage example. Absolutely useless.

  use MOP::MetaModule;
  use MOP::MOP;
  use MyBaseModule; # A reflective package

  my $obj = MyBaseModule->new();
  my $raw_meta_obj = MOP::MetaModule->new();

  # Provides (or replaces) the meta-object for the base object
  MOP::MOP::register_meta($raw_meta_obj, $obj);

  $obj->method1($foo,$bar);# With a raw meta-object, method calls are
  $obj->method2($bur);     # done normally.  But they are done by the
  $obj->method3();         # meta-object. (I told you it was useless.)

Simple derived class that correspond to the normal context of a meta-module.
It allows to perform additional operations before or after the method call.
    
  use MOP::MetaModule;
  use MOP::MOP; # We probably use some MOP function somewhere

  use vars qw(@ISA);
  @ISA = qw(MOP::MetaModule);

  # Overload the meta-level management of a method call
  sub meta_method_call {
     # Get the meta-object (sometimes a meta-module)
      my $meta_that = shift;
      # Get the (base level) method name
      my $reflected_method = shift;
      # Normal method arguments (including base self)
      my @method_args = @_;
      # Placeholder for returned value(s)
      my @returned;
      ...
      # Here, you have full control over how the actual method call
      # will take place. So, do something nice that enhances the object
      # behavior, and somewhere, you can do the real method call with:
      @returned = $meta_that->meta_handle_method_call($reflected_method,
						      @method_args);
      ...
      return wantarray ? @returned : $returned[0];
  }

=head1 DESCRIPTION

=head2 Methods

=over 4

=item C<MOP::MetaModule-E<gt>new()> I<or> $meta_thing-E<gt>new()

Creates a new raw meta-object from the MOP::MetaModule class. This one will
do nothing except normal method calls. This method should be overloaded, but
the default method will provide you an anonymous hash that you can use directly
as a placeholder for some named attributes if you want.

=item $meta_thing-E<gt>meta_method_call($method_name, $base_arguments)

This method is called by the meta-object protocol (MOP) when a (reflective) method
call is performed on a base level object controlled by a meta-object. Hence, it provides
the entry point where you should customize the meta-object behavior if you want to
do something nice for the object. This method should be overloaded in real
meta-classes. For example, you can imagine saving some state
before the call, and restoring that state in case the method fails the rough way.
The meta-object could also call a remote server (see MOP::Remote).
The MOP may call this method either via a blessed reference (a real meta-I<object>)
or on the module itself (that behaves then like a meta-I<class>).

=item $meta_thing-E<gt>meta_handle_method_call($method_name, $base_arguments)

This method will perform the actual call to the base level class or object and
return you the results from this call. Inside the meta-object methods, this one
allows you to activate the real method call requested originally by the programmer
(or by a lower meta-level). You should use this method that you will inherit
from MOP::MetaModule to do so as it will be able to locate the original method
thanks to the method name provided by the MOP.

=head2 Usage outline

In the following example, the synopsis is detailed a little further to show
how you can write a meta-module. Most of the work is done inside
the meta_method_call() method which needs to study the base level methods
names and act accordingly. Base level constructors deserve special care as the
meta-module should usually create a meta-object and register it with the freshly
created base level object (see the C</new/> case below).
More generally, pure class methods called on the base module should be treated
with care at the meta-level.

  # We are a meta-module: use MetaModule to inherit from it
  use MOP::MetaModule;
  # We probably use the MOP register function in object creation
  use MOP::MOP;

  use vars qw(@ISA);
  @ISA = qw(MOP::MetaModule);

  ###  META-METHODS  ###
  # Trap of method call
  sub meta_method_call {
      my $meta_that = shift; # meta-object (sometimes meta-module)
      my $reflected_method = shift; # Get the (base) method name
      my @method_args = @_; # Normal method arguments (w/ self)
      my @returned; # Placeholder
      # Switch on method name.
      foreach ($reflect) {
	  # Specific behavior for 'new' method: meta-object creation
	  /new/o and do {
	      # We call the base-level creation method
	      @returned =
	       $meta_that->meta_handle_method_call($reflected_method,
						   @method_args);
	      # We create a meta object for this object
	      my $meta_object = $meta_that->new();
	      # ...we initialize it if we need some meta-state...
	      # We register both the object and meta-object.
	    MOP::MOP::register_meta($meta_object, $returned[0]);
	      last;
	  };
	  # First, we manage only object methods... (Not mandatory)
	  if (ref($m_that)) {
	      # Behavior for working methods
	      /method1|method3/o and do {
		  ...do something nice before the method call...
		  @returned =
		   $meta_that->meta_handle_method_call($reflected_method,
						       @method_args);	    
		  ...do something nice after the method call...
	      };	
	  } else { # Here, we deal we class methods...
	      ...spit some warning...but call it anyway...
	      @returned =
	       $meta_that->meta_handle_method_call($reflected_method,
						   @method_args);
	  }
      }
      return wantarray ? @returned : $returned[0];
  }

Useful work can be performed on normal method calls on base level objects
(see the C</method1|method3/> case above). At this point, you have full control
on the method parameters and behavior. Possible usages involve: security management
via authorization verification or arguments encryption, fault tolerance via multiple
replicas management or stable storage of object state, transparent remote execution,
and maybe a combination of these.

=head1 BUGS

It is not yet clear how I<destruction> of base level objects can be
trapped and handled in the meta-module. Expect improvement on this
point (and an additional class method to manage carefully in the
meta-object).

=head1 AUTHOR

Rodolphe Ortalo, ortalo@laas.fr

=head2 Acknowledgements

This work has been performed with the support of LAAS-CNRS.

=head1 SEE ALSO

perl(1), MOP::MOP(3).

=cut
