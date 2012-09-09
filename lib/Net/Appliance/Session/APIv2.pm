package Net::Appliance::Session::APIv2;
{
  $Net::Appliance::Session::APIv2::VERSION = '3.122530';
}

use Moose;
extends 'Net::Appliance::Session';

sub BUILDARGS {
    my ($class, @params) = @_;
    my $args = {};
    
    if (scalar @params == 1 and ref $params[0] eq ref {}) {
        die "you are using Net::Appliance::Session v3 API style but loaded v2!";
    }

    if (scalar @params == 1 and ref $params[0] eq ref '') {
        return {
            host => $params[0],
            personality => 'ios',
            transport => 'SSH',
        };
    }

    my $param_hash = { @params };
    if (exists $param_hash->{Source}) {
        die '"Source" param to new() is no longer supported. Please convert '
            .'your phrasebook to the Net::CLI::Interact format';
    }

    my $map = {
        Host => 'host',
        Platform => 'personality',
        Transport => 'transport',
    };

    foreach my $k (keys %$map) {
        $args->{ $map->{$k} } = $param_hash->{$k}
            if exists $param_hash->{$k};
    }

    $args->{connect_options} = {
        map {lc $_ => $param_hash->{$_}} keys %$param_hash
    };

    return $args;
}

# intercept a call to connect() and set all options we can support
# then allow the call to procede.
sub connect {
    my ($self, @params) = @_;

    if (scalar @params == 1 and ref $params[0] eq ref {}) {
        die "you are using Net::Appliance::Session v3 API style but loaded v2!";
    }

    my $param_hash = { @params };
    my $map = {
        # all transports
        Name => sub { (shift)->set_username(shift) },
        Password => sub { (shift)->set_password(shift) },
        App  => sub { (shift)->nci->transport->app(shift) },
        Timeout => sub { (shift)->nci->transport->timeout(shift) },
        # SSH Transport
        SHKC => sub { (shift)->nci->transport->connect_options->shkc(shift) },
        Opts => sub { (shift)->nci->transport->connect_options->opts(shift) },
        # Serial Transport
        Line => sub { (shift)->nci->transport->connect_options->device(shift) },
        Parity => sub { (shift)->nci->transport->connect_options->parity(shift) },
        Nostop => sub { (shift)->nci->transport->connect_options->nostop(shift) },
        Speed => sub { (shift)->nci->transport->connect_options->speed(shift) },
    };

    foreach my $k (keys %$param_hash) {
        next unless exists $map->{$k};
        $map->{$k}->($self, $param_hash->{$k});
    }

    return $self->_wrap( sub { $self->SUPER::connect(@params) } );
}

# run a command on the remote device using old v2 API arguments
sub cmd {
    my ($self, @params) = @_;

    # to be fair, could be APIv3 but we can't tell
    # and there are internal calls to cmd() which must be passed through
    if (scalar @params == 1
        or (scalar @params == 2 and ref $params[1] eq ref {})) {
        return $self->_wrap( sub { $self->SUPER::cmd(@params) } );
    }

    my $param_hash = { @params };
    my $cmd = $param_hash->{String};
    $self->nci->transport->timeout($param_hash->{Timeout})
        if exists $param_hash->{Timeout};

    my @output = ();
    if (exists $param_hash->{Match}) {
        my $match = (map {eval "qr$param_hash->{Match}"}
                         @{ $param_hash->{Match} });
        @output = $self->_wrap( sub {
            $self->SUPER::cmd->($cmd, { match => $match }) } );
    }
    else {
        @output = $self->_wrap( sub { $self->SUPER::cmd->($cmd) } );
    }

    if (exists $param_hash->{Output} and ref $param_hash->{Output}) {
        if (ref $param_hash->{Output} eq ref \'') {
            ${$param_hash->{Output}} = join '', @output;
        }
        else {
            $param_hash->{Output} = \@output;
        }
    }

    return @output;
}

sub begin_privileged {
    my ($self, @params) = @_;
    
    if (scalar @params == 1 and ref $params[0] eq ref {}) {
        die "you are using Net::Appliance::Session v3 API style but loaded v2!";
    }

    if (scalar @params == 1) {
        return $self->_wrap( sub { $self->SUPER::begin_privileged({
            password => $params[0],
        }) } );
    }
    elsif (scalar @params == 2) {
        return $self->_wrap( sub { $self->SUPER::begin_privileged({
            username => $params[0],
            password => $params[1],
        }) } );
    }
    elsif (scalar @params >= 4) {
        my $param_hash = { @params };
        return $self->_wrap( sub { $self->SUPER::begin_privileged({
            username => $param_hash->{Username},
            password => $param_hash->{Password},
        }) } );
    }
    # and that's why this API was dumped by the roadside.

    return $self->_wrap( sub { $self->SUPER::begin_privileged() } );
}

sub error {
    my $self = shift;
    $self->_wrap( sub { die "the error() method is no longer available to call" } );
}

sub input_log {
    my $self = shift;
    $self->_wrap( sub { $self->set_global_log_at('notice') } );
}

# call some perl code which might die, so catch that and create a kind-of
# exception object which is thrown instead.
sub _wrap {
    my ($self, $sub, @args) = @_;

    my ($ret, @ret);
    if (wantarray) {
        @ret = eval { $sub->(@args) };
    }
    else {
        $ret = eval { $sub->(@args) };
    }

    {
        # this simulates the Exception::Class exceptions used in
        # Net::Appliance::Session as best we can.

        package # hide from pause
            Net::Appliance::Session::Exception;
        use Moose;
        use overload '""' => '_error_str';

        sub _error_str {
            my $self = shift;
            return $self->message .', '. $self->errmsg .' '. $self->lastline;
        };

        has 'message'  => ( is => 'ro', isa => 'Str', required => 1 );
        has 'errmsg'   => ( is => 'ro', isa => 'Str', required => 1 );
        has 'lastline' => ( is => 'ro', isa => 'Str', required => 1 );
    }

    if ($@) {
        my $e = Net::Appliance::Session::Exception->new(
            message => $@,
            errmsg => 'version 3 of Net::Appliance::Session does not support'
                        .' exception objects',
            lastline => '(call last_response for the last line)',
        );
        die $e;
    }
    else {
        return wantarray ? @ret : $ret;
    }
}

foreach my $name (qw/
    binmode
    break
    buffer
    buffer_empty
    cmd_remove_mode
    dump_log
    eof
    errmode
    errmsg
    fhopen
    get
    getline
    getlines
    input_record_separator
    lastline
    login
    max_buffer_length
    ofs
    option_accept
    option_callback
    option_log
    option_send
    option_state
    ors
    output_field_separator
    output_log
    output_record_separator
    port
    print_length
    prompt
    put
    rs
    telnetmode
    timed_out
    waitfor
/) {
    __PACKAGE__->meta->add_method($name, sub {
        my $self = shift;
        return $self->nci->transport->wrapper->$name(@_);
    });
}

1;

# ABSTRACT: Back-compatibility with API version 2


__END__
=pod

=head1 NAME

Net::Appliance::Session::APIv2 - Back-compatibility with API version 2

=head1 VERSION

version 3.122530

=head1 INTRODUCTION

Version 3 of Net::Appliance::Session is a complete rewrite of the previous
version and so all client code will need updating. This is not ideal, but is
important for the module to survive, and have some much-requested features
implemented.

You can choose either to keep things just as they are on your system, with
version 2 API client code and version 2 of the library. Or you can modify your
code to be compatible with version 3 and install that newer version
(recommended). Finally there is the option to have version 3 installed but use
a simple compatibility layer to interface from version 2 client code.

=head1 APIv2 Back-Compat Module

If you have installed version 3 of the library but don't wish to update client
code, this APIv2 Back-Compat Module I<might> be sufficient for your
application to keep working. In your code, wherever you have C<use
Net::Appliance::Session>, replace it with:

 use Net::Appliance::Session::APIv2;

The effect is that a wrapper is placed around the version 3 API such that your
version 2 client code should continue to work. Be aware that the author is not
planning to add any features to this compatibility layer, and in fact some
features are missing (those which cannot be mapped into the new API). The list
of missing features is:

=over 4

=item *

Custom phrasebooks cannot be loaded (i.e. the C<Source> param to C<new()>
doesn't work)

=item *

The C<error()> method is not implemented

=item *

Error strings in output from the device are not acted upon

=item *

All exceptions are of class C<Net::Appliance::Session::Exception>

=item *

Exceptions probably don't contain the same amount of useful information

=back

=head2 A note on error handling

A large part of the philosophy of earlier versions was that the module could
identify certain error conditions at the CLI by the syntax used in output
messages, and act accordingly. Together with that, client code was encouraged
to capture exceptions and check for various conditions, exception types, and
messages.

When automating a CLI, this doesn't really make much sense. If a human makes a
mistake, the CLI shows an error. A computer-driven script should I<never> make
a mistake - it will have been tested and developed. It's unnecessary overhead
to check for errors all the time and attempt to recover. Of course, the remote
device might still have a problem and report it, or die, but in that case
version 3 of the module will still itself C<die> with an error message.

So any version 2 code you have which handles exceptions by class, and checks
for Net::Appliance::Session::Exception will be okay, but other classes used in
earlier versions are not supported in the compatibility layer.

=head1 Porting to API Version 3

The changes are not too severe - you should recognise all the method calls.
Some features have been removed, and you will need to rewrite any custom
phrasebooks. You should go through each of the following sections and make
changes as required.

=head2 Method Parameter Passing

You must provide parameters to the C<new>, C<connect>, and C<begin_privileged>
methods as a I<hash reference with named parameters>. There is no longer the
option to have unnamed parameters as a bare list. Here is an example of how
things must be, for each of these methods:

 my $s = Net::Appliance::Session->new({
     personality => 'ios',
     transport => 'SSH',
     host => 'hostname.example',
 });
 
 eval {
     $s->connect({ name => 'username', password => 'loginpass' });
 
     $s->begin_privileged({ password => 'privilegedpass' });
     
     # etc.....

=head2 Parameters to C<new>

As shown above, you can no longer provide a bare device host name, and nothing
else, to C<new>. You I<must> provide the C<hostname>, C<transport> and
C<personality>.

The C<personality> parameter is the direct equivalent of C<Platform> in the
previous version 2 API. The Transports on offer are the same (except they now
work on Windows natively - no cygwin required).

=head2 Parameters to C<cmd>

As before, you can pass in a single string statement which will be issued to
the connected CLI, followed by a carriage return. The method returns the
complete response either in one Perl Scalar or an Array, depending on what
you assign the result of the method call to:

 my $config     = $s->cmd('show running-config');
 my @interfaces = $s->cmd('show interfaces brief');

In addition, you can pass a Hash Reference as the I<second> parameter, with
some additional options. This includes a custom timeout for the command,
custom Regular Expressions to match the completed response, and the option to
suppress addition of a carriage return. See the
L<Net::CLI::Interact::Role::Engine> manual page for further details.

=head2 Custom Phrasebooks

Sadly it has not been possible to automatically import existing version 2
custom phrasebooks into the version 3 module. The built-in phrasebook is
however still included, just as before.

Please see the comprehensive documentation for
L<Net::CLI::Interact::Phrasebook> and the C<add_library> method of this
module, to see how to construct and install your custom phrasebook. There's
also the L<Cookbook|Net::CLI::Interact::Manual::Cookbook> which gives examples
of the new language.

=head2 Error and Exception Handling

As explained above, there are no longer any fancy exception objects, and
instead just simple Perl C<die> calls when things go wrong. Typically this
will be a timeout in communications at the connected CLI, or a bug in the
module code. Check out the example script included with this distribution for
a demonstration of handling these errors.

=head2 Troubleshooting

Whereas before you used the C<input_log> method, please use the
C<set_global_log_at> method instead, for similar dumping of communications
(and more). There's actually much more powerful logging, if you check out the
main Net::Appliance::Session manual pages.

 $s->set_global_log_at('notice');

=head2 Useful New Features

See the extensive documentation of L<Net::Appliance::Session> or the
underlying L<Net::CLI::Interact> module for details. You have I<a lot> more on
offer with the version 3 API.

=head1 AUTHOR

Oliver Gorwits <oliver@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Oliver Gorwits.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

