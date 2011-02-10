package Treex::Block::A2T::EN::SetCoapFunctors;
use Moose;
use Treex::Moose;
extends 'Treex::Core::Block';

has '+language' => ( default => 'en' );

sub process_tnode {
    my ( $self, $tnode ) = @_;

    my $functor = get_coap_functor($tnode) or next;
        $tnode->set_functor($functor);
    }
    return 1;
}

sub get_coap_functor {
    my ($t_node) = @_;
    my $lemma = $t_node->t_lemma;
    return 'DISJ' if $lemma eq 'or';
    return 'ADVS' if $lemma eq 'but';
    return 'ADVS' if $lemma eq 'yet' && grep { $_->is_member } $t_node->get_children();

    #return 'CONJ' if any { $_ eq $lemma } qw(and as_well_as);
    # There can be also other CONJ lemmas (& plus),
    # so it is better to check the tag for CC (after solving DISJ...).
    my $a_node = $t_node->get_lex_anode() or return;
    return 'CONJ' if $a_node->tag eq 'CC';
    return;
}

1;

=over

=item Treex::Block::A2T::EN::SetCoapFunctors

Functors (attribute C<functor>) in SEnglishT trees
have to be assigned in (at least) two phases. This block
corresponds to the first phase, in which only coordination and apposition functors
are filled (which makes it possible to use the notions of effective parents and effective
children in the following phase).

=back

=cut

# Copyright 2008-2009 Zdenek Zabokrtsky, Martin Popel

# This file is distributed under the GNU General Public License v2. See $TMT_ROOT/README.
