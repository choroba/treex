package Treex::Block::HamleDT::UD1To2;
use utf8;
use Moose;
use List::MoreUtils qw(any);
use Treex::Core::Common;
use Treex::Tool::PhraseBuilder::StanfordToUD;
extends 'Treex::Core::Block';



sub process_atree
{
    my $self = shift;
    my $root = shift;
    # Fix relations before morphology. The fixes depend only on UPOS tags, not on morphology (e.g. NOUN should not be attached as det).
    # And with better relations we will be more able to disambiguate morphological case and gender.
    $self->convert_deprels($root);
    # Coordinating conjunctions and punctuation should now be attached to the following conjunct.
    # The Coordination phrase class already outputs the new structure, hence simple
    # conversion to phrases and back should do the trick.
    my $builder = new Treex::Tool::PhraseBuilder::StanfordToUD
    (
        'prep_is_head'           => 0,
        'coordination_head_rule' => 'first_conjunct'
    );
    my $phrase = $builder->build($root);
    $phrase->project_dependencies();
}



my %v12deprel =
(
    'dobj'      => 'obj',
    'nsubjpass' => 'nsubj:pass',
    'csubjpass' => 'csubj:pass',
    'auxpass'   => 'aux:pass',
    ###!!! We may want to also check that the child node has either Polarity=Neg or PronType=Neg.
    'neg'       => 'advmod',
    'name'      => 'flat',
    ###!!! We may want to convert 'foreign' to just 'flat' and check that both the child and the parent have the feature Foreign=Yes.
    'foreign'   => 'flat:foreign',
    'mwe'       => 'fixed'
);



#------------------------------------------------------------------------------
# Converts dependency relations from UD v1 to v2.
#------------------------------------------------------------------------------
sub convert_deprels
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        my $parent = $node->parent();
        my $deprel = $node->deprel();
        if(exists($v12deprel{$deprel}))
        {
            $node->set_deprel($v12deprel{$deprel});
        }
        # Split 'nmod' to 'nmod' and 'obl'. This is an approximation only.
        # If an 'nmod' depends on a nominal predicate, we do not know whether it is
        # a location/time adjunct (as in "he will be smarter <next time>"), or just
        # a modifier of a nominal (as in "he will be professor <of linguistics>").
        elsif($deprel eq 'nmod' && $parent->is_verb())
        {
            $node->set_deprel('obl');
        }
    }
}



#------------------------------------------------------------------------------
# Collects all nodes in a subtree of a given node. Useful for fixing known
# annotation errors, see also get_node_spanstring(). Returns ordered list.
#------------------------------------------------------------------------------
sub get_node_subtree
{
    my $self = shift;
    my $node = shift;
    my @nodes = $node->get_descendants({'add_self' => 1, 'ordered' => 1});
    return @nodes;
}



#------------------------------------------------------------------------------
# Collects word forms of all nodes in a subtree of a given node. Useful to
# uniquely identify sentences or their parts that are known to contain
# annotation errors. (We do not want to use node IDs because they are not fixed
# enough in all treebanks.) Example usage:
# if($self->get_node_spanstring($node) =~ m/^peça a URV em a sua mesada$/)
#------------------------------------------------------------------------------
sub get_node_spanstring
{
    my $self = shift;
    my $node = shift;
    my @nodes = $self->get_node_subtree($node);
    return join(' ', map {$_->form() // ''} (@nodes));
}



1;

=over

=item Treex::Block::HamleDT::UD1To2

This is a temporary block that should do the language-independent part of conversion
from Universal Dependencies v1 to v2.

=back

=head1 AUTHORS

Daniel Zeman <zeman@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2017 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
