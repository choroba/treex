package Treex::Block::A2A::BG::CoNLL2PDTStyle;
use Moose;
use Treex::Core::Common;
use utf8;
extends 'Treex::Block::A2A::CoNLL2PDTStyle';



#------------------------------------------------------------------------------
# Reads the Bulgarian tree, converts morphosyntactic tags to the PDT tagset,
# converts deprel tags to afuns, transforms tree to adhere to PDT guidelines.
#------------------------------------------------------------------------------
sub process_zone
{
    my $self = shift;
    my $zone = shift;
    my $a_root = $self->SUPER::process_zone($zone);
    # Adjust the tree structure.
    $self->attach_final_punctuation_to_root($a_root);
    $self->process_auxiliary_particles($a_root);
    $self->process_auxiliary_verbs($a_root);
    $self->restructure_coordination($a_root);
    $self->mark_deficient_clausal_coordination($a_root);
}



#------------------------------------------------------------------------------
# Try to convert dependency relation tags to analytical functions.
# http://www.bultreebank.org/dpbtb/
# http://ufal.mff.cuni.cz/pdt2.0/doc/manuals/cz/a-layer/html/ch03s02.html
#------------------------------------------------------------------------------
sub deprel_to_afun
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        my $deprel = $node->conll_deprel();
        if($deprel eq 'ROOT')
        {
            if($node->get_iset('pos') eq 'verb' || $self->is_auxiliary_particle($node))
            {
                $node->set_afun('Pred');
            }
            else
            {
                $node->set_afun('ExD');
            }
        }
        elsif($deprel =~ m/^x?subj$/)
        {
            $node->set_afun('Sb');
        }
        # comp ... Complement (arguments of: non-verbal heads, non-finite verbal heads, copula)
        # nominal predicate: check that the governing node is a copula
        elsif($deprel eq 'comp')
        {
            # If parent is form of the copula verb 'to be', this complement shall be 'Pnom'.
            # Otherwise, it shall be 'Obj'.
            my $parent = $node->parent();
            my $verb = $parent;
            # If we have not processed the auxiliary particles yet, the parent is the particle and not the copula.
            if($self->is_auxiliary_particle($parent))
            {
                my $lvc = $self->get_leftmost_verbal_child($parent);
                if(defined($lvc))
                {
                    $verb = $lvc;
                }
            }
            # \x{435} = 'e' (cs:je)
            # \x{441}\x{430} = 'sa' (cs:jsou)
            # \x{441}\x{44A}\x{43C} = 'săm' (cs:jsem)
            # \x{431}\x{44A}\x{434}\x{435} = 'băde' (cs:bude)
            if($node!=$verb && $verb->form() =~ m/^(\x{435}|\x{441}\x{430}|\x{431}\x{44A}\x{434}\x{435}|\x{441}\x{44A}\x{43C})$/)
            {
                $node->set_afun('Pnom');
            }
            else
            {
                $node->set_afun('Obj');
            }
        }
        # obj ... Object (direct argument of a non-auxiliary verbal head)
        # indobj ... Indirect Object (indirect argument of a non-auxiliary verbal head)
        # object, indirect object or complement
        elsif($deprel =~ m/^((ind)?obj)$/)
        {
            $node->set_afun('Obj');
        }
        # adjunct: free modifier of a verb
        # xadjunct: clausal modifier
        elsif($deprel eq 'xadjunct' && $node->match_iset('pos' => 'conj', 'subpos' => 'sub'))
        {
            $node->set_afun('AuxC');
        }
        # marked ... Marked (clauses, introduced by a subordinator)
        elsif($deprel eq 'marked')
        {
            $node->set_afun('Adv');
        }
        elsif($deprel =~ m/^x?adjunct$/)
        {
            $node->set_afun('Adv');
        }
        # Pragmatic adjunct is an adjunct that does not change semantic of the head. It changes pragmatic meaning. Example: vocative phrases.
        elsif($deprel eq 'pragadjunct')
        {
            # PDT: AuxY: "příslovce a částice, které nelze zařadit jinam"
            # PDT: AuxZ: "zdůrazňovací slovo"
            # The only example I saw was the word 'păk', tagged as a particle of emphasis.
            $node->set_afun('AuxZ');
        }
        # xcomp: clausal complement
        # If the clause has got a complementizer ('that'), the complementizer is tagged 'xcomp'.
        # If there is no complementizer (such as direct speech), the root of the clause (i.e. the verb) is tagged 'xcomp'.
        elsif($deprel eq 'xcomp')
        {
            if($node->get_iset('pos') eq 'verb')
            {
                $node->set_afun('Obj');
            }
            else
            {
                $node->set_afun('AuxC');
            }
        }
        # negative particle 'ne', modifying a verb, is an adverbiale
        elsif($deprel eq 'mod' && lc($node->form()) eq "\x{43D}\x{435}")
        {
            $node->set_afun('Adv');
        }
        # mod: modifier (usually of a noun phrase)
        # xmod: clausal modifier
        elsif($deprel =~ m/^x?mod$/)
        {
            $node->set_afun('Atr');
        }
        # clitic: often a possessive pronoun ('si', 'ni', 'j') attached to noun, adjective or pronoun => Atr
        # sometimes a reflexive personal pronoun ('se') attached to verb (but the verb is in a nominalized form and functions as subject!)
        elsif($deprel eq 'clitic')
        {
            if($node->match_iset('prontype' => 'prs', 'poss' => 'poss'))
            {
                $node->set_afun('Atr');
            }
            else
            {
                $node->set_afun('AuxT');
            }
        }
        # The conjunction 'i' can serve emphasis ('even').
        # If it builds coordination instead, its afun will be corrected later.
        elsif($deprel eq 'conj' && $node->form() eq 'и')
        {
            $node->set_afun('AuxZ');
        }
        elsif($deprel eq 'punct')
        {
            # PDT: AuxX: "čárka (ne však nositel koordinace)"
            # PDT: AuxG: "jiné grafické symboly, které neukončují větu"
            if($node->form() eq ',')
            {
                $node->set_afun('AuxX');
            }
            else
            {
                $node->set_afun('AuxG');
            }
        }
    }
    # Once all nodes have hopefully their afuns, prepositions must delegate their afuns to their children.
    # (Don't do this earlier. If appositions are postpositions, we would be copying afuns that don't exist yet.)
    foreach my $node (@nodes)
    {
        my $deprel = $node->conll_deprel();
        if($deprel =~ m/^x?prepcomp$/)
        {
            my $preposition = $node->parent();
            # We assume that every preposition has exactly one prepcomp child.
            # Otherwise, the first prepcomp child would steal the afun and the second child would only get the newly assigned 'AuxP'.
            $node->set_afun($preposition->afun());
            $preposition->set_afun('AuxP');
        }
    }
}



#------------------------------------------------------------------------------
# Examines the last node of the sentence. If it is a punctuation, makes sure
# that it is attached to the artificial root node.
#------------------------------------------------------------------------------
sub attach_final_punctuation_to_root
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants();
    my $fnode = $nodes[$#nodes];
    my $final_pos = $fnode->get_iset('pos');
    if($final_pos eq 'punc' && $fnode->parent()!=$root)
    {
        $fnode->set_parent($root);
        $fnode->set_afun('AuxK');
    }
}



#------------------------------------------------------------------------------
# Returns the noun phrase attached directly to the preposition in a
# prepositional phrase.
#------------------------------------------------------------------------------
sub get_prepcomp
{
    my $self = shift;
    my $prepnode = shift;
    # We cannot reliably assume that a preposition has only one child.
    # There may be rhematizers modifying the whole prepositional phrase.
    my @prepchildren = grep {$_->conll_deprel() eq 'prepcomp'} ($prepnode->children());
    if(@prepchildren)
    {
        return $prepchildren[0];
    }
    return undef;
}



#------------------------------------------------------------------------------
# Detects auxiliary particles using Interset features.
#------------------------------------------------------------------------------
sub is_auxiliary_particle
{
    my $self = shift;
    my $node = shift;
    return $node->match_iset('pos' => 'part', 'subpos' => 'aux');
}



#------------------------------------------------------------------------------
# Finds the leftmost verbal child if any. Useful to find the verbs belonging to
# auxiliary particles. (There may be other children having the 'comp' deprel;
# these children are complements to the particle-verb pair.)
#------------------------------------------------------------------------------
sub get_leftmost_verbal_child
{
    my $self = shift;
    my $node = shift;
    my @children = $node->children();
    my @verbchildren = grep {$_->get_iset('pos') eq 'verb' && $_->conll_deprel() eq 'comp'} (@children);
    if(@verbchildren)
    {
        return $verbchildren[0];
    }
    return undef;
}



#------------------------------------------------------------------------------
# There are two auxiliary particles in BulTreeBank:
# 'da' is an infinitival marker;
# 'šte' is used to construct the future tense.
# Both originally govern an infinitive verb clause.
# Both will be treated as subordinating conjunctions in Czech.
#------------------------------------------------------------------------------
sub process_auxiliary_particles
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        if($self->is_auxiliary_particle($node))
        {
            # Consider the first verbal child of the particle the clausal head.
            my $head = $self->get_leftmost_verbal_child($node);
            if(defined($head))
            {
                my @children = $node->children();
                # Reattach all other children to the new head.
                foreach my $child (@children)
                {
                    unless($child==$head)
                    {
                        $child->set_parent($head);
                    }
                }
                # Experiment: different treatment of 'da' and 'šte'.
                if($node->form() eq 'да')
                {
                    # Treat the particle as a subordinating conjunction.
                    $node->set_afun('AuxC');
                }
                else # šte
                {
                    $self->lift_node($head, 'AuxV');
                }
            }
        }
    }
}



#------------------------------------------------------------------------------
# Constructions like "mogăl bi" (cs:mohl by). "mogăl" is a participle (in this
# case modal but it does not matter). "bi" is a form of the auxiliary verb
# "to be". In BulTreeBank, "bi" governs "mogăl". In PDT it would be vice versa.
#------------------------------------------------------------------------------
sub process_auxiliary_verbs
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants();
    my @liftnodes;
    # Search for nodes to lift.
    foreach my $node (@nodes)
    {
        # Is this a non-auxiliary verb?
        # Is its parent an auxiliary verb?
        if(
          $node->match_iset('pos' => 'verb', 'subpos' => '!aux', 'verbform' => 'part')
          # &&
          # $node->form() eq 'могъл'
        )
        {
            my $parent = $node->parent();
            if(!$parent->is_root() &&
              # $parent->get_attr('conll_pos') eq 'Vxi'
              # $parent->match_iset('pos' => 'verb', 'subpos' => 'aux', 'person' => 3, 'number' => 'sing')
              $parent->form() =~ m/^(би(ха)?|бях)$/
            )
            {
                push(@liftnodes, $node);
            }
        }
    }
    # Lift the identified nodes.
    foreach my $node (@liftnodes)
    {
        $self->lift_node($node, 'AuxV');
    }
}



#------------------------------------------------------------------------------
# Restructures coordinations from the Mel'čukian to the Prague style.
#------------------------------------------------------------------------------
sub restructure_coordination
{
    my $self = shift;
    my $root = shift;
    my @coords;
    # Collect information about all coordination structures in the tree.
    $self->detect_coordination($root, \@coords);
    # Loop over coordinations and restructure them.
    # Hopefully the order in which the coordinations are processed is not significant.
    foreach my $c (@coords)
    {
        # The first member was the root so far. Remember its parent.
        # Remember also the afun (we assume that it has already been set according to deprel).
        my $firstmember = $c->{members}[0];
        my $parent = $firstmember->parent();
        my $afun = $firstmember->afun();
        # Get rid of the bloody warnings.
        unless(defined($afun))
        {
            $afun = '';
        }
        my $ppafun;
        # If the first member is a preposition then the real afun is one level down.
        if($afun eq 'AuxP')
        {
            my $prepcomp = $self->get_prepcomp($firstmember);
            if(defined($prepcomp))
            {
                $ppafun = $prepcomp->afun();
            }
        }
        # Select the last delimiter as the new root.
        if(!@{$c->{delimiters}})
        {
            # In fact, there is an error in the CoNLL 2007 data where this happens (the conjunction is mistakenly tagged as conjarg).
            # We have to skip such cases but we do not want to make it fatal unless we are debugging this module.
            my $debug = 0;
            if($debug)
            {
                # get_position() returns numbers from 0 but Tred numbers sentences from 1.
                my $i = $root->get_bundle()->get_position()+1;
                log_info("\#$i ".$root->get_zone()->sentence());
                log_info("Coordination members:    ".join(' ', map {$_->form()} (@{$c->{members}})));
                log_info("Coordination delimiters: ".join(' ', map {$_->form()} (@{$c->{delimiters}})));
                log_info("Coordination modifiers:  ".join(' ', map {$_->form()} (@{$c->{shared_modifiers}})));
                log_fatal("Coordination has no delimiters. What node shall I make the new coordination root?");
            }
            else
            {
                return;
            }
        }
        my $croot = pop(@{$c->{delimiters}});
        # Attach the new root to the parent of the coordination.
        $croot->set_parent($parent);
        $croot->set_afun('Coord');
        # Attach all coordination members to the new root.
        foreach my $member (@{$c->{members}})
        {
            $member->set_parent($croot);
            $member->set_is_member(1);
            my $prepcomp;
            if(defined($ppafun) && defined($prepcomp = $self->get_prepcomp($member)))
            {
                $member->set_afun('AuxP');
                $prepcomp->set_afun($ppafun);
            }
            else
            {
                $member->set_afun($afun);
            }
        }
        # Attach all remaining delimiters to the new root.
        foreach my $delimiter (@{$c->{delimiters}})
        {
            $delimiter->set_parent($croot);
            if($delimiter->conll_deprel() eq 'conj')
            {
                $delimiter->set_afun('AuxY');
            }
            elsif($delimiter->form() eq ',')
            {
                $delimiter->set_afun('AuxX');
            }
            else
            {
                $delimiter->set_afun('AuxG');
            }
        }
        # Attach all shared modifiers to the new root.
        foreach my $modifier (@{$c->{shared_modifiers}})
        {
            $modifier->set_parent($croot);
        }
    }
}



#------------------------------------------------------------------------------
# Detects coordination in Bulgarian trees.
#------------------------------------------------------------------------------
sub detect_coordination
{
    my $self = shift;
    my $root = shift;
    my $coords = shift; # reference to array where detected coordinations are collected
    # Depth-first search.
    # If a conjarg is found, find all nodes involved in the coordination.
    # Make sure that any conjargs further to the right are not later recognized as different coordination.
    # However, search their descendants for nested coordinations.
    my @children = $root->children();
    my @conjargs = grep {$_->conll_deprel() eq 'conjarg'} (@children);
    my @delimiters;
    my @sharedmod;
    if(@conjargs)
    {
        # If there is a coordination, the current root is its first member.
        unshift(@conjargs, $root);
        # Punctuation and conjunction children are supporting the coordination.
        @delimiters = grep {$_->conll_deprel() =~ m/^(conj|punct)$/} (@children);
        # Any left modifiers of the first member will be considered shared modifiers of the coordination.
        # Any right modifiers of the first member occurring after the second member will be considered shared modifiers, too.
        # Note that the Mel'čukian structure does not provide for the distinction between shared modifiers and private modifiers of the first member.
        my $ord0 = $root->ord();
        my $ord1 = $conjargs[1]->ord();
        @sharedmod = grep {($_->ord() < $ord0 || $_->ord() > $ord1) && !$_->match_iset('pos' => 'part', 'negativeness' => 'neg') && $_->conll_deprel() !~ m/^(conjarg|conj|punct)$/} (@children);
        push(@{$coords}, {'members' => \@conjargs, 'delimiters' => \@delimiters, 'shared_modifiers' => \@sharedmod});
    }
    # Call this function recursively on every child.
    foreach my $child (@children)
    {
        $self->detect_coordination($child, $coords);
    }
}



#------------------------------------------------------------------------------
# Conjunction as the first word of the sentence is attached as 'conj' to the main verb in BulTreeBank.
# In PDT, it is the root of the sentence, marked as coordination, whose only member is the main verb.
#------------------------------------------------------------------------------
sub mark_deficient_clausal_coordination
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants({ordered => 1});
    if($nodes[0]->conll_deprel() eq 'conj')
    {
        my $parent = $nodes[0]->parent();
        if($parent->conll_deprel() eq 'ROOT')
        {
            my $grandparent = $parent->parent();
            $nodes[0]->set_afun('Coord');
            $nodes[0]->set_parent($grandparent);
            $parent->set_parent($nodes[0]);
            $parent->set_is_member(1);
        }
    }
}



1;



=over

=item Treex::Block::A2A::BG::CoNLL2PDTStyle

Converts trees coming from BulTreeBank via the CoNLL-X format to the style of
the Prague Dependency Treebank. Converts tags and restructures the tree.

=back

=cut

# Copyright 2011 Dan Zeman <zeman@ufal.mff.cuni.cz>

# This file is distributed under the GNU General Public License v2. See $TMT_ROOT/README.
