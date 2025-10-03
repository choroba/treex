package Treex::Tool::UMR::PDTV2PB;
use warnings;
use strict;

use Moose::Role;
use MooseX::Types::Moose qw( Str FileHandle HashRef );
use Moose::Util::TypeConstraints qw{ class_type };
class_type 'XML::LibXML::Element';
use experimental qw( signatures );

use Treex::Core::Log qw{ log_warn };
use Treex::Tool::UMR::PDTV2PB::Parser;
use Text::CSV_XS;
use XML::LibXML;
use namespace::clean;

has vallex  => (is => 'ro', isa => Str, init_arg => undef, writer => '_set_vallex');
has csv     => (is => 'ro', isa => Str, init_arg => undef, writer => '_set_csv');
has mapping => (is => 'ro', lazy => 1,
                init_arg => undef, builder => '_build_mapping',
                writer => '_set_mapping');
has parser  => (is => 'ro', lazy => 1,
                isa => 'Treex::Tool::UMR::PDTV2PB::Parser',
                builder => '_build_parser');
has debug   => (is => 'ro', default => 0);

has _csv    => (is => 'ro', lazy => 1, isa => FileHandle,
                init_arg => undef, builder => '_build__csv');
has _vdom   => (is => 'ro', lazy => 1,
                isa => 'XML::LibXML::Document',
                init_arg => undef, builder => '_build__vdom');
has _by_id  => (is => 'ro', lazy => 1,
                isa => HashRef[HashRef['XML::LibXML::Element | Str']],
                init_arg => undef, builder => '_build__by_id');

around BUILD => sub {
    my ($build, $self, $args) = @_;
    if (exists $args->{mapping}) {
        $self->_set_mapping($self->_parse_mapping($args->{mapping}));
    } else {
        $self->_set_vallex($args->{vallex});
        $self->_set_csv($args->{csv});
    }
    $self->$build($args);
};

sub _build__vdom($self) {
    'XML::LibXML'->load_xml(location => $self->vallex)
}

sub _build__csv($self) {
    open my $c, '<:encoding(UTF-8)', $self->csv or die "Can't open CSV: $!";
    return $c
}

sub _build__by_id($self) {
    my %by_id;
    for my $frame ($self->_vdom->findnodes(
        '/valency_lexicon/body/word/valency_frames/frame')
    ) {
        $by_id{ $frame->{id} } = {
            frame => $frame,
            word  => $frame->findvalue('../../self::word/@lemma')};
    }
    return \%by_id
}

sub _build_mapping($self) {
    my %mapping;
    my $csv = 'Text::CSV_XS'->new({binary => 1, auto_diag => 1});
    my $current_id;
    while (my $row = $csv->getline($self->_csv)) {
        next if 1 == $. || '1' eq $row->[15];

        if ($row->[0]) {
            my ($verb, $frame_id) = $row->[1] =~ /(.*) \((.*)\)/;
            next unless $frame_id;

            ($self->_by_id->{$frame_id}{word} // "") eq $verb
                or log_warn("$frame_id: $verb != "
                            . ($self->_by_id->{$frame_id}{word} // '-'))
                if $frame_id;
            if ($current_id = $frame_id) {
                my $umr_id = ($row->[0] =~ /^"(.*)"$/)[0];
                log_warn("Already exists $current_id $umr_id!"), next
                    if exists $mapping{$current_id}
                    && $mapping{$current_id}{umr_id} ne $umr_id;
                $mapping{$current_id}{umr_id} = $umr_id;
                if ($row->[4]) {
                    $mapping{$current_id}{rule}
                        = $self->validated_lemma($row->[4]);
                }
            }
        } elsif ($current_id) {
            my $relation = $row->[4];
            if (($relation // "") =~ /[!(:]/) {
                $relation = $self->validated_relation($relation);
            }
            $relation = $row->[3] unless length $relation;
            chomp $relation if $relation;
            if ($relation) {
                my ($functor) = $row->[1] =~ /^(?:\?|ALT-)?([^:]+)/;
                log_warn("Ambiguous mapping $mapping{$current_id}{umr_id}"
                         . " $current_id $functor:"
                         . " $relation/$mapping{$current_id}{$functor}!")
                    if exists $mapping{$current_id}{$functor}
                    && $mapping{$current_id}{$functor} ne $relation;
                $mapping{$current_id}{$functor} //= $relation;
            }
        }
    }
    close $self->_csv;

    for my $id (keys %mapping) {
        my %relation;
        ++$relation{$_} for values %{ $mapping{$id} };
        for my $duplicate (grep $relation{$_} > 1, keys %relation) {
            log_warn("Duplicate relation $duplicate in $id.");
        }
    }
    $self->parser->die_if_errors;
    use Data::Dumper; warn Dumper \%mapping;
    return \%mapping
}

sub _parse_mapping($self, $file) {
    my %mapping;
    my @pairs;
    open my $in, '<', $file or die $!;
    my ($umr_id, $rule);
    while (my $line = <$in>) {
        if ($line =~ /^: id: (.+)/) {
            $umr_id = $1;
            $umr_id =~ s/-conflict$//;
            if ($umr_id =~ /[!(:]/) {
                eval { $rule = $self->validated_lemma($umr_id) }
                    or die "Cannot parse: $line";
            }

        } elsif ($line =~ /^ \+ (.*)/) {
            push @pairs, $1 =~ /(\w+ \[[^]]+\])/g;

        } elsif ($line =~ /^\s*-Vallex1_id: (.*)/) {
            my @frames = split /; /, $1;
            for my $frame (@frames) {
                $mapping{$frame}{umr_id} = $umr_id;
                log_warn("Already exists $umr_id")
                    if exists $mapping{$frame}
                    && $mapping{$frame}{umr_id} ne $umr_id;

                for my $pair (@pairs) {
                    my ($functor, $relation) = $pair =~ /(\w+) \[([^]]+)\]/
                        or next;

                    next if 'NA' eq $relation;

                    log_warn("Ambiguous mapping $frame $functor $umr_id:"
                             . " $relation/$mapping{$frame}{$functor}")
                        if exists $mapping{$frame}{$functor}
                        && $mapping{$frame}{$functor} ne $relation;
                    $relation = $self->validated_relation($relation)
                        if $relation =~ /[(!:]/;
                    $mapping{$frame}{$functor} = $relation;
                    $mapping{$frame}{rule} = $rule if $rule;
                }
            }
            @pairs = ();

        } elsif ($line =~ /^$/) {
            @pairs = ();
            undef $umr_id;
            undef $rule;
        }
    }
    $self->parser->die_if_errors;
    return \%mapping
}

sub _build_parser($self) {
    'Treex::Tool::UMR::PDTV2PB::Parser'->new(debug => $self->debug)
}

sub validated_relation($self, $relation) {
    $self->parser->parse($relation)
}

sub validated_lemma($self, $lemma) {
    $self->parser->parse($lemma)
}

=encoding utf-8

=head1 NAME

Treex::Tool::UMR::PDTV2PB - A role translating a valency lexicon to PropBank

=head1 DESCRIPTION

This role maps valency frames to propbank frames.

=head1 METHODS

=over 4

=item mapping

Contains a hash that maps each vallex frame id to a hash that contains the
corresponding UMR concept and relations for all frame members.

  v41jsB => {
      'umr_id' => "být-001",
      'PAT' => 'ARG2',
      'ORIG' => 'causer',
      'ACT' => 'ARG1'
  };


The values can be more complicated if transformation of the frame is needed, e.g.

  'ACT' => "[if(PAT:možný,nutný)(!root)"
         . "if(PAT:možný)(!modal-strength(neutral-affirmative))"
         . "if(PAT:nutný)(!modal-strength(partial-affirmative))"
         . "if(PAT:obtížný,správný,uskutečnitelný)(ARG1)"
         . "else(!error)]"

=back

=head1 CONSTRUCTING

The consuming class has to either provide the C<mapping> file (used in the
Latin Dependency Treebank) or provide the C<vallex> and C<csv>: the valency
lexicon in the PDT Vallex format and a converion table.

=head1 AUTHOR

Jan Štěpánek <stepanek@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2025 by Institute of Formal and Applied Linguistics, Charles
University in Prague.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1
