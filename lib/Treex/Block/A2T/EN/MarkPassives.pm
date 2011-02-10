package Treex::Block::A2T::EN::MarkPassives;
use Moose;
use Treex::Moose;
extends 'Treex::Core::Block';

has '+language' => ( default => 'en' );

sub process_tnode {
    my ( $self, $t_node ) = @_;

            my $lex_a_node = $t_node->get_lex_anode();
            next if !defined $lex_a_node;    # gracefully handle e.g. generated nodes
            my @aux_a_nodes = $t_node->get_aux_anodes();

            if ($lex_a_node->tag =~ /VB[ND]/
                and (
                    ( grep { $_->lemma eq "be" } @aux_a_nodes )
                    or not $t_node->is_clause_head    # 'informed citizens' is marked too
                )
                )
            {                                                     # ??? to je otazka, jestli obe
                $t_node->set_is_passive( 1 );
            }
            else {
                $t_node->set_is_passive( undef );
            }
    return 1;
}

1;

=over

=item Treex::Block::A2T::EN::MarkPassives

EnglishT nodes corresponding to passive verb expressions are
    marked with value 1 in the C<is_passive> attribute.

    =back
    =cut

    # Copyright 2008 Zdenek Zabokrtsky

# This file is distributed under the GNU General Public License v2. See $TMT_ROOT/README.
