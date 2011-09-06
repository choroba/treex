package Treex::Block::A2A::RU::CoNLL2PDTStyle;
use Moose;
use Treex::Core::Common;
use utf8;
extends 'Treex::Block::A2A::CoNLL2PDTStyle';

#------------------------------------------------------------------------------
# Reads the Russian tree, converts morphosyntactic tags to the PDT tagset,
# converts deprel tags to afuns, transforms tree to adhere to PDT guidelines.
#------------------------------------------------------------------------------

sub process_zone
{
    my $self   = shift;
    my $zone   = shift;
    $self->backup_zone($zone);
    my $a_root = $zone->get_atree();

    $self->convert_tags( $a_root, 'syntagrus' );
    $self->tag_to_pos($a_root);
    $self->attach_final_punctuation_to_root($a_root);
    $self->fill_root_afun($a_root);
    $self->restructure_coordination($a_root);
    $self->deprel_to_afun($a_root);
    $self->check_afuns($a_root);
}


sub fill_root_afun {
    my $self = shift;
    my $a_root = shift;

    foreach my $ch ($a_root->get_children) {
        if (!$ch->conll_deprel) {
            $ch->set_conll_deprel($ch->tag =~ /^V/ ? 'Pred' : 'ExD');
        }
    }
}

sub tag_to_pos {
    my $self = shift;
    my $a_root = shift;
    foreach my $a_node ( $a_root->get_descendants() ) {
        $a_node->set_conll_pos($a_node->tag);
    }
}

sub restructure_coordination {
    my $self = shift;
    my $a_root = shift;
    
    foreach my $a_node ( $a_root->get_descendants() ) {
        if ( $a_node->conll_deprel =~ /^(сент-соч|сочин|ком-сочин|соч-союзн)$/ ) {
            my $conjunction;
            my $parent = $a_node->get_parent->get_parent;
            next if !$parent;
            my @members = ($a_node->get_parent);
            if ($members[0]->tag && $members[0]->tag =~ /^J\^/) {
                $conjunction = $members[0];
                @members = ();
            }
            my $current_node = $a_node;
            while ($current_node) {
                if ($current_node->tag =~ /^J\^/) {
                    $conjunction = $current_node;
                }
                else {
                    push @members, $current_node;
                }
                my @children = $current_node->get_children;
                last if !@children;
                $current_node = undef;
                foreach my $child (@children) {
                    if ($child->conll_deprel =~ /^(сент-соч|сочин|ком-сочин|соч-союзн)$/) {
                        $current_node = $child;
                        last;
                    }
                }
            }
            if ($conjunction) {
                $conjunction->set_conll_deprel('Coord');
                $conjunction->set_parent($parent);
            }
            foreach my $member (@members) {
                $member->set_parent($conjunction) if $conjunction;
                $member->set_conll_deprel($members[0]->conll_deprel);
                $member->set_is_member(1) if $conjunction;
            }
        }
    }
}


my %deprel2afun = ( 'предик' => 'Sb',
                    'предл' => 'AuxP',
                    'подч-союзн' => 'AuxC',
                    'опред' => 'Atr',
                    'оп-опред' => 'Atr',
                    'аппрокс-порядк' => 'Atr',
                    'релят' => 'Atr',
                    '1-компл' => 'Obj',
                    '2-компл' => 'Obj',
                    '3-компл' => 'Obj',
                    '4-компл' => 'Obj',
                    '5-компл' => 'Obj',
                    'адр-присв' => 'Obj',
                    'обст'     => 'Adv',
                    'длительн'     => 'Adv',
                    'кратно-длительн'     => 'Adv',
                    'дистанц'     => 'Adv',
                    'обст-тавт'     => 'Adv',
                    'суб-обст'     => 'Adv',
                    'об-обст'     => 'Adv',
                    'суб-копр'     => 'Adv',
                    'об-копр'     => 'Adv',
                    'огранич'     => 'Adv',
                    'вводн'     => 'Adv',
                    'изъясн'     => 'Adv',
                    'разъяснит'     => 'Adv',
                    'примыкат'     => 'Adv',
                    'уточн'     => 'Adv',
                    'Coord' => 'Coord',
                    'Pred' => 'Pred',
                    'ExD' => 'ExD',
                  );


sub deprel_to_afun {

    my $self   = shift;
    my $a_root = shift;

    # switch deprels for preposition phrases
    foreach my $node ($a_root->get_descendants) {
        if ($node->tag =~ /^RR/) {
            my $deprel = $node->conll_deprel;
            $node->set_conll_deprel('предл');
            foreach my $child ($node->get_children) {
                $child->set_conll_deprel($deprel) if $child->conll_deprel eq 'предл' && $deprel ne 'предл';
            }
        }
        elsif ($node->tag =~ /^J\^/) {
            my $deprel = $node->conll_deprel;
            foreach my $child ($node->get_children) {
                if ($child->conll_deprel eq 'подч-союзн' && $deprel ne 'Coord') {
                    $child->set_conll_deprel($deprel);
                    $node->set_conll_deprel('подч-союзн');
                }
            }
        }
    }

    foreach my $node ($a_root->get_descendants) {
        if ($deprel2afun{$node->conll_deprel}) {
            $node->set_afun($deprel2afun{$node->conll_deprel});
        }
        else {
            $node->set_afun('Atr');
        }
    }
}


1;

=over

=item Treex::Block::A2A::RU::CoNLL2PDTStyle

Converts Syntagrus (Russian Dependency Treebank) trees to the style of
the Prague Dependency Treebank.
Morphological tags will be
decoded into Interset and to the 15-character positional tags
of PDT.

=back

=cut

# Copyright 2011 Dan Zeman <zeman@ufal.mff.cuni.cz>
# This file is distributed under the GNU General Public License v2. See $TMT_ROOT/README.
