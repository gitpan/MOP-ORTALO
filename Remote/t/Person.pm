###########################################
# Test module for the Meta Module system  #
###########################################
# (c) 1997-9, Rodolphe Ortalo & LAAS-CNRS

#$Id: Person.pm,v 1.2 1999/02/09 14:14:15 ortalo Exp $

package Person;

use Carp;
use MOP::MOP qw(new inc_age name age);

MOP::MOP::register_meta(MOP::Remote, Person);

my $DEBUG = 0;

my %fields = (
	name => undef,
	age  => undef,
);

sub new {
	print "Person:new method called\n" if $DEBUG;
	my $that = shift;
	my $class = ref($that) || $that;
	my $self = {
		%fields,
		};
	bless $self, $class;
	return $self;
}

sub DESTROY {
  print "Destroying...\n" if $DEBUG;
}

sub inc_age {
	my $self = shift;
	croak "$self is not an object" unless ref($self);
	if (@_) {
		return $self->{'age'} += shift;
	} else {
		return $self->{'age'}++;
	}
}

sub name {
	my $self = shift;
	croak "$self is not an object" unless ref($self);
	if (@_) {
		return $self->{'name'} = shift;
	} else {
		return $self->{'name'};
	}
}

sub age {
	my $self = shift;
	croak "$self is not an object" unless ref($self);
	if (@_) {
		return $self->{'age'} = shift;
	} else {
		return $self->{'age'};
	}
}

