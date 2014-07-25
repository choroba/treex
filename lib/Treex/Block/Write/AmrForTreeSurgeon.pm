package Treex::Block::Write::AmrForTreeSurgeon;
use Moose;
use Treex::Core::Common;
extends 'Treex::Block::Write::Amr';

# Returns the t-node's lemma/label
sub _get_lemma {
    my ( $self, $tnode ) = @_;
    my @data = ( $tnode->t_lemma );

    if ( $tnode->src_tnode ) {
        push @data, 'formeme=' . ( $tnode->src_tnode->formeme // '' );

        my @anodes;
        if ( $tnode->wild->{is_ne_head} ) {
            my $nnode = $tnode->get_document()->get_node_by_id( $tnode->wild->{src_nnode} );
            @anodes = sort { $a->ord <=> $b->ord } $nnode->get_anodes();            
        }
        else {
            @anodes = $tnode->src_tnode->get_anodes( { ordered => 1 } );
        }
        push @data, 'lemma=' . join( ' ', map { $_->lemma } @anodes );
        push @data, 'form=' . join( ' ', map { $_->form } @anodes );
    }
    push @data, 'id=' . $tnode->id;
    
    return join(' ', map { $_ =~ s/ /_/g; $_ } @data );
}

1;

__END__

=head1 NAME

Treex::Block::Write::Amr

=head1 DESCRIPTION

Document writer for amr-like format.

=head1 ATTRIBUTES

=over

=item language

Language of tree


=item selector

Selector of tree

=back


=head1 COPYRIGHT AND LICENSE

Copyright © 2014 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
