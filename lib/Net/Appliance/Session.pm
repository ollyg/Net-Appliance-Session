package Net::Appliance::Session;

use Moose;
use Net::Appliance::Session::ActionSet;

has 'personality' => (
    is => 'rw',
    isa => 'Str',
    required => 1,
);

has 'transport' => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

has 'transport_options' => (
    is => 'ro',
    isa => 'HashRef[Str]',
    default => sub { {} },
    required => 0,
);

has 'library' => (
    is => 'ro',
    isa => 'Str|ArrayRef[Str]',
    default => sub { ['share'] },
    required => 0,
);

has 'add_library' => (
    is => 'ro',
    isa => 'Str|ArrayRef[Str]',
    default => sub { [] },
    required => 0,
);

has '_state' => (
    is => 'ro',
    isa => 'HashRef[Net::Appliance::Session::ActionSet]',
    default => sub { {} },
    required => 0,
);

has '_macro' => (
    is => 'ro',
    isa => 'HashRef[Net::Appliance::Session::ActionSet]',
    default => sub { {} },
    required => 0,
);

sub BUILD {
    my ($self, $params) = @_;

    $self->_load_graph;

    use Moose::Util;
    Moose::Util::apply_all_roles($self, 
        'Net::Appliance::Session::Transport::'. $self->transport);
}

# inflate the hashref into action objects
use Net::Appliance::Session::ActionSet;
sub _bake {
    my ($self, $data) = @_;
    return unless ref $data eq ref {} and keys %$data;

    my $slot = '_'. (lc $data->{type});
    $self->$slot->{$data->{name}}
        = Net::Appliance::Session::ActionSet->new({
            actions => $data->{actions}
        });
}

# parse phrasebook files and load action objects
sub _load_graph {
    my $self = shift;
    my $data = {};

    foreach my $file ($self->_find_phrasebooks) {
        my @lines = $file->slurp;
        while ($_ = shift @lines) {
            # Skip comments and empty lines
            next if m/^(?:#|\s*$)/;

            if (m{^(state|macro) (\w+)\s*$}) {
                $self->_bake($data);
                $data = {type => $1, name => $2};
            }
            elsif (m{^\w}) {
                $_ = shift @lines until m{^(?:state|macro)};
                unshift @lines, $_;
            }

            if (m{^\s+send\s+(.+)$}) {
                push @{ $data->{actions} },
                    {type => 'send', value => $1};
            }
            if (m{^\s+match\s+/(.+)/\s*$}) {
                push @{ $data->{actions} },
                    {type => 'match', value => qr/$1/m};
            }

            if (m{^\s+follow\s+/(.+)/\s+with\s+(.+)\s*$}) {
                my ($match, $send) = ($1, $2);
                $send =~ s/^["']//; $send =~ s/["']$//;
                $data->{actions}->[-1]->{continuation} = [
                    {type => 'match', value => qr/$match/},
                    {type => 'send',  value => $send}
                ];
            }
        }
        # last entry in the file needs baking
        $self->_bake($data);
    }
}

# finds the path of Phrasebooks within the Library leading to Personality
use Path::Class;
sub _find_phrasebooks {
    my $self = shift;
    my @libs = (ref $self->add_library ? @{$self->add_library} : ($self->add_library));
    push @libs, (ref $self->library ? @{$self->library} : ($self->library));

    my $target = undef;
    foreach my $l (@libs) {
        Path::Class::Dir->new($l)->recurse(callback => sub {
            return unless $_[0]->is_dir;
            $target = $_[0] if $_[0]->dir_list(-1) eq $self->personality
        });
        last if $target;
    }
    die (sprintf "couldn't find Personality '%s' within your Library\n",
            $self->personality) unless $target;

    my @phrasebooks = ();
    my $root = Path::Class::Dir->new();
    foreach my $part ( $target->dir_list ) {
        $root = $root->subdir($part);
        push @phrasebooks,
            sort {$a->basename cmp $b->basename}
            grep { not $_->is_dir } $root->children(no_hidden => 1);
    }

    die (sprintf "Personality [%s] contains no content!\n",
            $self->personality) unless scalar @phrasebooks;
    return @phrasebooks;
}

1;
