package Treex::Block::HamleDT::KO::FixUD;
use Moose;
use List::MoreUtils qw(any);
use Treex::Core::Common;
use utf8;
use Treex::Tool::PhraseBuilder::StanfordToUD;
extends 'Treex::Core::Block';



sub process_atree
{
    my $self = shift;
    my $root = shift;
    $self->fix_morphology($root);
    $self->regenerate_upos($root);
    $self->fix_relations($root);
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



#------------------------------------------------------------------------------
# Fixes known issues in features.
#------------------------------------------------------------------------------
sub fix_morphology
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants({ordered => 1});
    foreach my $node (@nodes)
    {
        my $form = $node->form();
        my $iset = $node->iset();
        ###!!! PLACEHOLDER
    }
}



#------------------------------------------------------------------------------
# After changes done to Interset (including part of speech) generates the
# universal part-of-speech tag anew.
#------------------------------------------------------------------------------
sub regenerate_upos
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        $node->set_tag($node->iset()->get_upos());
    }
}



#------------------------------------------------------------------------------
# Fixes known issues in dependency relations.
#------------------------------------------------------------------------------
sub fix_relations
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants({ordered => 1});
    foreach my $node (@nodes)
    {
        my $deprel = $node->deprel();
        if($deprel eq 'numc')
        {
            $deprel = 'flat';
        }
        elsif($deprel eq 'precomp')
        {
            $deprel = 'compound:lvc';
        }
        elsif($deprel eq 'obl:poss')
        {
            $deprel = 'obl';
        }
        elsif($deprel eq 'pref')
        {
            $deprel = 'det';
        }
        $node->set_deprel($deprel);
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

=item Treex::Block::HamleDT::KO::FixUD

This is a temporary block that should fix selected known problems in the Korean UD treebank.

=back

=head1 AUTHORS

Daniel Zeman <zeman@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2016-2018 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
