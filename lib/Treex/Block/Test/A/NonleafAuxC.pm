package Treex::Block::Test::A::NonleafAuxC;
use Moose;
use Treex::Core::Common;
extends 'Treex::Block::Test::BaseTester';

sub process_anode {
    my ($self, $anode) = @_;
    if ($anode->afun eq 'AuxC'
            and not $anode->get_children
        ) {
        $self->complain($anode);
    }
}

1;

=over

=item Treex::Block::Test::A::NonleafAuxC

AuxC must not be a leaf node.

=back

=cut

# Copyright 2011 Zdenek Zabokrtsky
# This file is distributed under the GNU GPL v2 or later. See $TMT_ROOT/README.

