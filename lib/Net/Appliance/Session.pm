package Net::Appliance::Session;

use Moose;
with 'Net::Appliance::Session::Role::Engine';
use Net::Appliance::Session::ActionSet;

has 'states' => (
    is => 'ro',
    isa => 'HashRef[Net::Appliance::Session::ActionSet]',
    default => sub { {} },
    required => 0,
);

has 'macros' => (
    is => 'ro',
    isa => 'HashRef[Net::Appliance::Session::ActionSet]',
    default => sub { {} },
    required => 0,
);

has 'transitions' => (
    is => 'ro',
    isa => 'HashRef[Net::Appliance::Session::ActionSet]',
    default => sub { {} },
    required => 0,
);

has 'host' => (
    is => 'rw',
    isa => 'Str',
    required => 1,
);

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

    my $slot = (lc $data->{type}) . 's'; # fragile
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
            # trim
            s/^\s+//; s/\s+$//;
            # Skip comments and empty lines
            next if m/^(?:\#|\;|$)/;
            # Remove inline comments
            s/\s\;\s.+$//g;

            if (m/^(state|macro) (\w+)/) {
                $self->_bake($data);
                $data = {name => $2, type => ucfirst $1};
            }
            if (m/^from\s+(\w+)\s+to\s+(\w+)/) {
                $self->_bake($data);
                $data = {name => "${1}_to_${2}", type => 'Transition'};
            }

            if (m/^send\s+(.+)/) {
                push @{ $data->{actions} },
                    {type => 'send', value => $1};
            }
            if (m/^match\s+\/(.+)\/$/) {
                push @{ $data->{actions} },
                    {type => 'match', value => qr/$1/};
            }

            if (m/^continuation\s+\/(.+)\/$/) {
                $data->{actions}->[-1]->{continuation} = qr/$1/;
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
