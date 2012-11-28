package Treex::Tool::Triggers::Features;

use Moose;
use Treex::Core::Common;

use Treex::Tool::Coreference::ContentCandsGetter;
use Treex::Tool::IR::ESA;

has 'prev_sents_num' => (
    isa => 'Num',
    is => 'ro',
    default => 2,
    required => 1,
);

has '_trigger_words_getter' => (
    isa => 'Treex::Tool::Coreference::AnteCandsGetter',
    is => 'ro',
    required => 1,
    lazy => 1,
    builder => '_build_trigger_words_getter',
);

has '_esa_provider' => (
    isa => 'Treex::Tool::IR::ESA',
    is => 'ro',
    lazy => 1,
    builder => '_build_esa',
);

sub BUILD {
    my ($self) = @_;
    $self->_trigger_words_getter;
}

sub _build_trigger_words_getter {
    my ($self) = @_;

    my $acs = Treex::Tool::Coreference::ContentCandsGetter->new({
        prev_sents_num => $self->prev_sents_num,
        anaphor_as_candidate => 0,
        cands_within_czeng_blocks => 1,
    });
    return $acs;
}

sub _build_esa {
    my ($self) = @_;
    return Treex::Tool::IR::ESA->new();
}

sub create_lemma_instance {
    my ($self, $tnode) = @_;
        
    my $trigger_nodes = $self->_trigger_words_getter->get_candidates( $tnode );
    return $self->_extract_lemmas($trigger_nodes)
}

sub create_esa_instance {
    my ($self, $tnode, $n) = @_;
        
    my $trigger_nodes = $self->_trigger_words_getter->get_candidates( $tnode );
    if (@$trigger_nodes == 0) {
        return {};
    }
    return $self->_extract_esa_vector($trigger_nodes, $n)
}

sub _extract_esa_vector {
    my ($self, $nodes, $n) = @_;
    my $text = join " ", map {$_->t_lemma} @$nodes;
    my %vector = $self->_esa_provider->esa_vector_n_best($text, $n);
    my %feats = map {"esa_" . $_ => $vector{$_}} keys %vector;
    return \%feats;
}

sub _extract_lemmas {
    my ($self, $nodes) = @_;
    my %lemmas = map {'trig=' . lc($_->t_lemma) => 1} @$nodes;
    return \%lemmas;
    #return sort keys %lemmas;
}

1;
__END__

=encoding utf-8

=head1 NAME 

Treex::Tool::Triggers::Features

=head1 DESCRIPTION

Features for trigger based models. Features are t-lemmas of the content words
from the previous context given by the parameter C<prev_sents_num>. 

=head1 PARAMETERS

=over

=item prev_sents_num

The size of the previous context (in sentences) from which the features
are extracted.

=back

=head1 METHODS

=over

=item create_instance

Returns a hash reference whose keys are features and values are
values of the features.

=back

=head1 AUTHORS

Michal Novák <mnovak@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2012 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
