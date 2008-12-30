package Net::Appliance::Session;

use strict;
use warnings FATAL => 'all';

use base qw(
    Net::Appliance::Session::Transport
    Net::Appliance::Session::Engine
    Net::Telnet
    Class::Accessor::Fast::Contained
    Class::Data::Inheritable
); # eventually, would Moosify this ?

our $VERSION = '1.34';
$VERSION = eval $VERSION; # numify for warning-free dev releases

use Net::Appliance::Session::Exceptions;
use Net::Appliance::Session::Util;
use Net::Appliance::Phrasebook 1.2;
use UNIVERSAL::require;
use Carp;

__PACKAGE__->mk_ro_accessors('pb');
__PACKAGE__->mk_accessors(qw(
    logged_in
    in_privileged_mode
    in_configure_mode
    do_paging
    do_login
    do_privileged_mode
    do_configure_mode
    check_pb
    childpid
    fail_with_repl
    last_command_sent
));
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_accessors(qw(
    username
    password
    pager_disable_lines
    pager_enable_lines
));

__PACKAGE__->mk_classdata(
    basic_phrases => [qw/
        prompt
        basic_prompt
        user_prompt
        pass_prompt
        userpass_prompt
        err_string
    /]
);

# ===========================================================================

sub new {
    my $class = shift @_;
    my %args;

    # interpret params into hash so we can augment safely
    if (scalar @_ == 1) {
        $args{host} = shift @_;
    }
    elsif (! scalar @_ % 2) {
        %args = _normalize(@_);
    }
    else {
        raise_error "Error: odd number of paramters supplied to new()";
    }

    # our primary base is Net::Telnet, and it's quite sensitive to
    # unrecognized args, so take them out. this also prevents auto-connect

    my $tprt = exists $args{transport} ? delete $args{transport} : 'SSH';
    my $host = exists $args{host}      ? delete $args{host}      : undef;
    my $chpb = exists $args{checkpb}   ? delete $args{checkpb}   : 1;
    my $repl = exists $args{repl}      ? delete $args{repl}      : 0;

    my %pbargs = (); # arguments to Net::Appliance::Phrasebook->load
    $pbargs{platform} =
        exists $args{platform} ? delete $args{platform} : 'IOS';
    $pbargs{source} = delete $args{source} if exists $args{source};

    # load up the transport, which is a wrapper for Net::Telnet

    my $transport = 'Net::Appliance::Session::Transport::' . $tprt;
    $transport->require or
        raise_error "Couldn't load transport '$transport' (maybe you forgot to install it?)";

    my $self = $transport->new( %args );
    bless ($self, $class);  # reconsecrate into __PACKAGE__
    unshift @Net::Appliance::Session::ISA, $transport;

    # a bit of a double-backflip, but that's what you get for using MI :-}
    $self = $self->Class::Accessor::Fast::Contained::setup({
        pb => Net::Appliance::Phrasebook->load( %pbargs )
    });

    # $self will now respond to Net::Telnet methods, and ->pb->fetch()
    $self->check_pb($chpb);

    # (optionally) check all necessary words are in our loaded phrasebook
    if ($self->check_pb) {
        my %k_available = map {$_ => 1} $self->pb->keywords;
        foreach my $k (@{ __PACKAGE__->basic_phrases }) {
            $k_available{$k} or
                raise_error "Definition of '$k' missing from phrasebook!";
        }
    }

    # restore the Host argument
    $self->host( $host ) if defined $host;

    # set Net::Telnet prompt from platform's phrasebook
    $self->prompt( $self->pb->fetch('prompt') );

    # set failure mode
    $self->fail_with_repl($repl);

    # set some operation defaults
    $self->set_pager_disable_lines(0);
    $self->set_pager_enable_lines(24);
    $self->do_paging(1);
    $self->do_login(1);
    $self->do_privileged_mode(1);
    $self->do_configure_mode(1);
    $self->last_command_sent('');

    return $self;
}

# need to override Net::Telnet::close to make sure we back out
# of any nested modes correctly
sub close {
    my $self = shift;

    my $caller = ( caller(1) )[3];

    # close() is called from other things like fhopen, so we only want
    # to act on real closes -- a bit hacky really
    if ((! defined $caller) or ($caller !~ m/fhopen/)) {
        $self->end_configure
            if $self->do_configure_mode and $self->in_configure_mode;
        $self->end_privileged
            if $self->do_privileged_mode and $self->in_privileged_mode;

        # re-enable paging
        $self->enable_paging if $self->do_paging;

        # transport-specific work
        $self->disconnect;
    }

    $self->SUPER::close(@_);
}

# cygwin perl does not reap for some reason, so one solution
# for now is to kill the child if it's still around when we are GC'd
sub DESTROY {
    my $self = shift;

    # only applies to cygwin
    return if $^O !~ m/win/i;

    if (defined $self->childpid
        and $self->childpid > 0
        and (kill 0, $self->childpid) > 0) {

        # print "SIGKILL to process ID ", $self->childpid, "\n";
        kill 9, $self->childpid;
    }
}

# need to override Net::Telnet::fhopen because it would obliterate our
# private attributes otherwise.
sub fhopen {
    my ($self, $fh) = @_;
    
    ## Save our private data.
    my $s = *$self->{ref $self};

    my $r = $self->SUPER::fhopen($fh); # does not return $self

    ## Restore our private data.
    *$self->{ref $self} = $s;

    return $r;
}

# override Net::Telnet::error(), which is a little tricky...
# Normally error() is kind of polymorphic, changing depending on the state of
# the Errmode parameter, and we still want that to be the case. However
# locally we want ->error to work because it's more straighforward, so we'll
# just filter for calls from our own namespace versus everything else.
sub error {
    my $self = shift;

    return $self->SUPER::error(@_) if scalar caller !~ m/^Net::Appliance::Session/;

    my $e =  Net::Appliance::Session::Exception->new(
        message  => join (', ', @_). Carp::shortmess,
        errmsg   => $self->errmsg,
        lastline => $self->lastline,
    );

    if ($self->fail_with_repl) {
        # don't use REPL, even if asked, if we're not interactive
        eval {
            require IO::Interactive;
            $e->throw if ! IO::Interactive::is_interactive();
        };

        # start up a REPL shell
        eval {
            require Devel::REPL;
            my $repl = Devel::REPL->new;
            $repl->load_plugin('NAS');

            ${ $repl->lexical_environment->get_member_ref('$', '_', '$s') }
                = $self;
            $repl->nas_cli_mode(1);
            $repl->nas_command_cache($self->last_command_sent);
            $repl->print( $repl->format_error($e) );
            $repl->run;
        };
    }

    $e->throw if $@ or !$self->fail_with_repl;

    return $self; # but hopefully not, because we died or started a REPL
}

# override Net::Telnet::cmd() to check responses against error strings in
# phrasebook for each platform. also check for response sanity to save client
# effort.
sub cmd {
    my $self = shift;

    my (%args, @nt_args, $string, $output);
    if (scalar @_ == 1) {
        @nt_args = ();
        $string = shift @_;
    }
    else {
        %args = _normalize(@_);
        ($string, $output) = @args{'string', 'output'};

        push @nt_args, ('Timeout', $args{timeout}) if exists $args{timeout};
        push @nt_args, (map {( Match => $_ )} @{$args{match}})
            if exists $args{match};
    }

    $self->last_command_sent($string); # to pass to error handler
    my $completion = ($string =~ s/\?$//); # command line completion?

    $self->put($string . ($completion ? $self->pb->fetch('completion') : "\n"))
        or $self->error('Incomplete command write: only '.
                        $self->print_length .' bytes have been sent');

    my $prompt = $self->prompt;
    $prompt =~ s/\$/\\s*$string\$/ if $completion;
    my @retvals = $self->waitfor( Match => $prompt, @nt_args );

    $self->error('Timeout, EOF or other failure waiting for command response')
        if scalar @retvals == 0; # empty list

    $self->error('Command response matched device error string')
        if $retvals[0] =~ eval 'qr'. $self->pb->fetch('err_string');

    # Save the most recently matched prompt.
    $self->last_prompt($retvals[1]);

    # Reset the cli input (ctrl-u), for a new command.
    $self->put( chr(21) );

    my @output;
    my $irs = $self->input_record_separator || "\n";

    if ($retvals[0] =~ m/^(?:$irs)*$/) {
        # no output, so according to Net::Telnet docs do this...
        @output = ('');
    }
    else {
        @output = map { $_ . $irs } split m/$irs/, $retvals[0];
        @output = splice @output, $self->cmd_remove_mode;
    }

    if (ref $output) {
        if (ref $output eq 'SCALAR') {
            $$output = join '', @output;
        }
        else {
            @$output = @output;
        }
    }

    return @output if wantarray;
    return $self;
}

# ===========================================================================

1;

=head1 NAME

Net::Appliance::Session - Run command-line sessions to network appliances

=head1 VERSION

This document refers to version 1.34 of Net::Appliance::Session.

=head1 SYNOPSIS

 use Net::Appliance::Session;
 my $s = Net::Appliance::Session->new('hostname.example');

 eval {
     $s->connect(Name => 'username', Password => 'loginpass');
     $s->begin_privileged('privilegedpass');
     print $s->cmd('show access-list');
     $s->end_privileged;
 };
 if ($@) {
     $e = Exception::Class->caught();
     ref $e ? $e->rethrow : die $e;
 }

 $s->close;

=head1 DESCRIPTION

Use this module to establish an interactive command-line session with a
network appliance. There is special support for moving into C<privileged>
mode and C<configure> mode, with all other commands being sent through a
generic call to your session object.

There are other CPAN modules that cover similar ground, including Net::SSH and
Net::Telnet::Cisco, but they are less robust or do not handle SSH properly.
Objects created by this module are based upon Net::Telnet so the majority of
your interaction will be with methods in that module. It is recommended that
you read the Net::Telnet manual page for further details.

This module natively supports connections via SSH, Telnet and a Serial Port.
All commands can be overridden from the built-in Cisco defaults in order to
support other target devices; the connection process (user log-in) is
similarly configurable.

=head1 METHODS

Objects created by this module are based upon Net::Telnet so the majority of
your interaction will be with methods in that module.

=head2 C<< Net::Appliance::Session->new >>

Like Net::Telnet you can supply either a single parameter to this method which
is used for the target device hostname, or a list of named parameters as
listed in the Net::Telnet documentation. Do not use C<Net::Telnet>'s
C<Errmode> parameter, because it will be overridden by this module.

The significant difference with this module is that the actual connection to
the remote device is delayed until you C<connect()>.

Named Parameters, passed as a hash to this constructor, are optional. Some are
described in L</"TRANSPORTS">, L</"DIAGNOSTICS">, and L</"CONFIGURATION">
below. Any others are passed directly to L<Net::Telnet> (which dies on unknown
parameters).

This method returns a new C<Net::Appliance::Session> object.

=head2 C<connect>

When you instantiate a new Net::Appliance::Session object the module does not
actually establish a connection with the target device. This behaviour is
slightly different to Net::Telnet and is because the Transport may need to
have login credentials before a connection is made (e.g. in the case of SSH).
Use this method to establish that interactive session.

Parameters to this method are determined by the Transport (SSH, Telnet, etc)
that you are running. See the L<Net::Appliance::Session::Transport> manual
page for further details.

In addition to logging in, C<connect> will also disable paging in the
output for its interactive session. This means that unlike Net::Telnet::Cisco
no special page scraping logic is required in this module's code. This feature
can be disabled (see L</"CONFIGURATION">, below).

=head2 C<begin_privileged>

To enter privileged mode on the device use this method. Of course you must be
connected to the device using the C<connect> method, first.

All parameters are optional, and if none are given then the login password
will be used as the privileged password.

If one parameter is given then it is assumed to be the privileged password.

If two parameters are given then they are assumed to be the privileged
username and password, respectively.

If more than two parameters are given then they are interepreted as a list of
named parameters using the key names C<Name> and C<Password> for the
privileged username and password, respectively.

=head2 C<end_privileged>

To leave privileged mode and return to the unpriviledged shell then use this
method.

=head2 C<in_privileged_mode>

This method will return True if your interactive session is currently in
privileged (or configure) mode, and False if it is not.

Also, you can pass a True or False value to this method to "trick" the module
and alter its behaviour. This is useful for performing secondary logins (see
CPAN Forum).

=head2 C<begin_configure>

In order to enter configure mode, you must first have entered privileged mode,
using the C<begin_privileged> method described above.

To enter configure mode on the device use this method.

=head2 C<end_configure>

To leave configure mode and return to privileged mode the use this method.

=head2 C<in_configure_mode>

This method will return True if your interactive session is currently in
configure mode, and False if it is not.

Also, you can pass a True or False value to this method to "trick" the module
and alter its behaviour (see CPAN Forum).

=head2 C<cmd>

Ordinarily, you might use this C<Net::Telnet> method in scalar context to
observe whether the command was successful on the target appliance. However,
this module's version C<die>s if it doesn't think everything went well. See
L</"DIAGNOSTICS"> for tips on managing this using an C<eval{}> construct.

The following error conditions are checked on your behalf:

=over 4

=item *

Incomplete command output, it was cut short for some reason

=item *

Timeout waiting for command response

=item *

EOF or other anomaly received in the command response

=item *

Error message from your appliance in the response

=back

If any of these occurs then you will get an exception with appropriately
populated fields. Otherwise, in array context this method returns the command
response, just as C<Net::Telnet> would. In scalar context the object itself
returned.

The only usable method arguments are C<String>, C<Output> and C<Timeout>, plus
as a special case, C<Match>. The C<Match> named argument takes in an I<array
reference> a list of one or more strings representing valid Perl pattern match
operators (e.g. C</foo/>). Therefore, the C<cmd()> method can check against
the default command prompt, built-in error strings, and also a custom response
of your choice at the same time.

Being overridden in this way means you should have less need for the
C<print()> and C<waitfor()> methods of C<Net::Telnet>, although they are of
course still available should you want them.

=head2 C<close>

This C<Net::Telnet> method has been overridden to automatically back
out of configure and/or privilege mode, as well as re-enable paging mode on
your behalf, as necessary.

=head2 C<error>

Rather than following the C<Net::Telnet> documentation, this method now
creates and throws an exception, setting the field values for you. See
L</"DIAGNOSTICS"> below for more information, however under most circumstances
it will be called automatically for you by the overridden C<cmd()> method.

=head1 TRANSPORTS

This module supports interactive connections to devices over SSH, Telnet and
via a Serial Port. The default is to use SSH, so to select an alternative,
pass an optional C<Transport> parameter to the C<new()> constructor:

 my $s = Net::Appliance::Session->new(
     Host      => 'hostname.example',
     Transport => 'Serial',
 );

Whatever transport you are using, it is highly recommended that you read the
relevant manual page. The L<Net::Appliance::Session::Transport> manual is a
good starting place.

=head1 CONFIGURATION

=head2 Log-in

In the default case, which is SSH to a Cisco IOS device, both a Username and
Password are required and a full log-in is made (i.e. the device presents a
Password prompt, and so on).

However, some devices require no login. Examples of this might be a Public
Route Server, or a device connected via a Serial Port. In that situation, use
the following object method I<before> calling C<connect()>:

=head3 C<do_login>

Passing any False value to this method prevents C<connect()> from expecting to
have to negotiate a log-in to the device. Most Transports in that case do not
require the Password parameter, although a Username might still be required.
By default log-in negotiation is enabled.

=head2 Paging

In the default case, Net::Appliance::Session expects that command output
paging is enabled on the device. This is where response to commands is
"paged", having only (e.g.) 24 lines printed at a time, and you press the
Enter or Space key to see more.

With automated interaction this is useless, and error-prone, so
Net::Appliance::Session by default will send a command to disable paging
straight after it connects, and re-enable it as part of C<close()>.

To override the pager management command itself, you will need to edit the
phrasebook (see below). The following object methods alter other aspects of
pager management:

=head3 C<do_paging>

Passing any False value to this method prevents C<connect()> and C<close()>
from respectively disabling and re-enabling paging on the device. By default
paging management is enabled.

=head3 C<enable_paging> and C<disable_paging>

If you have an installation which requires manual issueing of paging
commands to the device, then call these methods to take that action. Note that
C<do_paging> must have been passed a True value otherwise these methods will
short-circuit thinking you don't want paging.

In other words, to page manually, set C<do_paging> to False at the start of
your session, before connecting, and then set it to True as you call either of
these methods. This dancing around will probably be fixed in a forthcoming
release of Net::Appliance::Session.

=head3 C<set_pager_disable_lines>

Net::Appliance::Session assumes that the command to disable the pager just
re-sets the number of paging lines. Pass this method a new value for that
number, which has a default of zero in the module.

=head3 C<set_pager_enable_lines>

Likewise, to re-enable paging Net::Appliance::Session will call the pager
management command with a value for the number of output lines per page. Pass
this method a value to override the default of 24.

=head2 Command mode

If your target device does not have the concept of "privileged exec" or
"configure" mode, then just don't call the methods to change into those modes.

However, there is a catch. If your device separates only configure mode, then
when you try to call C<begin_configure()> straight after a log-in, the module
will complain, because it thinks you need to ask for a C<begin_privileged>
first.  Also, when disconnecting, Net::Appliance::Session will attempt to step
out of privileged and configure modes, so if they don't apply you will want to
disable those steps.

To alter all this behaviour, use the following object methods.

If you are trying to subvert this module to just automate interaction with a
CLI via SSH, Telnet or Serial Line on a strange kind of device, then these
methods will be useful (as well as C<do_paging>, above).

=head3 C<do_privileged_mode>

If you pass a False value to this method, then Net::Appliance::Session will
believe you are in some kind of privileged mode as soon as you log in. The net
effect is that you can now safely call C<begin_configure()>. The default is to
actively gatekeep access to privileged mode.

=head3 C<do_configure_mode>

By passing a False value to this method you also make Net::Appliance::Session
believe you are in configure mode straight after entering privileged mode (or
after log in if C<do_privileged_mode> is also False). The default is to
actively gatekeep access to configure mode.

=head2 Commands and Prompts

Various models of network device, either from one vendor such as Cisco or
between vendors, will naturally use alternate command and command prompt
syntax. Net::Appliance::Session does not hard-code any of these commands or
pattern matches in its source. They are all loaded at run-time from an
external phrasebook (a.k.a. dictionary), which you may of course override.

The default operation of Net::Appliance::Session is to assume that the target
is running a form of Cisco's IOS, so if this is the case you should not need
to modify any settings.

Support is also available, via the C<< Net::Appliance::Phrasebook >> module,
for the following operating systems:

 IOS     # the default
  
 Aironet # currently the same as the default
 CATOS   # for older, pre-IOS Cisco devices
 PIXOS   # for PIX OS-based devices
 PIXOS7  # Slightly different commands from other PIXOS versions
 FWSM    # currently the same as 'PIXOS'
 FWSM3   # for FWSM Release 3.x devices (slightly different to FWSM 2.x)
  
 JUNOS   # Juniper JUNOS support
 HP      # Basic HP support
 Nortel  # Basic Nortel support

To select a phrasebook, pass an optional C<Platform> parameter to the C<new>
method like so:

 my $s = Net::Appliance::Session->new(
     Host     => 'hostname.example',
     Platform => 'FWSM3',
 );

If you want to add a new phrasebook, or override an existing one, there are
two options. Either submit a patch to the maintaner of the C<<
Net::Appliance::Phrasebook >> module, or read the manual page for that module
to find out how to use a local phrasebook rather than the builtin one via the
C<Source> parameter (which is accepted by this module and passed on verbatim).

 my $s = Net::Appliance::Session->new(
     Host     => 'hostname.example',
     Source   => '/path/to/file.yml',
     Platform => 'MYDEVICE',
 );

In this way, you can fix bugs in the standard command set, adjust them for
your own devices, or "port" this module onto a completely different appliance
platform (that happens to provide an SSH, Telnet or Serial Port CLI).

Some sanity checking takes place at certain points to make sure the phrasebook
contains necessary phrases. If overriding the phrasebook, you'll need to
provide at least the C<basic_phrases> as set in this module's source code. If
using Privileged and Configure mode, there are C<privileged_phrases> and
C<configure_phrases> that will be required, also. Paging requires a
C<pager_cmd> phrase to be available. See the source code of
L<Net::Appliance::Phrasebook> for examples.

If you fancy yourself as a bit of a cowboy, then there is an option to
C<new()> that disables this checking of phrasebook entries:

 my $s = Net::Appliance::Session->new(
     Host     => 'hostname.example',
     Platform => 'MYDEVICE',
     Source   => '/path/to/file.yml', # override phrasebook completely
     CheckPB  => 0, # squash errors about missing phrasebook entries
 );

You better have read the source and checked what phrases you need before
disabling C<CheckPB>. Don't say I didn't warn you.

=head1 DIAGNOSTICS

Firstly, if you want to see a copy of everything sent to and received from the
appliance, then something like the following will probably do what you want:

 $s->input_log(*STDOUT);

All errors returned from Net::Appliance::Session methods are Perl exceptions,
meaning that in effect C<die()> is called and you will need to use C<<
eval {} >>. The rationale behind this is that you should have taken care to
script interactive sessions robustly, and tested them thoroughly, so if a
prompt is not returned or you supply incorrect parameters then it's an
exceptional error.

Recommended practice is to wrap your interactive session in an eval block like
so:

 eval {
     $s->begin_privileged('password');
     print $s->cmd('show version');
     # and so on...
 };
 if ( UNIVERSAL::isa($@,'Net::Appliance::Session::Exception') ) {
     print $@->message, "\n";  # fault description from Net::Appliance::Session
     print $@->errmsg, "\n";   # message from Net::Telnet
     print $@->lastline, "\n"; # last line of output from your appliance
     # perform any other cleanup as necessary
 }
 $s->close;

Exceptions belong to the C<Net::Appliance::Session::Exception> class if
they result from errors internal to Net::Telnet such as lack of returned
prompts, command timeouts, and so on.

Alternatively exceptions will belong to C<Net::Appliance::Session::Error>
if you have been silly (for example missed a method parameter or tried to
enter configure mode without having first entered privileged mode).

All exception objects are created from C<Exception::Class> and so
stringify correctly and support methods as described in the manual page for
that module.

C<Net::Appliance::Session::Exception> exception objects have two
additional methods (a.k.a. fields), C<errmsg> and C<lastline> which
contain output from Net::Telnet diagnostics.

=head2 Using a C<Devel::REPL> shell

This module supports an additional mode of failure which can be useful when
debugging C<Net::Appliance::Session> scripts. Instead of having an exception
thrown as described above, you can be dropped into an interactive shell at the
connected device, if possible, instead.

A L<Devel::REPL> shell is used, which means you also have the bonus of a full
Perl environment from which you can execute Perl code, test network device
commands, and save and load data from disk. Further information on how to use
the shell and its features is given in the L<Devel::REPL::Plugin::NAS> manual
page.

As well as installing the C<Devel::REPL> and C<Devel::REPL::Plugin::NAS>
modules, you'll need to change the call to C<new()> for this module, like so:

 my $s = Net::Appliance::Session->new(
     Host => 'hostname.example',
     REPL => 1,
 );

=head1 INTERNALS

The guts of this module are pretty tricky, although I would also hope elegant,
in parts ;-) In particular, the following C<Net::Telnet> method has been
overridden to modify behaviour:

=head2 C<fhopen>

The killer feature in C<Net::Telnet> is that it allows you to swap out the
builtin I/O target from a standard TELNET connection, to another filehandle of
your choice. However, it does so in a rather intrusive way to the poor object,
so this method is overridden to safeguard our instance's private data.

=head1 DEPENDENCIES

Other than the contents of the standard Perl distribution, you will need the
following:

=over 4

=item *

L<Exception::Class>

=item *

L<Net::Telnet>

=item *

L<IO::Pty>

=item *

L<UNIVERSAL::require>

=item *

L<Class::Accessor> >= 0.25

=item *

L<Class::Accessor::Fast::Contained>

=item *

L<Net::Appliance::Phrasebook> >= 1.2

=back

You can also make use of certain features by installing the following optional
modules:

=over 4

=item *

L<Devel::REPL::Plugin::NAS>

=item *

L<Devel::REPL>

=item *

L<IO::Interactive>

=back

=head1 AUTHOR

Oliver Gorwits C<< <oliver.gorwits@oucs.ox.ac.uk> >>

=head1 ACKNOWLEDGEMENTS

Parts of this module are based on the work of Robin Stevens and Roger Treweek.
The command spawning code was based on that in C<Expect.pm> and is copyright
Roland Giersig and/or Austin Schutz.

=head1 COPYRIGHT & LICENSE

Copyright (c) The University of Oxford 2008.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
