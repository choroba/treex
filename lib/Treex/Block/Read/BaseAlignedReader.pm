package Treex::Block::Read::BaseAlignedReader;
use Moose;
use Treex::Moose;

has selector => ( isa => 'Selector', is => 'ro', default => '' );

has file_stem => (
    isa           => 'Str',
    is            => 'ro',
    documentation => 'how to name the loaded documents',
);

has _filenames => (
    isa           => 'HashRef[LangCode]',
    is            => 'ro',
    init_arg      => undef,
    default       => sub { {} },
    documentation => 'mapping language->filenames to be loaded;'
        . ' automatically initialized from constructor arguments',
);

has _files_per_language => ( is => 'rw', default => 0 );

has _file_number => (
    isa           => 'Int',
    is            => 'rw',
    default       => 0,
    init_arg      => undef,
    documentation => 'Number of n-tuples of input files loaded so far.',
);

sub BUILD {
    my ( $self, $args ) = @_;
    foreach my $arg ( keys %{$args} ) {
        if ( Treex::Moose::is_lang_code($arg) ) {
            my @files = split( /[ ,]+/, $args->{$arg} );
            if ( !$self->_files_per_language ) {
                $self->_set_files_per_language( scalar @files );
            }
            elsif ( @files != $self->_files_per_language ) {
                log_fatal("All languages must have the same number of files");
            }
            $self->_filenames->{$arg} = \@files;
        }
        elsif ( $arg =~ /selector|language|scenario/ ) { }
        else                                           { log_warn "$arg is not a lang_code"; }
    }
}

sub current_filenames {
    my ($self) = @_;
    my $n = $self->_file_number;
    return if $n == 0 || $n > $self->_files_per_language;
    return map { $_ => $self->_filenames->{$_}[ $n - 1 ] } keys %{ $self->_filenames };
}

sub next_filenames {
    my ($self) = @_;
    $self->_set_file_number( $self->_file_number + 1 );
    return $self->current_filenames;
}

sub new_document {
    my ( $self, $load_from ) = @_;
    my %filenames = $self->current_filenames();
    log_fatal "next_filenames() must be called before new_document()" if !%filenames;

    my ( $stem, $file_number ) = ( '', '' );
    my ( $volume, $dirs, $file );
    if ( $self->file_stem ) {
        ( $stem, $file_number ) = ( $self->file_stem, undef );
    }
    else {    # Magical heuristics how to choose default name for a document loaded from several files
        foreach my $lang ( keys %filenames ) {
            my $filename = $filenames{$lang};
            ( $volume, $dirs, $file ) = File::Spec->splitpath($filename);
            my ( $name, $extension ) = $file =~ /([^.]+)(\..+)?/;
            $name =~ s/[_-]?$lang[_-]?//gi;
            if ( !$name && !$stem ) {
                $name        = 'noname';
                $file_number = undef;
            }
            if ( $stem !~ /$name/ ) {
                $stem .= '_' if $stem ne '';
                $stem .= $name;
            }
        }
    }
    return Treex::Core::Document->new(
        {
            file_stem => $stem,
            loaded_from => join( ',', values %filenames ),
            defined $file_number ? ( file_number => $file_number )    : (),
            defined $dirs        ? ( path        => $volume . $dirs ) : (),
            defined $load_from   ? ( filename    => $load_from )      : (),
        }
    );
}

sub number_of_documents {
    my $self = shift;
    return $self->_files_per_language;
}

1;
