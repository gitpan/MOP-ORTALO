###########################################
# Perl meta-module providing basic client-#
# server functions for remote execution.  #
###########################################
# 1997-9, (c) Rodolphe Ortalo & LAAS-CNRS

#$Id: Remote.pm,v 1.3 1999/02/10 15:17:14 ortalo Exp $

package MOP::Remote;

use strict;
use Carp;
use FileHandle;
use Socket;
use Config;
use Cwd;
use Data::Dumper;
use MOP::MOP; # We use the MOP for object creation
use MOP::MetaModule; # We use MetaModule to inherit from it

use vars qw($VERSION @ISA);

@ISA = qw(MOP::MetaModule);

# This is the version of MOP::Remote (specifically)
$VERSION = '0.80';


################################
#  LOCAL CONSTANTS DEFINITIONS #
################################
# Socket basic parameters
my $MAX_START_ATTEMPTS = 90; # (s) Max Connection attempts on server start
my $MAX_CALL_ATTEMPTS = 90; # (s) Max connection attempts on method call
my $DEFAULT_BASE_PORT = 2345;

# DEBUG FLAGS
# Be careful if adding a new debug flag...
# STD{OUT,ERR} can be closed by create_server on remote host...
my $DEBUG = 0;
my $DEBUG2 = 0;

###################
# LOCAL VARIABLES #
###################
# Id of object (for identification on the server)
my $OBJECT_ID = 1;
# Server-local objects
my %SERVER_OBJECT = ();
# Previous guesses for remote Perl executable names
my %previous_guess = ();
# Previous guesses for remote archnames
my %arch_prev_guess = ();

################################################################
# The following function is the real key of this (meta-)module #
# Other functions (that implement the client server protocol)  #
# could be replaced by specialized modules... Like EventServer.#
################################################################

######################
#    META-METHODS    #
######################

# Trap of method call on server or client side
sub meta_method_call {
    my $m_that = shift; # 'm' for meta
    my $reflect = shift;
    my @args = @_;
    my @ret;
# We have problems with the object destruction in the MOP currently -- ortalo
#    if ($reflect =~ /DESTROY/o) {
#	print STDERR "Destroy method $reflect seen in meta-object $m_that of $$ ";
#	print STDERR "Args-$$:"; print STDERR @args; print STDERR "\n";
#    }
    foreach ($reflect) {
	# Specific behavior for 'new' method
	/new/o and do {
	    my $s = pop @args; # get first arg (server or server type)
	    foreach ($s) {
		/LOCAL/o and do { # On a local server...
		    # ...we call directly the creation method...
		    @ret = $m_that->meta_handle_method_call($reflect, @args);
		    # ...we create the meta object...
		    my $mo = $m_that->new();
		    # ...we set its type...
		    $mo->{TYPE} = 'LOCAL';
		    # ...and we register both.
		  MOP::MOP::register_meta($mo, $ret[0]);
		    last;
		};
		/SERVER/o and do { # For a real server side...
		    # ...we create the object my calling the method...
		    my $new_obj = $m_that->meta_handle_method_call($reflect, @args);
		    # ...we also create the meta-object...
		    my $mo = $m_that->new();
		    # ...we set its type to 'real server'...
		    $mo->{TYPE} = 'SERVER';
		    # ...we register both objects...
		  MOP::MOP::register_meta($mo, $new_obj);
		    # ...we allocate a (net-)global id to the object served...
		    my $distant_id = "$$-".$OBJECT_ID++;
		    # ...we register the id and the server object...
		    server_register_that($distant_id, $new_obj);
		    # ...and we return the id (to the client).
		    @ret = ($distant_id);
		    last;
		};
		# Default:  When we are on the client...
		# ...we find the package name (new is a class method)...
		my $package = $args[0];
		print STDERR "META: Class method $reflect called\n"
		    if $DEBUG;
		# ...we remove the MOP suffix... TODO:Should be a function of MOP::MOP
		$reflect =~ s/_Refl//o;
		# ...we call the server for creation on itself...
		my @ans = call_server($s, $reflect, @args, 'SERVER');
		# ...we create a proxy object (empty at the base level)...
		my $new_object = bless {}, $package;
		# ...we recover the ID of the object on the server...
		my $new_object_id = $ans[0];
		print STDERR "New remote object id in $$: $new_object_id\n" if $DEBUG;
		# ...we create and initialize a meta-object (client side)...
		my $meta_object =  $m_that->new();
		$meta_object->{SERVER} = $s;
		$meta_object->{TYPE} = 'CLIENT';
		$meta_object->{ID} = $new_object_id;
		# ...we register both client object to the meta protocol...
	      MOP::MOP::register_meta($meta_object,$new_object);
		# ...and we return the proxy.
		@ret = ($new_object);
	    }
	    last;
	};
	# Default: behavior for 'work' calls
	if (ref($m_that)) {
	    my $t = $m_that->{TYPE};
	    foreach ($t) {
		/SERVER|LOCAL/o and do { # If we are on a server (local or real)...
		    # ...we simply do the call requested.
		    @ret = $m_that->meta_handle_method_call($reflect, @args);
		    last;
		};
		/CLIENT/o and do { # If we are on a client...
		    # ...we get the method name... TODO:Should be a function of MOP::MOP
		    $reflect =~ s/_Refl//o;
		    shift @args; # Remove local object reference
		    unshift @args, $m_that->{ID}; # Adds reference to the object ID
#		    print STDERR "Local object ID: '".$m_that->{ID}."'\n";
		    # ...and call the server...
		    @ret = call_server($m_that->{'SERVER'}, $reflect, @args);
		    last;
		};
		croak "Meta:$m_that for Base:$_[0] neither client nor server";
	    }
	} else {
	    carp "Unhandled class method $reflect at meta-level, calling anyway";
	    @ret = $m_that->meta_handle_method_call($reflect, @args);
	}
    }
    return wantarray ? @ret : $ret[0];
}


###########################
# LOCAL STATIC PROCEDURES # TODO: Put these in a sub-package ?
###########################

# Utility methods (send/receive arguments over a socket)
# Data::Dumper is used to transfer the data
sub _send_data (*$) {
    my $fh = shift;
    my $data_ref = shift;
    my $d = Data::Dumper->new([$data_ref], [qw(MsgData)]);
    $d->Purity(1);
    $d->Indent(0);
    my $msg = $d->Dumpxs();
    $msg .= "\nEOM\n";
    print $fh $msg;
    return;
}
sub _get_data (*) {
    my $fh = shift;
    my $msg = "";
    my $line;
    my $n = 0 if $DEBUG;
    while (defined($line = <$fh>)) {
	last if ($line =~ /^EOM$/o);
	$msg .= $line;
	$n++ if $DEBUG;
    }
    print STDERR "_get_data: Read $n lines\n$msg" if $DEBUG2;
    my $MsgData;
    eval $msg;
    return $MsgData;
}

# Initialize the local server
# (creates the socket, configure it, etc.)
sub _server_init ($$$) {
    my ($location, $port, $module_served) = @_;
    
    # Server does not have any input (STDIN is closed)
    # Server is ALSO disconnected from any output if no debug flag.
    my $server_sock = new FileHandle;
    my $proto = getprotobyname('tcp');
    socket($server_sock, PF_INET, SOCK_STREAM, $proto) or die "socket: $!";
    setsockopt($server_sock, SOL_SOCKET, SO_REUSEADDR, pack("l", 1))
	or die "setsockopt: $!";
    setsockopt($server_sock, SOL_SOCKET, SO_LINGER, pack("ll", 0, 0))
	or die "setsockopt: $!";
    bind($server_sock, sockaddr_in($port, INADDR_ANY)) or die "bind: $!";
    listen($server_sock, SOMAXCONN) or die "listen: $!";
    $server_sock->autoflush();
    print STDERR "Server started on $location, port $port for module $module_served (PID:$$)\n"
	if $DEBUG;
    # Starting real server loop
    _server_loop($module_served, $server_sock);
    # THIS CODE SHOULD NEVER BE EXECUTED
    die "Unreachable code";
}

# Server loop code for serving a module
sub _server_loop ($$) {
    my ($module_served, $server_socket) = @_;
    server_register_that($module_served,$module_served); # root: for module class

    my $new_socket = new FileHandle;
    my $paddr = accept($new_socket, $server_socket); #send a message when server starts
    $new_socket->autoflush();
    my ($new_port, $client_iaddr) = sockaddr_in($paddr);
    my $client_name = gethostbyaddr($client_iaddr, AF_INET);
    my $inf = _get_data($new_socket);
    die "problem with abnormal server initialisation" unless $inf->[0] eq "READY";
    _send_data($new_socket, ["STARTED"]);
    close $new_socket;
    while (1) {
	my $paddr = accept($new_socket, $server_socket);
	$new_socket->autoflush();
	my ($new_port, $client_iaddr) = sockaddr_in($paddr);
	my $client_name = gethostbyaddr($client_iaddr, AF_INET);
	print STDERR "Connection from $client_name [".inet_ntoa($client_iaddr)."], service port: $new_port\n"
	    if $DEBUG2;
	# Process the request
	my $req_ref = _get_data($new_socket);
	my @request = @$req_ref;
	my $m = shift @request;
	if ($m eq "EXIT_SERVER") {
	    _send_data($new_socket, ["EXITING"]);
	    close $new_socket;
	    close $server_socket;
	    print STDERR "Server exiting\n" if $DEBUG;
	    exit 0;
	}
	if ($m eq "READY") {
	    _send_data($new_socket, ["NOT_OK"]);
	    close $new_socket;
	    close $server_socket;
	    print STDERR "Bad initialisation call on server already started\n" if $DEBUG;
	    # Commit suicide anyway... Tough world isn't it?
	    exit 0;
	}
	my $o = shift @request; # May be class name
	$m =~ s/.*:://o;
	die "Unknown object key in server $$" unless $SERVER_OBJECT{$o};
	my @resp = $SERVER_OBJECT{$o}->$m(@request);
	_send_data($new_socket, \@resp);
	close $new_socket;
    }
    # THIS CODE SHOULD NEVER BE EXECUTED
    die "Unreachable code";
}

##############################
#    EXPORTABLE FUNCTIONS    #
##############################

#########################
# SERVER-SIDE FUNCTIONS #
#########################

# This function register a new local object in our server
sub server_register_that ($$) {
    my ($that_key, $that) = @_;
    $SERVER_OBJECT{$that_key} = $that;
    return;
}

# This function returns the number of local objects for
# this server
sub server_num_reg () {
    return scalar(keys %SERVER_OBJECT);
}

# This functions closes one server
sub exit_server ($) {
    my ($server) = @_;

    my $remote = $server->{ServerLocation};
    my $port = $server->{ServerPort};
    print STDERR "Destroying server on $remote, port $port\n" if $DEBUG;
    my ($iaddr, $paddr, $proto, $line);
    $iaddr = inet_aton($remote);
    $paddr = sockaddr_in($port, $iaddr);
    $proto = getprotobyname('tcp');
    my $sockhandle = new FileHandle;
    socket($sockhandle, PF_INET, SOCK_STREAM, $proto) or die "socket: $!";
    connect($sockhandle , $paddr) or die "connect: $!";
    $sockhandle->autoflush();
    # Do the actual communication
    _send_data($sockhandle, ["EXIT_SERVER"]);
    my $ack_ref = _get_data($sockhandle);
    die "Server on $remote, $port did not exit" unless ($ack_ref->[0] =~ /EXITING/o);
    print STDERR "Server on $remote exited.\n" if $DEBUG;
    # Close socket
    close $sockhandle;
    return;
}

# Tries to guess the Perl executable path name at given location
# Also tries to guess archname. Not a clean hack for sure
sub guess_perl_exec ($) {
    my ($location) = @_;
    return $previous_guess{$location} if defined($previous_guess{$location});
    my @attempts = ('perl', $^X, '/usr/local/bin/perl'); # Add more guesses if you want here
    foreach $b (@attempts) {
	open(TRYING,"rsh $location $b \"-e 'print 123456; use Config; print \\\$Config{archname};'\" 2>&1 |");
	my $out = "";
	my $line = "";
	while (defined($line = <TRYING>)) { $out .= $line; }
	close TRYING;
	if ($out =~ /123456/o) {
	    $previous_guess{$location} = $b;
	    # Get archname and cache it
	    $out =~ /^123456(.+)$/o;
	    my $arch = $1;
	    $arch_prev_guess{$location} = $arch if ($arch);
	    return $b;
	}
    }
    die "Unable to find remote Perl executable on $location: please provide path.";
}
# Tries to guess the archname at given location
# TODO: Double check! This is not a clean hack!
sub guess_perl_arch ($) {
    my ($location) = @_;
    return $arch_prev_guess{$location} if defined($arch_prev_guess{$location});
    my $pbin = guess_perl_exec($location); # Check exec name.
    open(TRYING,"rsh $location $pbin \"-e 'use Config; print \\\$Config{archname}; print;'\" 2>&1 |");
    my $out = "";
    my $line = "";
    while (defined($line = <TRYING>)) { $out .= $line; }
    close TRYING;
    $out =~ s/\n.*//o;
    $arch_prev_guess{$location} = $out;
    return $out;
}
# Start a remote perl script via rsh with the same environement
# as us.
sub start_remote_script ($$$;$) {
    my ($location, $perl_inst, $debug, $perl_exe) = @_;
    my $perl_to_use = $perl_exe || guess_perl_exec($location);
    # Obtain remote host archname
    my $rem_arch = guess_perl_arch($location);
    # Get current directory
    my $pwd = cwd();
    print STDERR "Starting remote Perl with RSH on host $location ($rem_arch).\n" if $debug;
    # Build list of module directories to include.
    my $archname = $Config{'archname'};
    my @noarch_inc = ();
    # Look into INC and substitutes the architecture names... (Best effort)
    foreach my $dir (@INC) {
	if ($dir =~ /$archname/) {
	    my $new_d = $dir;
	    $new_d =~ s/$archname/$rem_arch/;
	    push @noarch_inc, $new_d;
	} else {
	    push @noarch_inc, $dir;
	}
    }
    unless ($debug) {
	# Without debug, we do the fork on remote host and close all outputs
	my $script = "BEGIN { close STDIN; close STDOUT; close STDERR;  fork() and exit(0); chdir(\"$pwd\"); }  use lib qw(".join(' ',@noarch_inc).");".$perl_inst."\n";
	open(REMOTE, "|rsh $location $perl_to_use")
	    or die "Unable to launch remote server on $location (".$$.")";
	print REMOTE $script."\n";
	close REMOTE;
    } else {
	# We need additional work on local host if we want to see debug output
	my $booter_pid;
	if ($booter_pid = fork) {
	    # Parent here, we must go on
	} elsif (defined $booter_pid) {
	    # child here: we don't close outputs
	    close STDIN; # Just in case...
	    my $script = " BEGIN { close STDIN; chdir(\"$pwd\"); }  use lib qw(".join(' ',@noarch_inc)."); ".$perl_inst."\n";
	    open(REMOTE, "|rsh $location $perl_to_use")
		or die "Unable to launch remote server on $location (".$$.")";
	    print REMOTE $script."\n";
	    close REMOTE;
	    wait;
	    exit(0);
	} else {
	    # fork error
	    die "Can't fork: $!\n";
	}
    }
}
# Creation of a new server
sub create_server ($;$$$) {
    my $type = shift;
    my $location = shift || 'localhost';
    my $port = shift || $DEFAULT_BASE_PORT++;
    my $perl_to_use = shift;
    print STDERR "Starting server for module $type on host $location port $port\n" if $DEBUG;
    start_remote_script($location,"use $type; use MOP::Remote; MOP::Remote::_server_init($location, $port, $type); die(\"Unable to initialize server for $type\");",($DEBUG || $DEBUG2),$perl_to_use);
    # waiting start signal of server to quit create_server 
    print STDERR "Waiting a little for server to start\n" if $DEBUG;
    my ($iaddr, $paddr, $proto);
    $iaddr = inet_aton($location);
    $paddr = sockaddr_in($port, $iaddr);
    $proto = getprotobyname('tcp');
    my $attempt = 0;
    while ($attempt < $MAX_START_ATTEMPTS) {
	my $sockhandle = new FileHandle;
	socket($sockhandle, PF_INET, SOCK_STREAM, $proto) or die "socket: $!";
	connect($sockhandle, $paddr) or (close $sockhandle , sleep 1 , $attempt++ , next);
	$sockhandle->autoflush();	
	# Do the actual communication
	_send_data($sockhandle, ["READY"]);
	my $ack_ref = _get_data($sockhandle);
#	print $ack_ref->[0]."\n";
	if ( $ack_ref->[0] eq "STARTED") {
	    print STDERR "Signal server on $location started.\n" if $DEBUG2;
	} else {
	    carp "Server didn't start normally on $location" if $DEBUG2;
	    return undef;
	}
	# Close socket
	close $sockhandle;
	last;
    }
    if ($attempt >= $MAX_START_ATTEMPTS) { # we can't connect to the server, it doesn't manage to start
	carp "Server can't start on $location";
	return undef;
    }  
    # Removes the generated perl program for server
    return { ServerPort => $port,
	     ServerLocation => $location
	     } ;
}

#########################
# CLIENT-SIDE FUNCTIONS #
#########################

# Do a transaction with the server
sub call_server ($@) {
    my ($server, @rest) = @_;

    my $remote = $server->{ServerLocation};
    my $port = $server->{ServerPort};
    print STDERR "Connecting to server on $remote, port $port\n" if $DEBUG2;
    my ($iaddr, $paddr, $proto, $line);
    $iaddr = inet_aton($remote);
    $paddr = sockaddr_in($port, $iaddr);
    $proto = getprotobyname('tcp');
    my $attempt = 0;
RETRY :
    print STDERR "try to connect on $remote\n" if $DEBUG2;
    my $sockhandle = new FileHandle;
    socket ($sockhandle, PF_INET, SOCK_STREAM, $proto) or die "socket: $!";
    connect($sockhandle, $paddr) or (close $sockhandle ,sleep 1, $attempt++ ,
				     $attempt < $MAX_CALL_ATTEMPTS ? goto RETRY : die "connect: $!");
    #server may be shutdown if there is no answer after 4 attempts
    print STDERR "Connection accepted (from $remote,$port)\n" if $DEBUG2;
    $sockhandle->autoflush();
    # Do the actual communication
    _send_data($sockhandle, \@rest);
    my $resp_ref = _get_data($sockhandle);
    my @resp = (undef);
    @resp = @$resp_ref if $resp_ref;
    # Close socket
    close $sockhandle;
    return @resp;
}   

#################################
1; # Final true ending for module
__END__
# Below is the stub of documentation for your module. You better edit it!

=head1 NAME

MOP::Remote - Perl meta-module for transparent distribution of object oriented modules.

=head1 SYNOPSIS

    # A random package declaration
    package MyModule;

    # Activate the meta-object protocol for a few methods
    use MOP::MOP qw(new method1 method3);
    # Our meta-module is 'MOP::Remote'
    MOP::MOP::register_meta('MOP::Remote','MyModule');

    # Some functions
    sub new { return bless { ... }; } # Constructor
    sub method1 { ... }
    sub method2 { ... }
    sub method3 { ... }

    ##### NOW USING MyModule ####
    use MyModule;
    
    # Creates a remote server
    my $REMOTE = 'host.name.fr'; my $PORT = 1234;
    my $server = MOP::Remote::create_server('MyModule', $REMOTE, $PORT);

    # Creates an object - additional argument is grabbed by meta-module
    my $o = MyModule->new(..., $server);
    # Now, simply use it: all methods are done remotely on $REMOTE_HOST
    $o->method1();
    my $var = $o->method3('a_value');
    ...

=head1 DESCRIPTION

This module provides two things:

=over 4

=item

An example of basic meta-module that demonstrates how it is possible
to design a meta-module, and use it to provide useful functionality
to third-party module writers.

=item

A transparent way of adding remote processing capabilities to any
module with minimal modifications. This will probably work only on
Unix systems.

=back

Using this module should be straightforward. In the definition
of an object-oriented Perl module that you want to enhance by remote
processing capabilities, you simply need to state that several methods
should be reflective, with: C<use MOP::MOP qw(method_name1 method_name2 ...)>.
This simply makes the MOP (Meta-Object Protocol) aware of the given methods.
Then, you should probably define a static link between your module and the
MOP::Remote meta-module with: C<MOP::MOP::register_meta('MOP::Remote','MyModule')>,
at the beginning of F<MyModule.pm>.
This magic formula indicates to the MOP that MOP::Remote is the meta-module
to be used for MyModule. It is this meta-module that provides the magical
remote processing capability.

Then, the user of MyModule creates a new server via the
create_server() function of MOP::Remote, in order to create new
objects on that server. All method calls on such an object will be
performed on the remote server.
If the user wants to create a local object (in-process), he simply passes
the constant LOCAL instead of a server reference, as in:
C<MyModule-E<gt>new(..., 'LOCAL')>. This creates an object normally.
But then, there is nothing funny anymore.

=head2 Detailed operation

At creation via C<MyModule-E<gt>new(...,$server)>, the call will be
trapped and redirected to the host associated with the given server.
The $server argument will be removed before calling the new() method
on the server, of course.
The remote server will create a new object, and the local machine will
simply return you an empty hashref that plays the role of a proxy.
In fact, two additional meta-objects will be created: one locally that
will hold some useful information (such as the remote object ID) and
will control the future method calls made on the proxy, and one meta-object
on the remote server that will perform the real base-level method call
on the real (remote) object.

Afterwards, all method calls made on objects from MyModule will be trapped by the MOP
and redirected to MOP::Remote. The (local) meta-object created after the call
to new() will be used to find the remote processing server, and the
call with all its arguments will be redirected to that server. On the remote
host, the server will catch this request, perform the operation on the
real object (via its own meta-object) and communicate the results
back to your process. The returned value will be sent back to you.
Data::Dumper is used (in deep mode) to pass the arguments back and forth.
So, it is possible that some references be lost during the network exchange,
depending on the base module operation.

The remote invocation is a blocking one. If you want to perform multiple
concurrent remote invocations, you should handle that yourself.

Currently, you should consider MOP::Remote as a form of RPC.
It is also preferred to create different remote servers for different modules
(ie: one for each class).
You can create several objects on one server, and you may also create them
from different client machines. However, note that one remote server
serializes the method calls (it does not do any fork()) and that you
will need to find a way to exchange the server reference. This is not exactly
the normal way of operation.

=head2 Functions

=over 4

=item C<$server = MOP::Remote::create_server($module_name[,$host,$port,$remote_perl])>

This function creates a new server on a remote machine. $module_name should contain
the name of the module that is operated by the server. B<rsh> is used to create
a Perl process on the remote machine, so you need to have B<rsh> and an account
on the remote machine (that does not require a password).
The remaining arguments are optional. $host is the name of a remote host on
which you want to create the server. It defaults to 'localhost', ie: the local host
(in another Perl process in fact - this is a behavior of B<rsh>). However,
you will probably want to specify this one.
$port is the TCP port number used for the communication between the client and the server.
It default to 2345 (an arbitrary value). You should adapt that to your application.
Finally, $remote_perl may indicate the name of the Perl executable to use on the
remote machine. MOP::Remote tries to be smart and to guess that name,
so usually you need not specify it. But in cross-platform configurations, it
may be useful to be able to specify it. (I<Hint>: if you configured your shell
initializations correcty so that the simple command B<perl> works on the remote
host, MOP::Remote will surely find the name of a good Perl executable.)

This function will return you a hash reference that contains server-related
information. You may use that hashref to create objects on the server via
new().

=item  C<MOP::Remote::exit_server($server)>

This function will send an exit message to the remote server that will
handshake and exit.

=head2 Notes

MOP::Remote I<closes> C<STDOUT> and C<STDERR> on the remote
server by default.
It may be difficult to debug your module (that executes remotely).
You can set the debug flag C<$MOP::Remote::DEBUG>. In that case,
MOP::Remote will not close ouputs and will arrange to maintain
a link between the standard outputs of remote processes and the local
terminal. You can also set C<$MOP::Remote::DEBUG2> if you want to see
the messages exchanged between the client and the server.

I have successfully tested remote invocations between Solaris and
Linux hosts.
However, cross-platform invocation, even though possible, still involves
careful setup of both platforms Perl5 modules library.
(The same modules should be available on both hosts.
Versions should be similar.
Previous note is really applicable.)

MOP::Remote depends on Data::Dumper.

=head1 LIMITATIONS AND FUTURE EVOLUTIONS

The client-server functionality implemented inside MOP::Remote is
self-contained but rather basic. It would be desirable to use a more
sophisticated set of functionalities for client-server operation (like
in EventServer).
Only the true meta-level part of MOP::Remote should remain in that
case.

As any magical device, MOP::Remote surely has a lot of shortcomings.
In fact, it is not sure at all that a MOP::Remote-enhanced
module will behave exactly like a normal module. For example,
the inheritance semantics of a reflective module is not (yet)
clear. If something inherits from MyModule, but overloads some
methods, the remote processing capability may be broken for these
methods.

Furthermore, if some public methods are not reflective, the MOP
does not know them, so they will not be trapped to be sent to
the remote server. Instead they will be executed locally
by Perl itself: at once I<on a proxy object>. So the result will surely
be some bad thing. Private method calls need not be reflective,
because the user should never call them (or they would not be
private), but well... nothing really prevents them from doing so
especially when inheritance is involved.

Finally, there may be meta-meta-objects on any side of the client-server
communication, and at this point, my brain usually stops understanding the
real path of the method call. Maybe Perl will figure out what to do...
(Remember this is just an example.)

=head1 BUGS

Due to a limitation of the meta-object protocol of MOP::MOP, the
destruction of objects is not handled. If you create a lot of objects
on the remote server and do not use them, it may be a (remote) problem.

new() is the only class method name considered. If your module
has other constructors that should execute remotely, you should modify
the meta-module. Currently MOP::Remote will complain, but
it will perform the class method call locally anyway.

The default TCP port number used for communication is arbitrary: 
it is 2345.

=head1 AUTHOR

Rodolphe Ortalo, ortalo@laas.fr

=head2 Acknowledgements

This work has been performed with the support of LAAS-CNRS.

=head1 SEE ALSO

perl(1), MOP::MOP(3), MOP::MetaModule(3).

=cut
