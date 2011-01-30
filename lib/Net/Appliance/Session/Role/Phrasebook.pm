package Net::Appliance::Session::Role::Phrasebook;

use Moose::Role;
use Net::Appliance::Session::ActionSet;

has 'personality' => (
    is => 'rw',
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

has '_prompt_tbl' => (
    is => 'ro',
    isa => 'HashRef[Net::Appliance::Session::ActionSet]',
    default => sub { {} },
    required => 0,
);

has '_macro_tbl' => (
    is => 'ro',
    isa => 'HashRef[Net::Appliance::Session::ActionSet]',
    default => sub { {} },
    required => 0,
);

# inflate the hashref into action objects
sub _bake {
    my ($self, $data) = @_;
    return unless ref $data eq ref {} and keys %$data;
    $self->log('phrasebook', 3, 'storing type', $data->{type}, 'with name', $data->{name});

    my $slot = '_'. (lc $data->{type}) .'_tbl';
    $self->$slot->{$data->{name}}
        = Net::Appliance::Session::ActionSet->new({
            actions => $data->{actions}
        });
}

# matches which are prompt names are resolved to RegexpRefs
sub _resolve_lazy_matches {
    my $self = shift;

    foreach my $name (keys %{$self->_macro_tbl}) {
        my $set = $self->_macro_tbl->{$name};
        my $new_set = [];

        $set->reset;
        while ($set->has_next) {
            my $item = $set->next;
            if ($item->is_lazy) {
                push @$new_set, $item->clone({ value =>
                    $self->_prompt_tbl->{$item->value}->first->value
                });
            }
            else {
                push @$new_set, $item;
            }
        }

        $self->_macro_tbl->{$name} = Net::Appliance::Session::ActionSet->new({
            actions => $new_set
        });
    }
}

# parse phrasebook files and load action objects
sub _load_phrasebooks {
    my $self = shift;
    my $data = {};

    foreach my $file ($self->_find_phrasebooks) {
        $self->log('phrasebook', 2, 'reading phrasebook', $file);
        my @lines = $file->slurp;
        while ($_ = shift @lines) {
            # Skip comments and empty lines
            next if m/^(?:#|\s*$)/;

            if (m{^(prompt|macro)\s+(\w+)\s*$}) {
                $self->_bake($data);
                $data = {type => $1, name => $2};
            }
            elsif (m{^\w}) {
                $_ = shift @lines until m{^(?:prompt|macro)};
                unshift @lines, $_;
            }

            if (m{^\s+(send(?:_literal)?)\s+(.+)$}) {
                push @{ $data->{actions} }, {
                    type => 'send', value => $2,
                    literal => ($1 eq 'send_literal')
                };
                next;
            }

            if (m{^\s+match\s+prompt\s+(.+)\s*$}) {
                push @{ $data->{actions} },
                    {type => 'match', value => $1, lazy => 1};
                next;
            }

            if (m{^\s+match\s+/(.+)/\s*$}) {
                push @{ $data->{actions} },
                    {type => 'match', value => qr/$1/};
                next;
            }

            if (m{^\s+follow\s+/(.+)/\s+with\s+(.+)\s*$}) {
                my ($match, $send) = ($1, $2);
                $send =~ s/^["']//; $send =~ s/["']$//;
                $data->{actions}->[-1]->{continuation} = [
                    {type => 'match', value => qr/$match/},
                    {type => 'send',  value => $send, literal => 1}
                ];
                next;
            }
        }
        # last entry in the file needs baking
        $self->_bake($data);
    }

    $self->_resolve_lazy_matches;
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
    confess (sprintf "couldn't find Personality '%s' within your Library\n",
            $self->personality) unless $target;

    my @phrasebooks = ();
    my $root = Path::Class::Dir->new();
    foreach my $part ( $target->dir_list ) {
        $root = $root->subdir($part);
        push @phrasebooks,
            sort {$a->basename cmp $b->basename}
            grep { not $_->is_dir } $root->children(no_hidden => 1);
    }

    confess (sprintf "Personality [%s] contains no content!\n",
            $self->personality) unless scalar @phrasebooks;
    return @phrasebooks;
}

1;
